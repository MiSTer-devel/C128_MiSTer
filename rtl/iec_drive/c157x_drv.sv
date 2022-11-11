//-------------------------------------------------------------------------------
//
// Reworked and adapted to MiSTer by Sorgelig@MiSTer (07.09.2018)
//
// Commodore 1541/157x to SD card by Dar (darfpga@aol.fr)
// http://darfpga.blogspot.fr
//
// c1541_logic    from : Mark McDougall
// via6522        from : Gideon Zweijtzer  <gideon.zweijtzer@gmail.com>
// c1541_track    from : Sorgelig@MiSTer
//
// c1541_logic    modified for : slow down CPU (EOI ack missed by real c64)
//                             : remove iec internal OR wired
//                             : synched atn_in (sometime no IRQ with real c64)
//
// Input clk 16MHz
//
// Extended with support for 157x models by Erik Scheffers
//
//-------------------------------------------------------------------------------

module c157x_drv #(parameter DRIVE)
(
	//clk ports
	input         clk,
	input         reset,

	input   [1:0] drv_mode,

	input         ce,
	input         wd_ce,
	input   [1:0] ph2_r,
	input   [1:0] ph2_f,

	input         img_mounted,
	input         img_readonly,
	input  [31:0] img_size,
	input         img_ds,
	input         img_gcr,
	input         img_mfm,

	output        led,

	input         iec_atn_i,
	input         iec_data_i,
	input         iec_clk_i,
	input         iec_fclk_i,
	output        iec_data_o,
	output        iec_clk_o,
	output        iec_fclk_o,

	// parallel bus
	input   [7:0] par_data_i,
	input         par_stb_i,
	output  [7:0] par_data_o,
	output        par_stb_o,

	input         ext_en,
	output [14:0] rom_addr,
	input   [7:0] rom_data,

	//clk_sys ports
	input         clk_sys,

	output [31:0] sd_lba,
	output  [5:0] sd_blk_cnt,
	output        sd_rd,
	output        sd_wr,
	input         sd_ack,
	input  [15:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr
);

localparam SD_BLK_CNT_1541 = 31;
localparam SD_BLK_CNT_157X = 52;

assign sd_blk_cnt = 6'(|drv_mode ? SD_BLK_CNT_157X : SD_BLK_CNT_1541);

assign led = act | sd_busy;

reg        readonly = 0;
reg        disk_present = 0;
reg [23:0] ch_timeout;
always @(posedge clk) begin
	reg old_mounted;

	if(ce && ch_timeout > 0) ch_timeout <= ch_timeout - 1'd1;

	old_mounted <= img_mounted;
	if (~old_mounted & img_mounted) begin
		ch_timeout <= '1;
		readonly <= img_readonly;
		disk_present <= |img_size;
	end
end

// reset drive when drive mode changes
wire reset_drv;
always @(posedge clk) begin
	reg [1:0] last_drv_mode;
	reg [3:0] reset_hold;

	if (reset) begin
		last_drv_mode <= drv_mode;
		reset_hold    <= 0;
		reset_drv	  <= 1;
	end
	else if (ph2_r[0]) begin
		last_drv_mode <= drv_mode;
		if (last_drv_mode != drv_mode) begin
			reset_hold <= '1;
			reset_drv  <= 1;
		end
		else if (reset_hold)
			reset_hold <= reset_hold - 1'd1;
		else
			reset_drv  <= 0;
	end
end

wire       mode, wgate;
wire [1:0] stp;
wire       mtr;
wire       act;
wire       fdc_busy;
wire [1:0] freq;

c157x_logic #(.DRIVE(DRIVE)) c157x_logic
(
	.clk(clk),
	.reset(reset_drv),
	.drv_mode(drv_mode),

	.wd_ce(wd_ce),
	.ph2_r(ph2_r),
	.ph2_f(ph2_f),

	// serial bus
	.iec_clk_in(iec_clk_i),
	.iec_data_in(iec_data_i),
	.iec_atn_in(iec_atn_i),
	.iec_fclk_in(iec_fclk_i),
	.iec_clk_out(iec_clk_o),
	.iec_data_out(iec_data_o),
	.iec_fclk_out(iec_fclk_o),

	.ext_en(ext_en),
	.rom_addr(rom_addr),
	.rom_data(rom_data),

	// parallel bus
	.par_data_in(par_data_i),
	.par_stb_in(par_stb_i),
	.par_data_out(par_data_o),
	.par_stb_out(par_stb_o),

	// drive signals
	.wps_n(~readonly ^ ch_timeout[22]),
	.act(act),
	.side(side),
	.mode(mode),
	.wgate(wgate),
	.fdc_busy(fdc_busy),

	// .din(dgcr_do),
	// .dout(gcr_di),
	// .mode(mode),
	.stp(stp),
	.mtr(mtr),
	.freq(freq),
	// .soe(soe),
	// .ted(ted),
	// .sync_n(dgcr_sync_n),
	// .byte_n(dgcr_byte_n),

	.hinit(hinit),
	.hclk(hclk),
	.hf(hf),
	.ht(ht),
	.tr00_sense(~|track),
	.index_sense(index),
	.drive_enable(drive_enable),
	.disk_present(disk_present),

	.img_mfm(img_mfm)
);

// wire  [7:0] gcr_di;
// assign      sd_buff_din = /*gcr_mode ? dgcr_sd_buff_dout : gcr_sd_buff_dout*/ dgcr_sd_buff_dout;

wire sd_busy;
iecdrv_sync busy_sync(clk, busy, sd_busy);

// wire [7:0]  gcr_do, gcr_sd_buff_dout;
// wire        gcr_sync_n, gcr_byte_n, gcr_we;

// c1541_gcr c1541_gcr
// (
// 	.clk(clk),
// 	.ce(ce & ~gcr_mode),
	
// 	.dout(gcr_do),
// 	.din(gcr_di),
// 	.mode(mode),
// 	.mtr(mtr),
// 	.freq(freq),
// 	.sync_n(gcr_sync_n),
// 	.byte_n(gcr_byte_n),

// 	.track(track[6:1]+1'd1),
// 	.busy(sd_busy | ~disk_present),
// 	.we(gcr_we),

// 	.sd_clk(clk_sys),
// 	.sd_lba(sd_lba),
// 	.sd_buff_addr(sd_buff_addr[12:0]),
// 	.sd_buff_dout(sd_buff_dout),
// 	.sd_buff_din(gcr_sd_buff_dout),
// 	.sd_buff_wr(sd_ack & sd_buff_wr & ~gcr_mode)
// );

// wire [7:0] dgcr_do, dgcr_sd_buff_dout;
// wire       dgcr_sync_n, dgcr_byte_n, dgcr_we, dgcr_index_n;

// c1541_direct_gcr c1541_direct_gcr
// (
// 	.clk(clk),
// 	.ce(ce /*& gcr_mode*/),
// 	.reset(reset_drv),
	
// 	// .dout(dgcr_do),
// 	// .din(gcr_di),
// 	.mode(mode),
// 	.mtr(mtr),
// 	.freq(freq),
// 	// .soe(soe),
// 	// .ted(ted),
// 	// .sync_n(dgcr_sync_n),
// 	// .byte_n(dgcr_byte_n),
// 	// .index_n(dgcr_index_n),

// 	.busy(sd_busy | ~disk_present),
// 	.we(dgcr_we),

// 	.sd_clk(clk_sys),
// 	.sd_buff_addr(sd_buff_addr),
// 	.sd_buff_dout(sd_buff_dout),
// 	.sd_buff_din(dgcr_sd_buff_dout),
// 	.sd_buff_wr(sd_ack & sd_buff_wr /*& gcr_mode*/)
// );

wire hinit, hclk, hf, ht, index, we, write, sd_update;
wire drive_enable = disk_present & mtr;

c157x_heads #(.DRIVE(DRIVE), .TRACK_BUF_LEN(SD_BLK_CNT_157X*256)) c157x_heads
(
	.clk(clk),
	.ce(ce),
	.reset(reset_drv),
	.enable(drive_enable),
	.img_ds(img_ds),
	.img_gcr(img_gcr),
	.img_mfm(img_mfm),

	.freq(freq),
	.side(side),
	.mode(mode),
	.wgate(wgate),
	.write(write),

	.hinit(hinit),
	.hclk(hclk),
	.hf(hf),
	.ht(ht),

	.index(index),

	.sd_busy(sd_busy),
	.sd_clk(clk_sys),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_ack & sd_buff_wr),
	.sd_update(sd_update)
);

wire busy;

c157x_track c157x_track
(
	.clk(clk_sys),
	.reset(reset_drv),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.freq(freq),
	
	.save_track(save_track),
	.change(img_mounted),
	.track(track),
	.busy(busy)
);

wire      side;
reg [7:0] track;
reg       save_track = 0;
always @(posedge clk) begin
	reg       track_modified;
	reg [6:0] track_num;
	reg [1:0] move, stp_old;
	reg       side_old;

	track <= track_num + (side ? 8'd84 : 8'd0);

	side_old <= side;
	stp_old <= stp;
	move <= stp - stp_old;

	if (sd_update)   track_modified <= 1;
	if (img_mounted) track_modified <= 0;

	if (reset_drv) begin
		track_num <= 36;
		side_old <= 0;
		track_modified <= 0;
	end else begin
		if (mtr) begin
			if (move[0] && !move[1] && track_num < 84) track_num <= track_num + 1'b1;
			if (move[0] &&  move[1] && track_num > 0 ) track_num <= track_num - 1'b1;
			if ((move[0] || side != side_old) && track_modified) begin
				save_track <= ~save_track;
				track_modified <= 0;
			end
		end

		if (track_modified && !write && !act && !fdc_busy && !sd_busy) begin	// stopping activity
			save_track <= ~save_track;
			track_modified <= 0;
		end
	end
end

endmodule
