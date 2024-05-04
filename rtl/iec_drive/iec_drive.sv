//-------------------------------------------------------------------------------
//
// C1541/C157x/C1581 selector
// (C) 2021 Alexey Melnikov
//
// Fast serial and 157x support by Erik Scheffers
//
//-------------------------------------------------------------------------------

module iec_drive #(parameter PARPORT=1,DRIVES=2)
(
   //clk ports
   input         clk,
   input   [N:0] reset,
   input         ce,

   input         pause,

   input   [1:0] drv_mode[NDR],
   input   [N:0] img_mounted,
   input         img_readonly,
   input  [31:0] img_size,
   input   [3:0] img_type,

   output  [N:0] led,
   output        disk_ready,

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

   // input  [31:0] rom_file_ext,
   input         rom_loading,
   output        rom_req,
   output [18:0] rom_addr,
   input   [7:0] rom_data,
   input         rom_wr
);

localparam NDR = (DRIVES < 1) ? 1 : (DRIVES > 4) ? 4 : DRIVES;
localparam N   = NDR - 1;

reg [N:0] img_ds;        // dual sided disk image (d71/g71)
reg [N:0] img_gcr;       // gcr enabled disk image (d64/g64/d71/g71)
reg [N:0] img_mfm;       // mfm enabled disk image (g64/g71)
reg [N:0] img_hd;        // HD (3.5") disk image (d81)
reg [3:0] rom_bank[NDR]; // ROM bank selector
always @(posedge clk_sys)
   for(int i=0; i<NDR; i=i+1) begin
      if(img_mounted[i] && img_size)
         {img_hd[i], img_mfm[i], img_gcr[i], img_ds[i]} = img_type;

      if (img_hd[i])
         rom_bank[i] = 4'((2*NDR)+i);  // 1581 ROM
      else if (drv_mode[i] == 2'b00)
         rom_bank[i] = 4'((0*NDR)+i);  // 1541 ROM
      else
         rom_bank[i] = 4'((1*NDR)+i);  // 1571 ROM
   end

wire  [14:0] mem_a[NDR], rom_addr_d[NDR];
wire  [18:0] rom_io_addr[NDR+1];
wire   [7:0] rom_do[NDR];
wire   [N:0] empty8k;
wire   [N:0] rom_valid, rom_req_d;
wire [N+1:0] rom_wr_en;

assign rom_io_addr[NDR] = 'X;
assign rom_wr_en[NDR] = 0;
assign rom_req = |rom_req_d;
assign rom_addr = rom_io_addr[0];

generate
	genvar i;
	for(i=0; i<NDR; i=i+1) begin :roms
      assign rom_wr_en[i] = rom_req_d[i] & ~rom_wr_en[i+1];
      assign rom_io_addr[i] = rom_wr_en[i] ? {rom_bank[i], rom_addr_d[i]} : rom_io_addr[i+1];
      iecdrv_rom iecdrv_rom
      (
         .clk_sys(clk_sys),
         .clk(clk),
         .reset(reset[i]),
         .rom_loading(rom_loading),

         .empty8k(empty8k[i]),
         .rom_valid(rom_valid[i]),

         .rom_bank(rom_bank[i]),
         .mem_a(mem_a[i]),
         .rom_do(rom_do[i]),

         .rom_req(rom_req_d[i]),
         .rom_addr(rom_addr_d[i]),
         .rom_wr(rom_wr & rom_wr_en[i]),
         .rom_data(rom_data)
      );
   end
endgenerate

// wire [1:0] rom_sel = rom_file_ext[15:0] == "41" ? 2'b00
//                    : rom_file_ext[15:0] == "70" ? 2'b01
//                    : rom_file_ext[15:0] == "71" ? 2'b10
//                    : rom_file_ext[15:0] == "81" ? 2'b11 : 2'bXX;

assign led          = c1581_led       | c157x_led;
assign iec_data_o   = c1581_iec_data  & c157x_iec_data;
assign iec_clk_o    = c1581_iec_clk   & c157x_iec_clk;
assign iec_fclk_o   = c1581_iec_fclk  & c157x_iec_fclk;
assign par_stb_o    = c1581_stb_o     & c157x_stb_o;
assign par_data_o   = c1581_par_o     & c157x_par_o;

always_comb for(int i=0; i<NDR; i=i+1) begin
   sd_buff_din[i] = (img_hd[i] ? c1581_sd_buff_dout[i] : c157x_sd_buff_dout[i] );
   sd_lba[i]      = (img_hd[i] ? c1581_sd_lba[i] << 1  : c157x_sd_lba[i]       );
   sd_rd[i]       = (img_hd[i] ? c1581_sd_rd[i]        : c157x_sd_rd[i]        );
   sd_wr[i]       = (img_hd[i] ? c1581_sd_wr[i]        : c157x_sd_wr[i]        );
   sd_blk_cnt[i]  = (img_hd[i] ? 6'd1                  : c157x_sd_blk_cnt[i]   );
   mem_a[i]       = (img_hd[i] ? c1581_mem_a[i]        : c157x_mem_a[i]        );
end

wire        c157x_iec_data, c157x_iec_clk, c157x_iec_fclk, c157x_stb_o;
wire  [7:0] c157x_par_o;
wire  [N:0] c157x_led;
wire  [7:0] c157x_sd_buff_dout[NDR];
wire [31:0] c157x_sd_lba[NDR];
wire  [N:0] c157x_sd_rd, c157x_sd_wr;
wire  [5:0] c157x_sd_blk_cnt[NDR];
wire [14:0] c157x_mem_a[NDR];

c157x_multi #(.PARPORT(PARPORT), .DRIVES(DRIVES)) c157x
(
   .clk(clk),
   .reset(reset | img_hd | ~rom_valid),
   .ce(ce),

   .drv_mode(drv_mode),

   .iec_atn_i (iec_atn_i),
   .iec_data_i(iec_data_i & c1581_iec_data),
   .iec_clk_i (iec_clk_i  & c1581_iec_clk),
   .iec_fclk_i(iec_fclk_i & c1581_iec_fclk),
   .iec_data_o(c157x_iec_data),
   .iec_clk_o (c157x_iec_clk),
   .iec_fclk_o(c157x_iec_fclk),

   .led(c157x_led),
   .disk_ready(disk_ready),

   .par_data_i(par_data_i),
   .par_stb_i(par_stb_i),
   .par_data_o(c157x_par_o),
   .par_stb_o(c157x_stb_o),

   .clk_sys(clk_sys),
   .pause(pause),

   // .rom_sel(rom_sel),
   // .rom_addr(rom_addr[14:0]),
   // .rom_data(rom_data),
   // .rom_wr(~&rom_sel & rom_wr),

   .mem_a(c157x_mem_a),
   .rom_do(rom_do),
   .empty8k(empty8k),

   .img_mounted(img_mounted),
   .img_size(img_size),
   .img_readonly(img_readonly),
   .img_ds(img_ds),
   .img_gcr(img_gcr),
   .img_mfm(img_mfm),

   .sd_lba(c157x_sd_lba),
   .sd_blk_cnt(c157x_sd_blk_cnt),
   .sd_rd(c157x_sd_rd),
   .sd_wr(c157x_sd_wr),
   .sd_ack(sd_ack),
   .sd_buff_addr(sd_buff_addr),
   .sd_buff_dout(sd_buff_dout),
   .sd_buff_din(c157x_sd_buff_dout),
   .sd_buff_wr(sd_buff_wr)
);


wire        c1581_iec_data, c1581_iec_clk, c1581_iec_fclk, c1581_stb_o;
wire  [7:0] c1581_par_o;
wire  [N:0] c1581_led;
wire  [7:0] c1581_sd_buff_dout[NDR];
wire [31:0] c1581_sd_lba[NDR];
wire  [N:0] c1581_sd_rd, c1581_sd_wr;
wire [14:0] c1581_mem_a[NDR];

c1581_multi #(.PARPORT(PARPORT), .DRIVES(DRIVES)) c1581
(
   .clk(clk),
   .reset(reset | ~img_hd | ~rom_valid),
   .ce(ce),

   .iec_atn_i (iec_atn_i),
   .iec_data_i(iec_data_i & c157x_iec_data),
   .iec_clk_i (iec_clk_i  & c157x_iec_clk),
   .iec_fclk_i(iec_fclk_i),
   .iec_data_o(c1581_iec_data),
   .iec_clk_o (c1581_iec_clk),
   .iec_fclk_o(c1581_iec_fclk),

   .act_led(c1581_led),

   .par_data_i(par_data_i),
   .par_stb_i(par_stb_i),
   .par_data_o(c1581_par_o),
   .par_stb_o(c1581_stb_o),

   .clk_sys(clk_sys),
   .pause(pause),

   // .rom_addr(rom_addr[14:0]),
   // .rom_data(rom_data),
   // .rom_wr(&rom_sel & rom_wr),

   .mem_a(c1581_mem_a),
   .rom_do(rom_do),

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
