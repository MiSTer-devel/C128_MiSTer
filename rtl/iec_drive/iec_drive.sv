//-------------------------------------------------------------------------------
//
// C1541/C1571/C1581/CMDHD selector
// (C) 2022 Alynna Kelly
// (C) 2021 Alexey Melnikov
//
//-------------------------------------------------------------------------------

module iec_drive #(parameter PARPORT=1,DUALROM=1,DRIVES=3)
(
	//clk ports
	input         clk,
	input   [N:0] reset,
	input         ce,

	input         pause,

	input   [N:0] img_mounted,
	input         img_readonly,
	input  [31:0] img_size,
	
	// Also see the dtype below
	// 00 - 1541/71 emulated GCR (D64,D71)
	// 01 - 1541/71 real GCR mode (G64,D64,G71,D71)
	// 10 - 1581 (D81)
	// 11 - DNP Emulated (DNP)
	
	input   [1:0] img_type,
	input         img_dblside,	// 1 when image is x71 
  input         img_mfm,      // 1 when image is MFM (1571/1581)
	input					use_1571,			// 1 when 1571 should be used on D64/G64
	output  [N:0] led,

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

	//clk_sys ports
	input         clk_sys,

	output [31:0] sd_lba[NDR],
	output  [5:0] sd_blk_cnt[NDR],
	output  [N:0] sd_rd,
	output  [N:0] sd_wr,
	input   [N:0] sd_ack,
	input  [13:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din[NDR],
	input         sd_buff_wr,

	input  [15:0] rom_addr,
	input   [7:0] rom_data,
	input         rom_wr,
	input         rom_std
);

localparam NDR = (DRIVES < 1) ? 1 : (DRIVES > 4) ? 4 : DRIVES;
localparam N   = NDR - 1;

// DTypes
//   MRDD - MFM, Raw format, Drive type
// 0:0000 - 1541/1541-II emulated
// 4:0100 - 1541/1541-II raw gcr  
// 1:0001 - 1571         emulated
// 5:0101 - 1571         raw gcr
// 9:1001 - 1571         mfm
// 3:0010 - 1581         emulated
// 6:0110 - 1581         raw gcr
// A:1010 - 1581         mfm
// 3:0011 - DNP					 generic
// 7:0111 - DNP					 cmd format
// B:1011 - Reserved     host file system format / DOS
// F:1111 - Unconnected
// all other types for future use

reg [3:0] dtype[NDR];
always @(posedge clk_sys) for(int i=0; i<NDR; i=i+1) if (img_mounted[i] && img_size) 
	dtype[i] <= { 
		( img_type == 2'b11 ? 4'b0011 :           // Native mode
		( img_type == 2'b10 ? {img_mfm, 3'b010} : // 1581 mode
		// 1571 mode if manually specified or image is double sided or MFM
		// 1541 mode otherwise.
		(	img_type[1] == 1'b0 ? {img_mfm, img_type[0], (use_1571 | img_dblside | img_mfm ? 2'b01 : 2'b00)} : 
		// Else the drive isn't hooked up at all.
		4'b1111 )))}; 
	
assign led          = c1581_led       | c1571_led				| c1541_led;
assign iec_data_o   = c1581_iec_data  & c1571_iec_data  & c1541_iec_data;
assign iec_clk_o    = c1581_iec_clk   & c1571_iec_clk   & c1541_iec_clk;
assign iec_fclk_o   = c1581_iec_fclk  & c1571_iec_fclk;
assign par_stb_o    = c1581_stb_o     & c1571_stb_o     & c1541_stb_o;
assign par_data_o   = c1581_par_o     & c1571_par_o     & c1541_par_o;

always_comb for(int i=0; i<NDR; i=i+1) begin
	sd_buff_din[i] = (dtype[i] != 4'b1111 ? (dtype[1][i] ? c1581_sd_buff_dout[i] : (dtype[0][i] : c1571_sd_buff_dout[i] : c1541_sd_buff_dout[i] )) : {8{1'bz}});
	sd_lba[i]      = (dtype[i] != 4'b1111 ? (dtype[1][i] ? c1581_sd_lba[i] << 1  : (dtype[0][i] : c1571_sd_lba[i]       : c1541_sd_lba[i]       )) : {32{1'bz}});
	sd_rd[i]       = (dtype[i] != 4'b1111 ? (dtype[1][i] ? c1581_sd_rd[i]        : (dtype[0][i] : c1571_sd_rd[i]        : c1541_sd_rd[i]        )) : 1'bz);
	sd_wr[i]       = (dtype[i] != 4'b1111 ? (dtype[1][i] ? c1581_sd_wr[i]        : (dtype[0][i] : c1571_sd_wr[i]        : c1541_sd_wr[i]        )) : 1'bz);
	sd_blk_cnt[i]  = (dtype[i] != 4'b1111 ? (dtype[1][i] ? 6'd1                  : (dtype[0][i] : c1571_sd_blk_cnt[i]   : c1541_sd_blk_cnt[i]   )) : {6{1'bz}});
end

wire        c1541_iec_data, c1541_iec_clk, c1541_stb_o;
wire  [7:0] c1541_par_o;
wire  [N:0] c1541_led;
wire  [7:0] c1541_sd_buff_dout[NDR];
wire [31:0] c1541_sd_lba[NDR];
wire  [N:0] c1541_sd_rd, c1541_sd_wr;
wire  [5:0] c1541_sd_blk_cnt[NDR];

c1541_multi #(.PARPORT(PARPORT), .DUALROM(DUALROM), .DRIVES(DRIVES)) c1541
(
	.clk(clk),
	.reset(reset & (dtype[1:0] == 2'b00)),
	.ce(ce),

	.gcr_mode(dtype[1]),

	.iec_atn_i (iec_atn_i),
	.iec_data_i(iec_data_i & c1541_iec_data),
	.iec_clk_i (iec_clk_i  & c1541_iec_clk),
	.iec_data_o(c1541_iec_data),
	.iec_clk_o (c1541_iec_clk),

	.led(c1541_led),

	.par_data_i(par_data_i),
	.par_stb_i(par_stb_i),
	.par_data_o(c1541_par_o),
	.par_stb_o(c1541_stb_o),

	.clk_sys(clk_sys),
	.pause(pause),

	.rom_addr(rom_addr[14:0]),
	.rom_data(rom_data),
	.rom_wr(~rom_addr[15] & rom_wr),
	.rom_std(rom_std),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_readonly(img_readonly),

	.sd_lba(c1541_sd_lba),
	.sd_blk_cnt(c1541_sd_blk_cnt),
	.sd_rd(c1541_sd_rd),
	.sd_wr(c1541_sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(c1541_sd_buff_dout),
	.sd_buff_wr(sd_buff_wr)
);

wire        c1571_iec_data, c1571_iec_clk, c1571_fclk, c1571_stb_o;
wire  [7:0] c1571_par_o;
wire  [N:0] c1571_led;
wire  [7:0] c1571_sd_buff_dout[NDR];
wire [31:0] c1571_sd_lba[NDR];
wire  [N:0] c1571_sd_rd, c1571_sd_wr;
wire  [5:0] c1571_sd_blk_cnt[NDR];

c1571_multi #(.PARPORT(PARPORT), .DUALROM(DUALROM), .DRIVES(DRIVES)) c1571
(
	.clk(clk),
	.reset(reset reset & (dtype[1:0] == 2'b01)),
	.ce(ce),

	.iec_atn_i (iec_atn_i),
	.iec_data_i(iec_data_i & c1571_iec_data),
	.iec_clk_i (iec_clk_i & c1571_iec_clk),
	.iec_fclk_i (iec_fclk_i & c1571_iec_fclk),
	.iec_data_o(c1571_iec_data),
	.iec_clk_o (c1571_iec_clk),

	.act_led(c1571_led),

	.par_data_i(par_data_i),
	.par_stb_i(par_stb_i),
	.par_data_o(c1571_par_o),
	.par_stb_o(c1571_stb_o),

	.clk_sys(clk_sys),
	.pause(pause),

	.rom_addr(rom_addr[14:0]),
	.rom_data(rom_data),
	.rom_wr(rom_addr[15] & rom_wr),
	.rom_std(rom_std),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_readonly(img_readonly),

	.sd_lba(c1571_sd_lba),
	.sd_blk_cnt(c1571_sd_blk_cnt),
	.sd_rd(c1571_sd_rd),
	.sd_wr(c1571_sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr[8:0]),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(c1571_sd_buff_dout),
	.sd_buff_wr(sd_buff_wr)
);

wire        c1581_iec_data, c1581_iec_clk, c1581_stb_o;
wire  [7:0] c1581_par_o;
wire  [N:0] c1581_led;
wire  [7:0] c1581_sd_buff_dout[NDR];
wire [31:0] c1581_sd_lba[NDR];
wire  [N:0] c1581_sd_rd, c1581_sd_wr;

c1581_multi #(.PARPORT(PARPORT), .DUALROM(DUALROM), .DRIVES(DRIVES)) c1581
(
	.clk(clk),
	.reset(reset & (dtype[1:0] == 2'b10)),
	.ce(ce),

	.iec_atn_i (iec_atn_i),
	.iec_data_i(iec_data_i & c1581_iec_data),
	.iec_clk_i (iec_clk_i  & c1581_iec_clk),
	.iec_fclk_i (iec_fclk_i  & c1581_iec_fclk),
	.iec_data_o(c1581_iec_data),
	.iec_clk_o (c1581_iec_clk),
	.iec_fclk_o (c1581_iec_fclk),

	.act_led(c1581_led),

	.par_data_i(par_data_i),
	.par_stb_i(par_stb_i),
	.par_data_o(c1581_par_o),
	.par_stb_o(c1581_stb_o),

	.clk_sys(clk_sys),
	.pause(pause),

	.rom_addr(rom_addr[14:0]),
	.rom_data(rom_data),
	.rom_wr(rom_addr[15] & rom_wr),
	.rom_std(rom_std),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_readonly(img_readonly),

	.sd_lba(c1581_sd_lba),
	.sd_rd(c1581_sd_rd),
	.sd_wr(c1581_sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr[8:0]),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(c1581_sd_buff_dout),
	.sd_buff_wr(sd_buff_wr)
);
endmodule
