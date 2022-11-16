//-------------------------------------------------------------------------------
//
// C1541/157x multi-drive implementation with shared ROM
// (C) 2021 Alexey Melnikov
//
// Input clock/ce 16MHz
//
// Extended with support for 157x models by Erik Scheffers
//
//-------------------------------------------------------------------------------


module c157x_multi #(parameter PARPORT=1,DRIVES=2)
(
	//clk ports
	input         clk,
	input   [N:0] reset,
	input         ce,

	input   [1:0] drv_mode[NDR],

	input         pause,

	input   [N:0] img_mounted,
	input         img_readonly,
	input  [31:0] img_size,
	input   [N:0] img_ds,
	input   [N:0] img_gcr,
	input   [N:0] img_mfm,

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
	input  [15:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din[NDR],
	input         sd_buff_wr,

	input   [1:0] rom_sel,
	input  [14:0] rom_addr,
	input   [7:0] rom_data,
	input         rom_wr
);

localparam NDR = (DRIVES < 1) ? 1 : (DRIVES > 4) ? 4 : DRIVES;
localparam N   = NDR - 1;

wire iec_atn, iec_data, iec_clk, iec_fclk;
iecdrv_sync  atn_sync(clk, iec_atn_i,  iec_atn);
iecdrv_sync  dat_sync(clk, iec_data_i, iec_data);
iecdrv_sync  clk_sync(clk, iec_clk_i,  iec_clk);
iecdrv_sync fclk_sync(clk, iec_fclk_i, iec_fclk);

wire [N:0] reset_drv;
iecdrv_sync #(NDR) rst_sync(clk, reset, reset_drv);

reg [1:0] ph2_r;
reg [1:0] ph2_f;
reg       wd_ce;
always @(posedge clk) begin
	reg [3:0] div;
	reg       ena, ena1;

	ena1 <= ~pause;
	if(div[2:0]) ena <= ena1;

	ph2_r <= 0;
	ph2_f <= 0;
	wd_ce  <= 0;
	if(ce) begin
		div <= div + 1'd1;
		// 1 MHz clock
		ph2_r[0] <= ena && !div[3] && !div[2:0];
		ph2_f[0] <= ena &&  div[3] && !div[2:0];
		// 2 MHz clock
		ph2_f[1] <= ena &&  div[2] && !div[1:0];
		ph2_r[1] <= ena && !div[2] && !div[1:0];
		// 8 MHz WD1770 clock
		wd_ce <= ena && !div[0];
	end
end

reg rom_32k_i[4];
reg rom_16k_i[4];
reg empty8k[4];
always @(posedge clk_sys) begin
	if (rom_wr & !rom_addr) empty8k[rom_sel] <= 1;
	if (rom_wr & |rom_data & ~&rom_data) begin
		{rom_32k_i[rom_sel], rom_16k_i[rom_sel]} <= rom_addr[14:13];
		if(rom_addr[14:8] && !rom_addr[14:13]) empty8k[rom_sel] <= 0;
	end
end

reg [1:0] rom_sz[4];
always @(posedge clk) for(int i=0; i<4; i++) rom_sz[i] <= {rom_32k_i[i],rom_32k_i[i]|rom_16k_i[i]}; // support for 8K/16K/32K ROM

initial begin
	rom_32k_i = '{0,1,1,1};
	rom_16k_i = '{1,1,1,1};
	empty8k   = '{0,0,0,0};
end

wire [7:0] rom_do[3];
iecdrv_mem #(8,15,"rtl/iec_drive/c1541_rom.mif") rom1541
(
	.clock_a(clk_sys),
	.address_a(rom_addr),
	.data_a(rom_data),
	.wren_a(rom_sel == 0 ? rom_wr : 0),

	.clock_b(clk),
	.address_b(mem_a),
	.q_b(rom_do[0])
);

iecdrv_mem #(8,15,"rtl/iec_drive/c1570_rom.mif") rom1570
(
	.clock_a(clk_sys),
	.address_a(rom_addr),
	.data_a(rom_data),
	.wren_a(rom_sel == 1 ? rom_wr : 0),

	.clock_b(clk),
	.address_b(mem_a),
	.q_b(rom_do[1])
);

iecdrv_mem #(8,15,"rtl/iec_drive/c1571_rom.mif") rom1571
(
	.clock_a(clk_sys),
	.address_a(rom_addr),
	.data_a(rom_data),
	.wren_a(rom_sel == 2 ? rom_wr : 0),

	.clock_b(clk),
	.address_b(mem_a),
	.q_b(rom_do[2])
);

// iecdrv_mem #(8,15,"rtl/iec_drive/c1571cr_rom.mif") rom1571cr
// (
// 	.clock_a(clk_sys),
// 	.address_a(rom_addr),
// 	.data_a(rom_data),
// 	.wren_a(rom_sel == 3 ? rom_wr : 0),

// 	.clock_b(clk),
// 	.address_b(mem_a),
// 	.q_b(rom_do[3])
// );

reg  [14:0] mem_a;
wire [14:0] drv_addr[NDR];
reg   [7:0] drv_data[NDR];
always @(posedge clk) begin
	reg [2:0] state;
	reg [14:0] mem_d;
	
	if(~&state)  state <= state + 1'd1;
	if(ph2_f[1]) state <= 0;

	for(int i=0; i<NDR; i=i+1) begin
 		if (state == i)   mem_a <= { drv_addr[i][14:13] & rom_sz[drv_mode[i]], drv_addr[i][12:0] };
		if (state == i+3) drv_data[i] <= rom_do[drv_mode[i]];
	end
end

wire [N:0] iec_data_d, iec_clk_d, iec_fclk_d;
iecdrv_reset_filter #(NDR) (clk, reset_drv, iec_clk_d, iec_clk_o);
iecdrv_reset_filter #(NDR) (clk, reset_drv, iec_data_d, iec_data_o);
iecdrv_reset_filter #(NDR) (clk, reset_drv, iec_fclk_d, iec_fclk_o);

wire [N:0] ext_en;
wire [7:0] par_data_d[NDR];
wire [N:0] par_stb_d;
assign     par_stb_o = &{par_stb_d | ~ext_en};
always_comb begin
	par_data_o = 8'hFF;
 	for(int i=0; i<NDR; i=i+1) begin
	 	ext_en[i] = rom_sz[drv_mode[i]][1] & empty8k[drv_mode[i]] & |PARPORT & ~&drv_mode[i] & ~reset_drv[i];
		if (ext_en[i]) par_data_o = par_data_o & par_data_d[i];
	end
end

wire [N:0] led_drv;
assign     led = led_drv & ~reset_drv;

generate
	genvar i;
	for(i=0; i<NDR; i=i+1) begin :drives
		c157x_drv #(i) c157x_drv
		(
			.clk(clk),
			.reset(reset_drv[i]),
			.drv_mode(drv_mode[i]),

			.ce(ce),
			.wd_ce(wd_ce),
			.ph2_r(ph2_r),
			.ph2_f(ph2_f),

			.img_mounted(img_mounted[i]),
			.img_readonly(img_readonly),
			.img_size(img_size),
			.img_ds(img_ds[i]),
			.img_gcr(img_gcr[i]),
			.img_mfm(img_mfm[i]),

			.led(led_drv[i]),

			.iec_atn_i(iec_atn),
			.iec_data_i(iec_data & iec_data_o),
			.iec_clk_i(iec_clk & iec_clk_o),
			.iec_fclk_i(iec_fclk & iec_fclk_o),
			.iec_data_o(iec_data_d[i]),
			.iec_clk_o(iec_clk_d[i]),
			.iec_fclk_o(iec_fclk_d[i]),

			.par_data_i(par_data_i),
			.par_stb_i(par_stb_i),
			.par_data_o(par_data_d[i]),
			.par_stb_o(par_stb_d[i]),

			.ext_en(ext_en[i]),
			.rom_addr(drv_addr[i]),
			.rom_data(drv_data[i]),

			.clk_sys(clk_sys),

			.sd_lba(sd_lba[i]),
			.sd_blk_cnt(sd_blk_cnt[i]),
			.sd_rd(sd_rd[i]),
			.sd_wr(sd_wr[i]),
			.sd_ack(sd_ack[i]),
			.sd_buff_addr(sd_buff_addr),
			.sd_buff_dout(sd_buff_dout),
			.sd_buff_din(sd_buff_din[i]),
			.sd_buff_wr(sd_buff_wr)
		);
	end
endgenerate

endmodule
