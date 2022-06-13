//
// floppy.v
//
// Copyright (c) 2015 Till Harbaum <till@harbaum.org>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

module floppy (
	// main clock
	input        clk,
	input        clk8m_en,

	input        select,
	input        motor_on,
	input        step_in,
	input        step_out,

	input [10:0] sector_len,
	input        sector_base,    // number of first sector on track (archie 0, dos 1)
	input  [4:0] spt,            // sectors/track
	input  [9:0] sector_gap_len, // gap len/sector
	input        hd,
	input        fm,

	output 	    dclk_en,      // data clock enable
	output [6:0] track,        // number of track under head
	output [4:0] sector,       // number of sector under head, 0 = no sector
	output       sector_hdr,   // valid sector header under head
	output       sector_data,  // valid sector data under head
	       
	output       ready,        // drive is ready, data can be read
	output reg   index
);

// The sysclock is the value all floppy timings are derived from. 
// Default: 8 MHz
parameter CLK_EN = 8000;

assign sector_hdr = (sec_state == SECTOR_STATE_HDR);
assign sector_data = (sec_state == SECTOR_STATE_DATA);

// a standard DD floppy has a data rate of 250kBit/s and rotates at 300RPM
localparam RATESD          = 125000;
localparam RATEDD          = 250000;
localparam RATEHD          = 500000;
localparam RPM             = 300;
localparam STEPBUSY        = 18;    // 18ms after step data can be read
localparam SPINUP          = 500;   // drive spins up in up to 800ms
localparam SPINDOWN        = 300;   // GUESSED: drive spins down in 300ms
localparam INDEX_PULSE_LEN = 5;     // fd1036 data sheet says 1~8ms
localparam SECTOR_HDR_LEN  = 6;     // GUESSED: Sector header is 6 bytes
localparam TRACKS          = 85;    // max allowed track

// Archimedes specific values
//localparam SECTOR_LEN = 11'd1024  // Default sector size is 1024 on Archie
//localparam SECTOR_LEN = 11'd512;  // Default sector size is 512 on ST ...
//localparam SPT = 4'd10;           // ... with 5 sectors per track
//localparam SECTOR_BASE = 4'd1;    // number of first sector on track (archie 0, dos 1)

// number of physical bytes per track
localparam BPTSD = RATESD*60/(8*RPM);
localparam BPTDD = RATEDD*60/(8*RPM);
localparam BPTHD = RATEHD*60/(8*RPM);

// report disk ready if it spins at full speed
assign ready = select && (rate == (fm ? RATESD : hd ? RATEHD : RATEDD));

// ================================================================
// ========================= INDEX PULSE ==========================
// ================================================================

// Index pulse generation. Pulse starts with the begin of index_pulse_start
// and lasts INDEX_PULSE_CYCLES system clock cycles
localparam INDEX_PULSE_CYCLES = INDEX_PULSE_LEN * CLK_EN;
reg [18:0] index_pulse_cnt;
always @(posedge clk) if(clk8m_en) begin
	if(index_pulse_start && (index_pulse_cnt == INDEX_PULSE_CYCLES-1)) begin
		index <= 1'b0;
		index_pulse_cnt <= 19'd0;
	end else if(index_pulse_cnt == INDEX_PULSE_CYCLES-1)
		index <= 1'b1;
	else
		index_pulse_cnt <= index_pulse_cnt + 1'd1;
end

// ================================================================
// ======================= track handling =========================
// ================================================================

localparam STEP_BUSY_CLKS = CLK_EN*STEPBUSY;  // steprate is in ms

assign track = current_track;
reg [6:0] current_track /* verilator public */ = 7'd0;

reg step_inD;
reg step_outD;
reg [19:0] step_busy /* verilator public */;
   
always @(posedge clk) begin
	step_inD <= step_in;
	step_outD <= step_out;

	if(clk8m_en && step_busy != 0)
		step_busy <= step_busy - 18'd1;

	if(select) begin
		// rising edge of step signal starts step
		if(step_in && !step_inD) begin
			if(current_track != 0) current_track <= current_track - 7'd1;
				step_busy <= STEP_BUSY_CLKS[19:0];
		end

		if(step_out && !step_outD) begin
			if(current_track != TRACKS-1) current_track <= current_track + 7'd1;
				step_busy <= STEP_BUSY_CLKS[19:0];
		end
	end
end

// ================================================================
// ====================== sector handling =========================
// ================================================================

// track has BPT bytes
// SPT sectors are stored on the track
//localparam SECTOR_GAP_LEN = BPT/SPT - (SECTOR_LEN + SECTOR_HDR_LEN);

assign sector = current_sector;

localparam SECTOR_STATE_GAP  = 2'd0;
localparam SECTOR_STATE_HDR  = 2'd1;
localparam SECTOR_STATE_DATA = 2'd2;

// we simulate an interleave of 1
reg [4:0] start_sector = 4'd1;

reg [1:0] sec_state;
reg [9:0] sec_byte_cnt;  // counting bytes within sectors
reg [4:0] current_sector = 4'd1;
  
always @(posedge clk) begin
	if (byte_clk_en) begin
		if(index_pulse_start) begin
			sec_byte_cnt <= sector_gap_len-1'd1;
			sec_state <= SECTOR_STATE_GAP;     // track starts with gap
			current_sector <= start_sector;    // track starts with sector 1
		end else begin
			if(sec_byte_cnt == 0) begin
				case(sec_state)
				SECTOR_STATE_GAP: begin
					sec_state <= SECTOR_STATE_HDR;
					sec_byte_cnt <= SECTOR_HDR_LEN[9:0]-1'd1;
				end
	   
				SECTOR_STATE_HDR: begin
					sec_state <= SECTOR_STATE_DATA;
					sec_byte_cnt <= sector_len[9:0]-1'd1;
				end
	   
				SECTOR_STATE_DATA: begin
					sec_state <= SECTOR_STATE_GAP;
					sec_byte_cnt <= sector_gap_len-1'd1;
					if(current_sector == sector_base+spt-1) 
						current_sector <= sector_base;
					else
						current_sector <= sector + 1'd1;
					end

				default:
					sec_state <= SECTOR_STATE_GAP;
	      
				endcase
			end else
				sec_byte_cnt <= sec_byte_cnt - 10'd1;
		end
	end
end
   
// ================================================================
// ========================= BYTE CLOCK ===========================
// ================================================================

// An ed floppy at 300rpm with 1MBit/s has max 31.250 bytes/track
// thus we need to support up to 31250 events
reg [14:0] byte_cnt;
reg 	   index_pulse_start;
always @(posedge clk) begin
	if (byte_clk_en) begin
		index_pulse_start <= 1'b0;

		if(byte_cnt == ((fm ? BPTSD : hd ? BPTHD : BPTDD)-1'd1)) begin
			byte_cnt <= 0;
			index_pulse_start <= 1'b1;
		end else
			byte_cnt <= byte_cnt + 1'd1;
	end
end

// Make byte clock from bit clock.
// When a DD disk spins at 300RPM every 32us a byte passes the disk head
assign dclk_en = byte_clk_en;
reg byte_clk_en;
reg [2:0] clk_cnt2;
always @(posedge clk) begin
	byte_clk_en <= 0;
	if (data_clk_en) begin
		clk_cnt2 <= clk_cnt2 + 1'd1;
		if (clk_cnt2 == 3'b011) byte_clk_en <= 1;
	end
end

// ================================================================
// ===================== SPIN VIRTUAL DISK ========================
// ================================================================

// number of system clock cycles after which disk has reached
// full speed
localparam SPIN_UP_CLKS = CLK_EN*SPINUP;
localparam SPIN_DOWN_CLKS = CLK_EN*SPINDOWN;
reg [31:0] spin_up_counter;

// internal motor on signal that is only true if the drive is selected
wire motor_on_sel = motor_on && select;
   
// data rate determines rotation speed
reg [31:0] rate /* verilator public */ = 0;
reg motor_onD;

always @(posedge clk) begin
	motor_onD <= motor_on_sel;

	// reset spin_up counter whenever motor state changes
	if(motor_onD != motor_on_sel)
		spin_up_counter <= 32'd0;
	else if(clk8m_en) begin
		spin_up_counter <= spin_up_counter + (fm ? RATESD : hd ? RATEHD : RATEDD);
      
		if(motor_on_sel) begin
			// spinning up
			if(spin_up_counter > SPIN_UP_CLKS) begin
				if(rate < (fm ? RATESD : hd ? RATEHD : RATEDD))
					rate <= rate + 32'd1;
				spin_up_counter <= spin_up_counter - (SPIN_UP_CLKS - (fm ? RATESD : hd ? RATEHD : RATEDD));
			end
		end else begin
			// spinning down
			if(spin_up_counter > SPIN_DOWN_CLKS) begin
				if(rate > 0)
					rate <= rate - 32'd1;
				spin_up_counter <= spin_up_counter - (SPIN_DOWN_CLKS - (fm ? RATESD : hd ? RATEHD : RATEDD));
			end
		end // else: !if(motor_on)
	end // else: !if(motor_onD != motor_on)
end

// Generate a data clock from the system clock. This depends on motor
// speed and reaches the full rate when the disk rotates at 300RPM. No
// valid data can be read until the disk has reached it's full speed.
reg data_clk;
reg data_clk_en;
reg [31:0] clk_cnt;
always @(posedge clk) begin
	data_clk_en <= 0;
	if(clk8m_en) begin
		if(clk_cnt + rate > CLK_EN*1000/2) begin
			clk_cnt <= clk_cnt - (CLK_EN*1000/2 - rate);
			data_clk <= !data_clk;
			if (~data_clk) data_clk_en <= 1;
		end else
			clk_cnt <= clk_cnt + rate;
	end
end

endmodule
