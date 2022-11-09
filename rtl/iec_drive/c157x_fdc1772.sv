// Floppy disk controller of the 1570/1571.
//
// Based on fdc1772.v by Till Harbaum <till@harbaum.org>,
// modified by Erik Scheffers to process externally generated MFM bit stream

module c157x_fdc1772
(
    input            clkcpu,
    input            clk8m_en,

    // external set signals
    input            floppy_reset,
    input            floppy_present,
    input            floppy_motor,
    output           floppy_ready,
    input            floppy_index,
    input            floppy_wprot,
    input            floppy_track00,

    // control signals
    output reg       irq,
    output reg       drq,
    output           busy,

    // signals to/from heads
    output           hinit,
    input            hclk,
    output           ht,
    input            hf,
    output           wgate,

    // CPU interface
    input      [1:0] cpu_addr,
    input            cpu_sel,
    input            cpu_rw,
    input      [7:0] cpu_din,
    output reg [7:0] cpu_dout
);

assign busy = cmd_busy;

parameter CLK_EN           = 16'd8000; // in kHz
parameter MODEL            = 0;    // 0 - wd1770, 1 - fd1771, 2 - wd1772, 3 = wd1773/fd1793

parameter SYNC_A1_PATTERN  = 16'h4489; // "A1" sync pattern
parameter SYNC_C2_PATTERN  = 16'h5224; // "C2" sync pattern
parameter SYNC_A1_CRC      = 16'hCDB4; // CRC after 3 "A1" syncs

localparam INDEX_PULSE_CYCLES = 16'd5*CLK_EN;                                // duration of an index pulse, 5ms
localparam SETTLING_DELAY     = MODEL == 2 ? 19'd15*CLK_EN : 19'd30*CLK_EN;  // head settling delay, 15 ms (WD1772) or 30 ms (others)
localparam MIN_BUSY_TIME      = 16'd6*CLK_EN;                                // minimum busy time, 6ms

// -------------------------------------------------------------------------
// ---------------------------- IRQ/DRQ handling ---------------------------
// -------------------------------------------------------------------------
reg cpu_selD;
reg cpu_rwD;
always @(posedge clkcpu) begin
    cpu_rwD <= cpu_sel & ~cpu_rw;
    cpu_selD <= cpu_sel;
end

wire cpu_we = cpu_sel & ~cpu_rw & ~cpu_rwD;

// floppy_reset and read of status register/write of command register clears irq
reg cpu_rw_cmdstatus;
always @(posedge clkcpu)
  cpu_rw_cmdstatus <= ~cpu_selD && cpu_sel && cpu_addr == FDC_REG_CMDSTATUS;

wire status_clr = !floppy_reset || cpu_rw_cmdstatus;

reg irq_set;

always @(posedge clkcpu)
    if (status_clr) irq <= 0;
    else if (irq_set) irq <= 1;

// floppy_reset and read/write of data register read clears drq

reg drq_set;

reg cpu_rw_data;
always @(posedge clkcpu)
    cpu_rw_data <= ~cpu_selD && cpu_sel && cpu_addr == FDC_REG_DATA;

wire drq_clr = !floppy_reset || cpu_rw_data;

always @(posedge clkcpu)
    if (drq_clr) drq <= 0;
    else if (drq_set) drq <= 1;

// -------------------------------------------------------------------------
// -------------------- virtual floppy drive mechanics ---------------------
// -------------------------------------------------------------------------

reg       fd_index;
wire      fd_ready = floppy_motor;
wire      fd_dclk_en = clk8m_en & aligned;
reg [7:0] fd_track;
reg [7:0] fd_sector;
reg       fd_sector_hdr_valid;
wire      fd_present = floppy_present;
wire      fd_writeprot = floppy_wprot;
wire      fd_trk00 = floppy_track00;

assign floppy_ready = fd_ready && fd_present;

// -------------------------------------------------------------------------
// ----------------------- internal state machines -------------------------
// -------------------------------------------------------------------------

// ------------------------- Index pulse handling --------------------------

reg indexD;

localparam INDEX_COUNT_START = 3'd6;
reg [2:0] index_pulse_counter;

always @(posedge clkcpu) begin
    reg        last_floppy_index;
    reg [18:0] index_pulse_cnt;

    last_floppy_index <= floppy_index;
    if (!floppy_reset || !fd_present) begin
        index_pulse_cnt <= 0;
        fd_index <= 0;
    end
    else if (last_floppy_index && ~floppy_index) begin
        index_pulse_cnt <= INDEX_PULSE_CYCLES;
        fd_index <= 1;
    end
    else if (clk8m_en) begin
        if (index_pulse_cnt != 0) begin
            index_pulse_cnt <= index_pulse_cnt - 1'd1;
        end
        else
            fd_index <= 0;
    end
end

// --------------------------- Motor handling ------------------------------

// if motor is off and type 1 command with "spin up sequnce" bit 3 set
// is received then the command is executed after the motor has
// reached full speed for 5 rotations (800ms spin-up time + 5*200ms =
// 1.8sec) If the floppy is idle for 10 rotations (2 sec) then the
// motor is switched off again
localparam MOTOR_IDLE_COUNTER = 4'd10;
reg [3:0] motor_timeout_index;
reg cmd_busy;
reg [3:0] motor_spin_up_sequence;

// consider spin up done either if the motor is not supposed to spin at all or
// if it's supposed to run and has left the spin up sequence
wire motor_spin_up_done = (!motor_on) || (motor_on && (motor_spin_up_sequence == 0));

// ---------------------------- step handling ------------------------------

// the step rate is only valid for command type I
wire [15:0] step_rate_clk =
           (cmd_flag_r==2'b00)             ? (16'd6 *CLK_EN-1'd1):   //  6ms
           (cmd_flag_r==2'b01)             ? (16'd12*CLK_EN-1'd1):   // 12ms
           (MODEL==2 && cmd_flag_r==2'b10) ? (16'd2 *CLK_EN-1'd1):   //  2ms
           (cmd_flag_r==2'b10)             ? (16'd20*CLK_EN-1'd1):   // 20ms
           (MODEL==2)                      ? (16'd3 *CLK_EN-1'd1):   //  3ms
                                             (16'd30*CLK_EN-1'd1);   // 30ms

reg [15:0] step_rate_cnt;
reg [23:0] delay_cnt;

// flag indicating that a "step" is in progress
wire step_busy = (step_rate_cnt != 0);
wire delaying = (delay_cnt != 0);

reg [7:0] step_to;
reg RNF;
reg ctl_busy;
reg idle;
reg sector_inc_strobe;
reg track_inc_strobe;
reg track_dec_strobe;
reg track_clear_strobe;
reg address_update_strobe;

always @(posedge clkcpu) begin
    reg  [1:0] seek_state;
    reg        notready_wait;
    reg        irq_req;
    reg [15:0] min_busy_cnt;

    sector_inc_strobe <= 0;
    track_inc_strobe <= 0;
    track_dec_strobe <= 0;
    track_clear_strobe <= 0;
    address_update_strobe <= 0;

    irq_set <= 0;
    irq_req <= 0;
    data_transfer_start <= 0;

    if (status_clr && !cmd_busy) idle <= 1;

    if (!floppy_reset) begin
        motor_on <= 0;
        idle <= 1;
        ctl_busy <= 0;
        cmd_busy <= 0;
        seek_state <= 0;
        notready_wait <= 0;
        RNF <= 0;
        index_pulse_counter <= 0;
    end
    else if (clk8m_en) begin
        // step rate timer
        if (step_rate_cnt != 0)
            step_rate_cnt <= step_rate_cnt - 1'd1;

        // delay timer
        if (delay_cnt != 0)
            delay_cnt <= delay_cnt - 1'd1;

        // minimum busy timer
        if (min_busy_cnt != 0)
            min_busy_cnt <= min_busy_cnt - 1'd1;
        else if (!ctl_busy) begin
            cmd_busy <= 0;
            irq_set <= irq_req;
        end

        // just received a new command
        if (cmd_rx) begin
            idle <= 0;
            ctl_busy <= 1;
            cmd_busy <= 1;
            min_busy_cnt <= MIN_BUSY_TIME;
            notready_wait <= 0;

            if (cmd_type_1 || cmd_type_2 || cmd_type_3) begin
                RNF <= 0;
                motor_on <= 1;
                // 'h' flag '0' -> wait for spin up
                if (!motor_on && !cmd_flag_h) motor_spin_up_sequence <= 6;   // wait for 6 full rotations
            end

            if (cmd_type_2 || cmd_type_3)
                index_pulse_counter <= INDEX_COUNT_START;

            // handle "forced interrupt"
            if (cmd_stop) begin
                ctl_busy <= 0;
                cmd_busy <= 0;
                min_busy_cnt <= 0;
                // From Hatari: Starting a Force Int command when idle should set the motor bit and clear the spinup bit (verified on STF)
                if (!ctl_busy) motor_on <= 1;
            end
        end

        // immediate interrupt request
        if (cmd_stop_imm) irq_req <= 1;

        // execute command if motor is not supposed to be running or
        // wait for motor spinup to finish
        if (ctl_busy && motor_spin_up_done && !step_busy && !delaying) begin

            // ------------------------ TYPE I -------------------------
            if (cmd_type_1) begin
                if (!fd_present) begin
                    // no image selected -> send irq after 6 ms
                    if (!notready_wait) begin
                        delay_cnt <= 16'd6*CLK_EN;
                        notready_wait <= 1;
                    end
                    else begin
                        RNF <= 1;
                        ctl_busy <= 0;
                        irq_set <= 1; // emit irq when command done
                    end
                end
                else
                    // evaluate command
                    case (seek_state)
                        0: begin
                            // restore / seek
                            if (cmd_restore || cmd_seek) begin
                                if (cmd_restore && !fd_trk00) begin
                                    track_clear_strobe <= 1;
                                    seek_state <= 2;
                                end
                                else if (track == step_to)
                                    seek_state <= 2;
                                else begin
                                    step_dir <= (step_to < track);
                                    seek_state <= 1;
                                end
                            end

                            // step
                            if (cmd_step_to)
                                seek_state <= 1;

                            // step in/out
                            if (cmd_step) begin
                                step_dir <= cmd_flag_d;
                                seek_state <= 1;
                            end
                        end

                        // do the step
                        1: begin
                            // update the track register if seek/restore or the update flag set
                            if (cmd_restore || cmd_seek || cmd_flag_u)
                                if (step_dir)
                                    track_dec_strobe <= 1;
                                else
                                    track_inc_strobe <= 1;

                            step_rate_cnt <= step_rate_clk;

                            seek_state <= (cmd_restore || cmd_seek) ? 0 : 2; // loop for seek/restore
                        end

                        // verify
                        2: begin
                            if (cmd_flag_v)
                                delay_cnt <= SETTLING_DELAY; // TODO: implement verify, now just delay

                            seek_state <= 3;
                        end

                        // finish
                        3: begin
                            ctl_busy <= 0;
                            irq_req <= 1; // emit irq when command done
                            seek_state <= 0;
                        end
                    endcase
            end // if (cmd_type_1)

            // ------------------------ TYPE II -------------------------
            if (cmd_type_2) begin
                // read/write sector
                if (!fd_present) begin
                    // no image selected -> send irq after 6 ms
                    if (!notready_wait) begin
                        delay_cnt <= 16'd6*CLK_EN;
                        notready_wait <= 1;
                    end
                    else begin
                        RNF <= 1;
                        ctl_busy <= 0;
                        irq_set <= 1; // emit irq when command done
                    end
                end
                else if (cmd_flag_e && !notready_wait) begin
                    // e flag: 15/30 ms settling delay
                    delay_cnt <= SETTLING_DELAY;
                    notready_wait <= 1;
                end
                else if (cmd_wr_sec && fd_writeprot) begin
                    // abort if write protect enabled
                    ctl_busy <= 0;
                    irq_req <= 1; // emit irq when command done
                end
                else if ((!cmd_rx && index_pulse_counter == 0) || data_transfer_done) begin
                    if (!data_transfer_done)
                        RNF <= 1;

                    if (data_transfer_done && cmd_flag_m)
                        sector_inc_strobe <= 1; // multiple sector transfer
                    else begin
                        ctl_busy <= 0;
                        irq_req <= 1; // emit irq when command done
                    end
                end
                else if (!data_transfer_active && fd_sector_hdr_valid && fd_track == track && fd_sector == sector) begin
                    data_transfer_start <= 1;
                end
            end

            // ------------------------ TYPE III -------------------------
            if (cmd_type_3) begin
                if (!fd_present) begin
                    // no image selected -> send irq immediately
                    RNF <= 1;
                    ctl_busy <= 0;
                    irq_req <= 1; // emit irq when command done
                end
                else begin
                    // read track
                    if (cmd_rd_trk) begin
                        // TODO (not used by 1571 rom)
                        ctl_busy <= 0;
                        irq_req <= 1; // emit irq when command done
                    end

                    // write track
                    if (cmd_wr_trk) begin
                        // write track
                        if (!fd_present) begin
                            // no image selected -> send irq after 6 ms
                            if (!notready_wait) begin
                                delay_cnt <= 16'd6*CLK_EN;
                                notready_wait <= 1;
                            end
                            else begin
                                RNF <= 1;
                                ctl_busy <= 0;
                                irq_set <= 1; // emit irq when command done
                            end
                        end
                        else if (cmd_flag_e && !notready_wait) begin
                            // e flag: 15/30 ms settling delay
                            delay_cnt <= SETTLING_DELAY;
                            notready_wait <= 1;
                        end
                        else if (fd_writeprot || data_transfer_done) begin
                            ctl_busy <= 0;
                            irq_req <= 1; // emit irq when command done
                        end
                        else if (!data_transfer_active)
                            data_transfer_start <= 1;
                    end

                    // read address (used in 1571 rom)
                    if (cmd_rd_adr) begin
                        if ((!cmd_rx && index_pulse_counter == 0) || data_transfer_done) begin
                            if (data_transfer_done)
                                address_update_strobe <= 1;
                            else
                                RNF <= 1;

                            ctl_busy <= 0;
                            irq_req <= 1; // emit irq when command done
                        end
                        else if (!data_transfer_active && fd_dclk_en && idam_detected)
                            data_transfer_start <= 1;
                    end
                end
            end
        end

        // stop motor if there was no command for 10 index pulses
        indexD <= fd_index;
        if (!indexD && fd_index) begin
            // interrupt at index pulse requested
            if (cmd_stop_idx) irq_req <= 1;

            // let motor timeout run once fdc is not busy anymore
            if (!ctl_busy && motor_spin_up_done) begin
                if (motor_timeout_index != 0)
                    motor_timeout_index <= motor_timeout_index - 1'd1;
                else if (motor_on)
                    motor_timeout_index <= MOTOR_IDLE_COUNTER;

                if (motor_timeout_index == 1)
                    motor_on <= 0;
            end

            if (motor_spin_up_sequence != 0)
                motor_spin_up_sequence <= motor_spin_up_sequence - 1'd1;

            if (ctl_busy && motor_spin_up_done && index_pulse_counter != 0)
                index_pulse_counter <= index_pulse_counter - 1'd1;
        end

        if (ctl_busy)
            motor_timeout_index <= 0;
        else if (!cmd_rx)
            index_pulse_counter <= 0;
    end
end

// floppy delivers data at a floppy generated rate (usually 250kbit/s), so the start and stop
// signals need to be passed forth and back from cpu clock domain to floppy data clock domain
reg data_transfer_start;
reg data_transfer_done;

// Sync detector, byte aligner

reg  [15:0] shift_in_reg, shift_out_reg;
wire [15:0] shift_in = { shift_in_reg[14:0], hf };
reg   [3:0] shift_count;
reg         shift_out_enable;

assign      ht    = shift_out_reg[15];
assign      wgate = shift_out_enable;

wire sync_a1 = (shift_in == SYNC_A1_PATTERN);
wire sync_c2 = (shift_in == SYNC_C2_PATTERN);
wire sync    = (sync_a1 || sync_c2);

reg       aligned;
reg [7:0] aligned_data;
reg       aligned_sync_a1, aligned_sync_c2;

always @(posedge clkcpu)
begin
    if (!floppy_reset || clk8m_en)
        aligned <= 0;

    if (!floppy_reset || !fd_ready) begin
        shift_count      <= 4'd15;
        shift_out_reg    <= 0;
        shift_out_enable <= 0;
        aligned_data     <= 0;
        aligned_sync_a1  <= 0;
        aligned_sync_c2  <= 0;
        aligned          <= 0;
    end
    else if (hclk) begin
        if (write_out_strobe) begin
            shift_count      <= 4'd15;
            shift_out_reg    <= write_out;
            shift_out_enable <= 1;
        end
        else if (shift_out_enable) begin
            shift_out_reg <= { shift_out_reg[14:0], 1'b0 };
            shift_count   <= shift_count - 1'd1;
            if (shift_count == 1) aligned <= 1;
            if (shift_count == 0) shift_out_enable <= 0;
        end
        else begin
            shift_in_reg <= shift_in;
            shift_count  <= shift_count - 1'd1;

            if ((align_on_sync && sync) || !shift_count)
            begin
                shift_count     <= 4'd15;
                aligned_data    <= { shift_in[14], shift_in[12], shift_in[10], shift_in[8], shift_in[6], shift_in[4], shift_in[2], shift_in[0] };
                aligned_sync_a1 <= align_on_sync && sync_a1;
                aligned_sync_c2 <= align_on_sync && sync_c2;
                aligned         <= 1;
            end
        end
    end
end

// mark detector and header decoder

reg        data_mark;
reg  [1:0] sector_size_code;
reg        align_on_sync;
reg  [2:0] sync_detected;
reg [10:0] data_read_count; // including CRC bytes
reg  [7:0] data_read;
reg        fd_track_updated;
reg        crc_error_hdr, crc_error_data;
wire       crc_error = crc_error_data | crc_error_hdr;
reg        dam_detected, idam_detected;

function [10:0] sector_size;
    input [1:0] code;
    begin
        sector_size = {4'd1 << code, 7'd0};
    end
endfunction

function [15:0] crc;
    input [15:0] curcrc;
    input  [7:0] val;
    reg    [3:0] i;
    begin
        crc = {curcrc[15:8] ^ val, 8'h00};
        for (i = 0; i < 8; i=i+1'd1) begin
            if (crc[15]) begin
                crc = crc << 1;
                crc = crc ^ 16'h1021;
            end
            else crc = crc << 1;
        end
        crc = {curcrc[7:0] ^ crc[15:8], crc[7:0]};
    end
endfunction

always @(posedge clkcpu)
begin
    reg        last_sync_a1;
    reg        read_header, read_data;
    reg [15:0] crcchk;

    if (!floppy_reset || !fd_ready || cmd_rx) begin
        crc_error_data      <= 0;
        crc_error_hdr       <= 0;
        align_on_sync       <= 1;
        read_header         <= 0;
        read_data           <= 0;
        data_read_count     <= 0;
        fd_sector_hdr_valid <= 0;
        crcchk              <= 16'hFFFF;
        sync_detected       <= 0;
        idam_detected       <= 0;
        dam_detected        <= 0;
    end
    else if (fd_dclk_en) begin
        crcchk <= aligned_sync_a1 ? SYNC_A1_CRC : crc(crcchk, aligned_data);

        if (aligned_sync_a1 || aligned_sync_c2) begin
            last_sync_a1 <= aligned_sync_a1;
            if (aligned_sync_a1 != last_sync_a1)
                sync_detected <= 1'd1;
            else if (sync_detected < 4)
                sync_detected <= sync_detected + 1'd1;

            read_header <= 0;
            read_data   <= 0;
            data_read_count  <= 0;
            fd_sector_hdr_valid <= 0;
        end
        else begin
            sync_detected <= 0;
            idam_detected <= 0;
            dam_detected  <= 0;

            if (sync_detected >= 3 && aligned_data[7:2] == 6'b1111_10) begin
                // DDAM = F8/F9, DAM = FA/FB
                data_mark    <= ~aligned_data[1];
                dam_detected <= 1;
                if (!cmd_rd_trk)  // disable sync detection, unless we are reading a track
                    align_on_sync <= 0;
            end
            else if (sync_detected == 3 && aligned_data[7:1] == 7'b1111_111) begin
                // IDAM = FE..FF
                idam_detected <= 1;
                if (!cmd_rd_trk)  // disable sync detection, unless we are reading a track
                    align_on_sync <= 0;
            end
            else if (idam_detected || read_header) begin
                data_read <= aligned_data;
                if (idam_detected) begin
                    fd_track        <= aligned_data;
                    data_read_count <= 11'd6;
                    read_header     <= 1;
                end
                else begin
                    data_read_count <= data_read_count - 1'd1;
                    case(data_read_count)
                        5: fd_sector        <= aligned_data;
                        4: sector_size_code <= aligned_data[1:0];
                    endcase
                end
                // header_byte <= 1;
            end
            else if (dam_detected || read_data) begin
                data_read <= aligned_data;
                if (dam_detected) begin
                    data_read_count <= sector_size(sector_size_code) + 11'd2;
                    read_data       <= 1;
                end
                else begin
                    data_read_count <= data_read_count - 1'd1;
                end
            end

            if (data_read_count == 1) begin
                read_data     <= 0;
                read_header   <= 0;
                align_on_sync <= 1;

                if (crcchk && cmd_busy) begin
                    if (read_data   && cmd_rd_sec)  crc_error_data <= 1;
                    if (read_header && cmd_rd_adr) crc_error_hdr  <= 1;
                end

                if (read_header && !crcchk)
                    fd_sector_hdr_valid <= 1;
            end
        end
    end
end

// -------------------- CPU data read/write -----------------------
reg        data_in_strobe, write_out_strobe;
reg [15:0] write_out;

typedef enum bit[3:0] {
    // transfer idle
    XF_IDLE,
    // read address
    XF_RDAD,
    // read sector
    XF_RDSC, XF_RDSC_DATA,
    // write sector
    XF_WRSC, XF_WRSC_SYNC, XF_WRSC_DATA, XF_WRSC_CRC,
    // write track
    XF_WRTR, XF_WRTR_DATA, XF_WRTR_CRC
} xfer_state_t;

function [15:0] mfm_encode;
    input  [8:0] data;
    reg    [7:0] clock;
    begin
        clock = ~(data[8:1]|data[7:0]);
        mfm_encode = {
            clock[7], data[7],
            clock[6], data[6],
            clock[5], data[5],
            clock[4], data[4],
            clock[3], data[3],
            clock[2], data[2],
            clock[1], data[1],
            clock[0], data[0]
        };
    end
endfunction

xfer_state_t xfer_state = XF_IDLE;

wire       data_transfer_active = xfer_state != XF_IDLE;
wire [7:0] data_in_drq = drq ? 8'h00 : data_in;
wire [7:0] DAM = cmd_flag_a ? 8'hF8 : 8'hFB;

always @(posedge clkcpu) begin
    reg [12:0] xfer_cnt;
    reg [15:0] crccalc;

    drq_set <= 0;
    hinit <= 0;

    if (!cmd_busy || (!cmd_rd_adr && !cmd_rd_sec && !cmd_rd_trk))
        data_out <= data_in;

    if (!floppy_reset || !fd_ready || (cmd_rx && cmd_stop)) begin
        xfer_cnt <= 0;
        xfer_state <= XF_IDLE;
        crccalc <= 16'hFFFF;
        write_out_strobe <= 0;
        data_transfer_done <= 0;
    end

    if (!floppy_reset || (cmd_rx && !cmd_stop))
        data_lost <= 0;

    if (clk8m_en) data_transfer_done <= 0;
    if (hclk) write_out_strobe <= 0;
    if (data_transfer_start) begin
        // read address
        if (cmd_rd_adr) begin
            xfer_state <= XF_RDAD;
            xfer_cnt <= 13'd6;
        end

        // read sector
        if (cmd_rd_sec) begin
            xfer_state <= XF_RDSC;
            xfer_cnt <= 13'd43;
        end

        // todo read track

        // write sector
        if (cmd_wr_sec) begin
            xfer_state <= XF_WRSC;
            xfer_cnt <= 13'd22;
        end

        // write track
        if (cmd_wr_trk) begin
            xfer_state <= XF_WRTR;
            xfer_cnt <= 13'd3;
            drq_set <= 1;
        end
    end

    if (fd_dclk_en) begin
        case(xfer_state)
            // read sector / read address

            XF_RDSC: begin
                // Read sector: wait 43 bytes for DAM
                xfer_cnt <= xfer_cnt - 1'd1;
                if (!xfer_cnt) begin
                    // no DAM seen, abort
                    xfer_state <= XF_IDLE;
                end
                else if (dam_detected) begin
                    // DAM detected, start transfering data
                    xfer_state <= XF_RDSC_DATA;
                    xfer_cnt <= sector_size(sector_size_code);
                end
            end

            XF_RDAD,
            XF_RDSC_DATA: begin
                // Read sector & read address: transfer data to cpu
                if (xfer_cnt) begin
                    if (drq)
                        data_lost <= 1;

                    drq_set <= 1;
                    data_out <= data_read;
                    xfer_cnt <= xfer_cnt - 1'd1;
                end
                else if (!data_read_count) begin
                    data_transfer_done <= 1;
                    xfer_state <= XF_IDLE;
                end
            end

            // write sector

            XF_WRSC: begin
                // Write sector: delay 22 gap bytes
                if (xfer_cnt) begin
                    xfer_cnt <= xfer_cnt - 1'd1;
                    if (xfer_cnt == 20)
                        drq_set <= 1;

                    if (xfer_cnt == 11 && drq) begin
                        // abort when no data received from cpu
                        xfer_state <= XF_IDLE;
                        data_lost <= 1;
                        data_transfer_done <= 1;
                        xfer_cnt <= 0;
                    end
                end
                else begin
                    xfer_state <= XF_WRSC_SYNC;
                    xfer_cnt <= 13'd16;
                end
            end

            XF_WRSC_SYNC: begin
                // Write sector: write preamble and address mark (12 "00" bytes, 3 "A1" sync markers and 1 DAM or DDAM byte)
                if (xfer_cnt) begin
                    // write A1 sync
                    xfer_cnt <= xfer_cnt - 1'd1;
                    write_out_strobe <= 1;
                    write_out <= xfer_cnt > 3 ? mfm_encode(9'h000) : SYNC_A1_PATTERN;
                end
                else begin
                    // write address mark, initialize CRC
                    write_out_strobe <= 1;
                    write_out <= mfm_encode({SYNC_A1_PATTERN[0], DAM});
                    crccalc <= crc(SYNC_A1_CRC, DAM);
                    xfer_state <= XF_WRSC_DATA;
                    xfer_cnt <= sector_size(sector_size_code);
                end
            end

            XF_WRSC_DATA: begin
                // Write sector: transfer data from CPU to disk, update CRC
                xfer_cnt <= xfer_cnt - 1'd1;

                if (drq)
                    data_lost <= 1;

                if (xfer_cnt > 1)
                    drq_set <= 1;

                write_out_strobe <= 1;
                write_out <= mfm_encode({write_out[0], data_in_drq});
                crccalc <= crc(crccalc, data_in_drq);

                if (xfer_cnt == 1) begin
                    xfer_state <= XF_WRSC_CRC;
                    xfer_cnt <= 13'd3;
                end
            end

            XF_WRSC_CRC: begin
                // Write sector: write 2 CRC bytes, 1 trailing "FF" byte
                if (xfer_cnt) begin
                    xfer_cnt <= xfer_cnt - 1'd1;
                    crccalc <= {crccalc[7:0], 8'hFF};
                    write_out_strobe <= 1;
                    write_out <= mfm_encode({write_out[0], crccalc[15:8]});
                end
                else begin
                    xfer_state <= XF_IDLE;
                    data_transfer_done <= 1;
                end
            end

            // write track

            XF_WRTR: begin
                // Write track: wait 3 bytes for data from CPU, initialize CRC and signal initialization state to heads module
                if (xfer_cnt) begin
                    xfer_cnt <= xfer_cnt - 1'd1;
                end
                else if (drq) begin
                    // no data received from CPU, abort
                    data_lost <= 1;
                    data_transfer_done <= 1;
                end
                else begin
                    // set up track initialization state
                    xfer_state <= XF_WRTR_DATA;
                    xfer_cnt <= 13'd6250; // track buffer is exactly 12500 bytes, or 6250 MFM encoded bytes
                    crccalc <= 16'hFFFF;
                    hinit <= 1;
                end
            end

            XF_WRTR_DATA: begin
                // Write track: receive and decode data from CPU, update CRC
                if (xfer_cnt) begin
                    xfer_cnt <= xfer_cnt - 1'd1;

                    drq_set <= 1;
                    if (drq)
                        data_lost <= 1;

                    write_out_strobe <= 1;
                    case(data_in_drq)
                        8'hF5: begin
                            // write A1 sync, initialize CRC
                            write_out <= SYNC_A1_PATTERN;
                            crccalc <= SYNC_A1_CRC;
                        end

                        8'hF6: begin
                            // write C2 sync, update CRC
                            write_out <= SYNC_C2_PATTERN;
                            crccalc <= crc(crccalc, 8'hC2);
                        end

                        8'hF7: begin
                            // write first CRC byte, switch to XF_WRTR_CRC state
                            write_out <= mfm_encode({write_out[0], crccalc[15:8]});
                            xfer_state <= XF_WRTR_CRC;
                        end

                        default: begin
                            // write received data, update CRC
                            write_out <= mfm_encode({write_out[0], data_in_drq});
                            crccalc <= crc(crccalc, data_in_drq);
                        end
                    endcase
                end
                else begin
                    xfer_state <= XF_IDLE;
                    data_transfer_done <= 1;
                end
            end

            XF_WRTR_CRC: begin
                // Write track: write second CRC byte, reset CRC to zero, return to XF_WRTR_DATA state
                if (xfer_cnt)
                    xfer_cnt <= xfer_cnt - 1'd1;

                write_out_strobe <= 1;
                write_out <= mfm_encode(crccalc[8:0]);
                crccalc <= 16'h0000;
                xfer_state <= XF_WRTR_DATA;
            end
        endcase
    end
end

wire [7:0] status = { (MODEL == 1 || MODEL == 3) ? !floppy_ready : motor_on,
              (cmd_wr_sec | cmd_wr_trk | cmd_type_1) & fd_writeprot, // wrprot (only for write!)
              cmd_type_1?motor_spin_up_done:data_mark,    // data mark
              (crc_error&&!cmd_type_1)?crc_error_hdr:RNF, // seek error/record not found/crc error type
              crc_error,                                  // crc error
              (idle||cmd_type_1)?~fd_trk00:data_lost,     // track0/data lost
              (idle||cmd_type_1)?~fd_index:drq,           // index mark/drq
              cmd_busy } /* synthesis keep */;

reg [7:0] track;
reg [7:0] sector;
reg [7:0] data_in;
reg [7:0] data_out;

reg step_dir;
reg motor_on = 0;
reg data_lost = 0;

// ---------------------------- command register -----------------------
reg [7:0] cmd;
wire cmd_type_1   = cmd[7]   == 1'b0;
wire cmd_restore  = cmd[7:4] == 4'b0000;
wire cmd_seek     = cmd[7:4] == 4'b0001;
wire cmd_step_to  = cmd[7:5] == 3'b001;
wire cmd_step     = cmd[7:6] == 3'b01;

wire cmd_type_2   = cmd[7:6] == 2'b10;
wire cmd_rd_sec   = cmd[7:5] == 3'b100;
wire cmd_wr_sec   = cmd[7:5] == 3'b101;

wire cmd_type_3   = cmd[7:5] == 3'b111 || cmd[7:4] == 4'b1100;
wire cmd_rd_adr   = cmd[7:4] == 4'b1100;
wire cmd_rd_trk   = cmd[7:4] == 4'b1110;
wire cmd_wr_trk   = cmd[7:4] == 4'b1111;

wire cmd_type_4   = cmd[7:4] == 4'b1101;
wire cmd_stop     = cmd_type_4;
wire cmd_stop_idx = cmd_stop && cmd[2];
wire cmd_stop_imm = cmd_stop && cmd[3];

wire [1:0] cmd_flag_r = cmd[1:0];
wire       cmd_flag_a = cmd[0];
wire       cmd_flag_p = cmd[1];
wire       cmd_flag_v = cmd[2];
wire       cmd_flag_e = cmd[2];
wire       cmd_flag_h = cmd[3];
wire       cmd_flag_m = cmd[4];
wire       cmd_flag_u = cmd[4];
wire       cmd_flag_d = cmd[5];

localparam FDC_REG_CMDSTATUS = 0;
localparam FDC_REG_TRACK     = 1;
localparam FDC_REG_SECTOR    = 2;
localparam FDC_REG_DATA      = 3;

// CPU register read
always @(*) begin
    cpu_dout = 8'h00;

    if (cpu_sel && cpu_rw) begin
        case(cpu_addr)
            FDC_REG_CMDSTATUS: cpu_dout = status;
            FDC_REG_TRACK:     cpu_dout = track;
            FDC_REG_SECTOR:    cpu_dout = sector;
            FDC_REG_DATA:      cpu_dout = data_out;
        endcase
    end
end

// cpu register write
reg cmd_rx;
reg cmd_rx_i;

always @(posedge clkcpu) begin
    if (!floppy_reset) begin
        cmd <= 8'h00;
        cmd_rx <= 0;
        cmd_rx_i <= 0;
        track <= 8'h00;
        sector <= 8'h00;
    end
    else begin
        // cmd_rx is delayed to make sure all signals (the cmd!) are stable when
        // cmd_rx is evaluated
        cmd_rx <= cmd_rx_i;

        // command reception is ack'd by fdc going busy
        if ((!cmd_stop && ctl_busy) || (clk8m_en && cmd_stop && !ctl_busy)) cmd_rx_i <= 0;

        if (cpu_we) begin
            // command
            if (cpu_addr == FDC_REG_CMDSTATUS && (!cmd_busy || cpu_din[7:4] == 4'b1101)) begin
                cmd <= cpu_din;
                cmd_rx_i <= 1;

                // ------------- TYPE I commands -------------
                if (cpu_din[7:4] == 4'b0000) begin               // RESTORE
                    step_to <= 8'd0;
                    track <= 8'hff;
                end

                if (cpu_din[7:4] == 4'b0001) begin               // SEEK
                    step_to <= data_in;
                end
            end

            // track register
            if (cpu_addr == FDC_REG_TRACK && !cmd_busy)
                track <= cpu_din;

            // sector register
            if (cpu_addr == FDC_REG_SECTOR && !cmd_busy)
                sector <= cpu_din;

            // data register
            if (cpu_addr == FDC_REG_DATA)
                data_in <= cpu_din;
        end

        if (address_update_strobe) sector <= fd_track; // "read address" command updates *sector* register to current track
        if (sector_inc_strobe) sector <= sector + 1'd1;
        if (track_inc_strobe) track <= track + 1'd1;
        if (track_dec_strobe) track <= track - 1'd1;
        if (track_clear_strobe) track <= 8'd0;
    end
end

endmodule
