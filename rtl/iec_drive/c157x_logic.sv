//-------------------------------------------------------------------------------
//
// Reworked and adapted to MiSTer by Sorgelig@MiSTer (07.09.2018)
//
// Extended with 157x models by Erik Scheffers
//
//-------------------------------------------------------------------------------
//
// Model 1541B / 1570 / 1571 
//
module c157x_logic #(DRIVE)
(
	input        clk,
	input        reset,
	input  [1:0] drv_mode,      // 00: 1541, 01: 1570, 10: 1571, (11: 1571CR todo)

	input        wd_ce,
	input  [1:0] ph2_r,
	input  [1:0] ph2_f,

	output       act,		    // activity LED

	// serial bus
	input        iec_clk_in,
	input        iec_data_in,
	input        iec_atn_in,
	input        iec_fclk_in,
	output       iec_clk_out,
	output       iec_data_out,
	output       iec_fclk_out,

	input        ext_en,
	output[14:0] rom_addr,
	input  [7:0] rom_data,

	// parallel bus
	input  [7:0] par_data_in,
	input        par_stb_in,
	output [7:0] par_data_out,
	output       par_stb_out,

	// drive control signals
	output       hinit,         // init head buffer
	input        hclk,          // bit clock
	input        hf,            // signal from head
	output       ht,            // signal to head

	output       side,          // disk side  
	input        wps_n,		    // write-protect sense
	
	output       mode,          // GCR mode (0=write, 1=read)
	output       wgate,         // MFM wgate (0=read, 1=write)
	output       fdc_busy,      // WD1770 busy
	output [1:0] stp,			// stepper motor control
	output       mtr,			// drive motor on/off
	output [1:0] freq,		    // motor frequency
	input        tr00_sense,    // track 0 sense
	input        index_sense,   // index pulse
	input        drive_enable,  // sd busy
	input        disk_present,

	input        img_mfm        // mfm supported by disk image
);

// clock control
reg [2:0] accl;
always @(posedge clk)
begin
	if (~|drv_mode)
		accl <= 3'b000;
	else if (ph2_r[accl[1]]) 
		accl <= {accl[1:0],accl_ctl};
end

wire halt  = accl[0]^accl[2];
wire ena_f = ph2_f[accl[1]] & ~halt;
wire ena_r = ph2_r[accl[1]] & ~halt;

// cpu signal decode
assign rom_addr = cpu_a[14:0];

//same decoder as on real HW
wire [3:0] ls42 = {cpu_a[15], cpu_a[12:10]};   
wire ram_cs    = |drv_mode ? cpu_a[15:12] == 0 || cpu_a[15:13] == 3            : ls42 == 0 || ls42 == 1;
wire via1_cs   = |drv_mode ? cpu_a[15:12] == 1 && cpu_a[10] == 0               : ls42 == 6;
wire via2_cs   = |drv_mode ? cpu_a[15:12] == 1 && cpu_a[10] == 1               : ls42 == 7;
wire wd_cs     = |drv_mode ? cpu_a[15:13] == 1                                 : 1'b0;
wire cia_cs    = |drv_mode ? cpu_a[15:13] == 2 && (~&drv_mode | cpu_a[4] == 0) : 1'b0;
// wire scrram_cs = &drv_mode ? cpu_a[15:13] == 2 && cpu_a[4] == 1                : 1'b0;
wire rom_cs    = cpu_a[15];

wire  [7:0] cpu_di =
	!cpu_rw    ? cpu_do :
	 ram_cs    ? ram_do :
	 via1_cs   ? via1_do :
	 via2_cs   ? via2_do :
	 wd_cs     ? wd_do :
	 cia_cs    ? cia_do :
	//  scrram_cs ? scrram_do :
	 extram_cs ? extram_do :
	 rom_cs    ? rom_data :
	 8'hFF;

wire [23:0] cpu_a;
wire  [7:0] cpu_do;
wire        cpu_rw;
wire        cpu_irq_n = ~(via1_irq | via2_irq) & cia_irq_n;

T65 cpu
(
	.mode(2'b00),
	.res_n(~reset),
	.enable(ena_f),
	.clk(clk),
	.rdy(1'b1),
	.abort_n(1'b1),
	.irq_n(cpu_irq_n),
	.nmi_n(1'b1),
	.so_n(byte_n),
	.r_w_n(cpu_rw),
	.A(cpu_a),
	.DI(cpu_di),
	.DO(cpu_do)
);

// optional 8k RAM at $8000-$9FFF for custom roms

wire extram_cs = ext_en && (cpu_a[15:13] == 'b100);

wire [7:0] extram_do;
iecdrv_mem #(8,13) extram
(
	.clock_a(clk),
	.address_a(cpu_a[12:0]),
	.data_a(cpu_do),
	.wren_a(ena_r & ~cpu_rw & extram_cs),

	.clock_b(clk),
	.address_b(cpu_a[12:0]),
	.q_b(extram_do)
);

// system 2k RAM at $0000-$07FF

wire [7:0] ram_do;
iecdrv_mem #(8,11) ram
(
	.clock_a(clk),
	.address_a(cpu_a[10:0]),
	.data_a(cpu_do),
	.wren_a(ena_r & ~cpu_rw & ram_cs),

	.clock_b(clk),
	.address_b(cpu_a[10:0]),
	.q_b(ram_do)
);

// 8 bytes scratch RAM at $4010-$4017 (1571CR only)

// wire [7:0] scrram_do;
// iecdrv_mem #(8,3) scrram
// (
// 	.clock_a(clk),
// 	.address_a(cpu_a[2:0]),
// 	.data_a(cpu_do),
// 	.wren_a(ena_r & ~cpu_rw & scrram_cs),

// 	.clock_b(clk),
// 	.address_b(cpu_a[2:0]),
// 	.q_b(scrram_do)
// );

// VIA1 1571-U9 (6522) signals

wire [7:0] via1_do;
wire       via1_irq;
wire [7:0] via1_pa_o;
wire [7:0] via1_pa_oe;
wire       via1_ca2_o;
wire       via1_ca2_oe;
wire [7:0] via1_pb_o;
wire [7:0] via1_pb_oe;
wire       via1_cb1_o;
wire       via1_cb1_oe;
wire       via1_cb2_o;
wire       via1_cb2_oe;

wire       fser_dir     = (via1_pa_o[1] | ~via1_pa_oe[1]) & |drv_mode;
assign     side         = (via1_pa_o[2] | ~via1_pa_oe[2]) &  drv_mode[1];
wire       accl_ctl     = (via1_pa_o[5] | ~via1_pa_oe[5]) & |drv_mode;

assign     iec_data_out = ~(via1_pb_o[1] | ~via1_pb_oe[1]) & ~((via1_pb_o[4] | ~via1_pb_oe[4]) ^ ~iec_atn_in) & (~fser_dir | cia_sp_out);
assign     iec_clk_out  = ~(via1_pb_o[3] | ~via1_pb_oe[3]);

assign     par_stb_out  = |drv_mode ?  cia_pc_n               : (via1_ca2_o | ~via1_ca2_oe);
assign     par_data_out = |drv_mode ? (cia_pb_o | ~cia_pb_oe) : (via1_pa_o  | ~via1_pa_oe);

iecdrv_via6522 via1
(
	.clock(clk),
	.rising(ena_r),
	.falling(ena_f),
	.reset(reset),

	.addr(cpu_a[3:0]),
	.wen(~cpu_rw & via1_cs),
	.ren(cpu_rw & via1_cs),
	.data_in(cpu_do),
	.data_out(via1_do),

	.port_a_o(via1_pa_o),
	.port_a_t(via1_pa_oe),                     
	.port_a_i(ext_en & ~|drv_mode ? par_data_in : {byte_n | ~|drv_mode, 6'h3F, ~tr00_sense} & (via1_pa_o | ~via1_pa_oe)),

	.port_b_o(via1_pb_o),
	.port_b_t(via1_pb_oe),
	.port_b_i({~iec_atn_in, 2'(DRIVE), 2'b11, ~iec_clk_in, 1'b1, ~iec_data_in} & (via1_pb_o | ~via1_pb_oe)),

	.ca1_i(~iec_atn_in),

	.ca2_o(via1_ca2_o),
	.ca2_t(via1_ca2_oe),
	.ca2_i(wps_n & (via1_ca2_o | ~via1_ca2_oe)),

	.cb1_o(via1_cb1_o),
	.cb1_t(via1_cb1_oe),
	.cb1_i(((ext_en & ~&drv_mode) ? par_stb_in : 1'b1) & (via1_cb1_o | ~via1_cb1_oe)),

	.cb2_o(via1_cb2_o),
	.cb2_t(via1_cb2_oe),
	.cb2_i(via1_cb2_o | ~via1_cb2_oe),

	.irq(via1_irq)
);

// VIA2 1571-U4 (6522) signals

wire [7:0] via2_do;
wire       via2_irq;
wire [7:0] via2_pa_o;
wire [7:0] via2_pa_oe;
wire       via2_ca2_o;
wire       via2_ca2_oe;
wire [7:0] via2_pb_o;
wire [7:0] via2_pb_oe;
wire       via2_cb1_o;
wire       via2_cb1_oe;
wire       via2_cb2_o;
wire       via2_cb2_oe;

wire       ted    = via2_cs    | ~accl[2];
wire       soe    = via2_ca2_o | ~via2_ca2_oe;
wire [7:0] gcr_di = via2_pa_o  | ~via2_pa_oe;

assign     stp    = via2_pb_o[1:0] | ~via2_pb_oe[1:0];
assign     mtr    = via2_pb_o[2]   | ~via2_pb_oe[2];
assign     act    = via2_pb_o[3]   | ~via2_pb_oe[3];
assign     freq   = via2_pb_o[6:5] | ~via2_pb_oe[6:5];
assign     mode   = via2_cb2_o     | ~via2_cb2_oe;

iecdrv_via6522 via2
(
	.clock(clk),
	.rising(ena_r),
	.falling(ena_f),
	.reset(reset),

	.addr(cpu_a[3:0]),
	.wen(~cpu_rw & via2_cs),
	.ren(cpu_rw & via2_cs),
	.data_in(cpu_do),
	.data_out(via2_do),

	.port_a_o(via2_pa_o),
	.port_a_t(via2_pa_oe),
	.port_a_i(gcr_do & gcr_di),

	.port_b_o(via2_pb_o),
	.port_b_t(via2_pb_oe),
	.port_b_i({sync_n, 2'b11, wps_n, 4'b1111} & (via2_pb_o | ~via2_pb_oe)),

	.ca1_i(byte_n),

	.ca2_o(via2_ca2_o),
	.ca2_t(via2_ca2_oe),
	.ca2_i(via2_ca2_o | ~via2_ca2_oe),

	.cb1_o(via2_cb1_o),
	.cb1_t(via2_cb1_oe),
	.cb1_i(via2_cb1_o | ~via2_cb1_oe),

	.cb2_o(via2_cb2_o),
	.cb2_t(via2_cb2_oe),
	.cb2_i(via2_cb2_o | ~via2_cb2_oe),

	.irq(via2_irq)
);

// CIA 1571-U20 (6526/5710) signals

wire [7:0] cia_do;
wire       cia_irq_n;
wire [7:0] cia_pa_o, cia_pa_oe, cia_pb_o, cia_pb_oe;
wire       cia_pc_n;

wire       cia_sp_out;
wire       cia_cnt_out;

assign     iec_fclk_out = ~fser_dir | cia_cnt_out;

mos6526_8520 cia
(
	.res_n(~reset & |drv_mode),
	.clk(clk),
	.mode(&drv_mode ? 2'b11 : 2'b00),
	.phi2_p(ena_f),
	.phi2_n(ena_r),
	.cs_n(~cia_cs),
	.rw(cpu_rw),

	.rs(cpu_a[3:0]),
	.db_in(cpu_do),
	.db_out(cia_do),

	.pa_out(cia_pa_o),
	.pa_oe(cia_pa_oe),
	.pa_in(cia_pa_o | ~cia_pa_oe),

	.pb_out(cia_pb_o),
	.pb_oe(cia_pb_oe),
	.pb_in((ext_en ? par_data_in : 8'hff) & (cia_pb_o | ~cia_pb_oe)),

	.pc_n(cia_pc_n),

	.flag_n(ext_en ? par_stb_in : 1'b1),

	.tod(1'b1),

	.sp_in(fser_dir | iec_data_in),
	.sp_out(cia_sp_out),

	.cnt_in(fser_dir | iec_fclk_in),
	.cnt_out(cia_cnt_out),

	.irq_n(cia_irq_n)
);

// Head signals mux

assign     ht = gcr_ht | (mfm_ht & |drv_mode);
assign     hinit = gcr_hinit | (mfm_hinit & |drv_mode);

// 64H156 1571-U6 signals

wire [7:0] gcr_do;
wire       sync_n, byte_n, dgcr_we;
wire       gcr_ht, gcr_hinit;

c157x_h156 c157x_h156
(
	.clk(clk),
	.reset(reset),
	.enable(drive_enable),
	.mhz1_2(accl[1]),
	
	.hinit(gcr_hinit),
	.hclk(hclk),
	.ht(gcr_ht),
	.hf(hf),

	.mode(mode),
	.soe(soe),
	.ted(ted),
	.sync_n(sync_n),
	.byte_n(byte_n),

	.dout(gcr_do),
	.din(gcr_di)
);

// FDC 1571-U11 (WD1770) signals

wire [7:0] wd_do;
wire       mfm_ht, mfm_hinit;
wire       mfm_wgate;

assign     wgate = mfm_wgate & |drv_mode;

c157x_fdc1772 #(.MODEL(0)) c157x_fdc1772
(
	.clkcpu(clk),
	.clk8m_en(wd_ce),

	.floppy_reset(~reset & |drv_mode),
	.floppy_present(disk_present),
	// .floppy_side(side),
	.floppy_motor(mtr),
	.floppy_index(~index_sense),
	.floppy_wprot(~(wps_n & img_mfm)),
	.floppy_track00(1),

	.hinit(mfm_hinit),
	.hclk(hclk),
	.ht(mfm_ht),
	.hf(hf),
	.wgate(mfm_wgate),
	.busy(fdc_busy),

	.cpu_addr(cpu_a[1:0]),
	.cpu_sel(wd_cs),
	.cpu_rw(cpu_rw | ~ena_r),
	.cpu_din(cpu_do),
	.cpu_dout(wd_do)
);

endmodule
