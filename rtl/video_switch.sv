//============================================================================
//
//  C128 Video switch
//  Copyright (C) 2024 Erik Scheffers
//
//============================================================================

module video_switch (
   input        RESET,
   input        CLK_50M,
   input        clk_sys,
   input        clk_vdc,

   input        reset_n,
   input        c64_pause,
   input        ntsc,
   input        wide,
   input        mode,
   input  [2:0] scandoubler_fx,
   input        vdc_position,

   input        vicHsync,
   input        vicVsync,
   input  [7:0] vicR,
   input  [7:0] vicG,
   input  [7:0] vicB,

   input        vdcHsync,
   input        vdcVsync,
   input  [7:0] vdcR,
   input  [7:0] vdcG,
   input  [7:0] vdcB,

   output       clk_video,
   output       ce_pix,
   output       selected,
   output       vga_disable,
   output       hsync,
   output       vsync,
   output       hblank,
   output       vblank,
   output       ilace,
   output       field1,
   output [7:0] r,
   output [7:0] g,
   output [7:0] b
);

wire pll_locked;
wire pll_reset = pll_reset_vic | pll_reset_vdc;

pll_video pll_video
(
   .refclk(CLK_50M),
   .rst(pll_reset),
   .reconfig_to_pll(reconfig_to_pll),
   .reconfig_from_pll(reconfig_from_pll),
   .outclk_0(clk_video),
   .locked(pll_locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_video_cfg pll_video_cfg
(
   .mgmt_clk(CLK_50M),
   .mgmt_reset(0),
   .mgmt_waitrequest(cfg_waitrequest),
   .mgmt_read(0),
   .mgmt_readdata(),
   .mgmt_write(cfg_write),
   .mgmt_address(cfg_address),
   .mgmt_writedata(cfg_data),
   .reconfig_to_pll(reconfig_to_pll),
   .reconfig_from_pll(reconfig_from_pll)
);

reg  resync_req;

always @(posedge CLK_50M) begin
   reg ntscd = 0, ntscd2 = 0;
   reg selected_d = 0, selected_d2 = 0;
   reg [2:0] state = 0;
   reg ntsc_r, selected_r;

   cfg_write <= 0;

   ntscd <= ntsc;
   ntscd2 <= ntscd;
   if (ntscd2 == ntscd && ntscd2 != ntsc_r) begin
      ntsc_r <= ntscd2;
      if (selected_r)
         state <= 1;
   end

   selected_d <= selected;
   selected_d2 <= selected_d;
   if (selected_d2 == selected_d && selected_d2 != selected_r) begin
      selected_r <= selected_d2;
      state <= 1;
   end

   if(!cfg_waitrequest && pll_locked) begin
      if(state) state<=state+1'd1;
      case(state)
         1: begin
               cfg_address <= 0;
               cfg_data <= 0;
               cfg_write <= 1;
            end
         3: begin
               cfg_address <= 7;
               cfg_data <= selected_r ? (ntsc_r ? 3357876127 : 1503512573) : 2233382994;
               cfg_write <= 1;
            end
         5: begin
               cfg_address <= 2;
               cfg_data <= 0;
               cfg_write <= 1;
            end
         7: resync_req <= 1;
      endcase
   end

   if (pll_reset)
      resync_req <= 0;
end

wire vicHblank, vicVblank;
wire vicHsync_out, vicVsync_out;
wire vicIlace, vicF1, vicValid, vicCe;

video_sync videoSyncVIC (
   .reset(RESET),
   .clk32(clk_sys),
   .pause(c64_pause),
   .pixelrate((scandoubler_fx == 2) ? 3 : (scandoubler_fx == 1) ? 2 : 1),
   .hshift_r60(12'(wide ?  95 : 15)),
   .hshift_l60(12'(wide ? 141 : 56)),
   .hshift_r50(12'(wide ?  95 : 59)),
   .hshift_l50(12'(wide ? 141 : 30)),

   .hsync(vicHsync),
   .vsync(vicVsync),

   .hsync_out(vicHsync_out),
   .vsync_out(vicVsync_out),
   .hblank(vicHblank),
   .vblank(vicVblank),
   .ilace(vicIlace),
   .field(vicF1),
   .valid(vicValid),
   .ce(vicCe)
);

reg vdcShift;
always @(posedge clk_vdc) begin
   reg old_vsync;

   old_vsync <= vdcVsync_out;
   if (!old_vsync && vdcVsync_out)
      vdcShift <= vdc_position;
end

wire vdcHblank, vdcVblank;
wire vdcHsync_out, vdcVsync_out;
wire vdcIlace, vdcF1, vdcValid, vdcCe;

video_sync videoSyncVDC (
   .reset(RESET),
   .clk32(clk_vdc),
   .pause(c64_pause),
   .pixelrate(1),
   .hshift_r60(12'((vdcShift ?   0 :  28) + (wide ?  95 : 15))),
   .hshift_l60(12'((vdcShift ? 100 : 180) + (wide ? 141 : 56))),
   .hshift_r50(12'((vdcShift ?   0 :  28) + (wide ?  95 : 59))),
   .hshift_l50(12'((vdcShift ? 170 : 260) + (wide ? 141 : 30))),

   .hsync(vdcHsync),
   .vsync(vdcVsync),

   .hsync_out(vdcHsync_out),
   .vsync_out(vdcVsync_out),
   .hblank(vdcHblank),
   .vblank(vdcVblank),
   .ilace(vdcIlace),
   .field(vdcF1),
   .valid(vdcValid),
   .ce(vdcCe)
);

reg pll_reset_vic;
always @(posedge clk_sys) begin
   reg resync_req_d;
   reg last_ce;

   if (!selected || RESET) begin
      pll_reset_vic <= 0;
      resync_req_d <= 0;
   end

   last_ce <= vicCe;
   if (selected && !pll_reset_vdc) begin
      resync_req_d <= resync_req;

      if (!pll_reset_vic) begin
         if (resync_req && resync_req_d && last_ce != vicCe)
            pll_reset_vic <= 1;
      end
      else if (!resync_req)
         pll_reset_vic <= 0;
   end
end

reg pll_reset_vdc;
always @(posedge clk_vdc) begin
   reg resync_req_d;
   reg last_ce;

   if (selected || RESET) begin
      pll_reset_vdc <= 0;
      resync_req_d <= 0;
   end

   last_ce <= vdcCe;
   if (!selected && !pll_reset_vic) begin
      resync_req_d <= resync_req;
      if (!pll_reset_vdc) begin
         if (resync_req && resync_req_d && last_ce != vdcCe)
            pll_reset_vdc <= 1;
      end
      else if (!resync_req)
         pll_reset_vdc <= 0;
   end
end

wire [1:0] sel_sync = {vicVsync_out & !vicF1, vdcVsync_out & !vdcF1};
wire [1:0] valid  = {vicValid, vdcValid};
reg        switching;

always @(posedge clk_video) begin
   (* syn_encoding = "safe,johnson" *) reg [2:0] swstate;

   if (!reset_n) begin
      swstate <= 3'd1;
      switching <= 1;
   end
   else if (pll_locked && !resync_req)
      case (swstate)
         0: if (selected != mode && (sel_sync[selected] || !valid[selected])) begin
               switching <= 1;
               swstate <= 3'd1;
            end
         1: if (!sel_sync[selected] || !valid[selected]) begin
               swstate <= 3'd2;
            end
         2: if (sel_sync[selected] || !valid[selected]) begin
               swstate <= 3'd3;
            end
         3: if (sel_sync[mode]) begin
               selected <= mode;
               swstate <= 3'd4;
            end
         4: if (!sel_sync[selected]) begin
               swstate <= 3'd5;
            end
         5: if (sel_sync[selected]) begin
               switching <= 0;
               swstate <= 3'd0;
            end
      endcase
end

reg  [7:0] ro, go, bo;
reg [30:0] vids[2], vidq;

assign     vids[0] = {vdcVsync_out, vdcHsync_out, vdcVblank, vdcHblank, vdcIlace, vdcF1, ~vdcValid, vdcR, vdcG, vdcB};
assign     vids[1] = {vicVsync_out, vicHsync_out, vicVblank, vicHblank, vicIlace, vicF1, ~vicValid, vicR, vicG, vicB};
assign     {vsync, hsync, vblank, hblank, ilace, field1, vga_disable, ro, go, bo} = vidq;

assign     r = switching ? 8'h00 : ro;
assign     g = switching ? 8'h00 : go;
assign     b = switching ? (valid[mode] ? 8'h00 : 8'hCF) : bo;

reg        ce_pix_req, ce_pix_ack;
wire       ce_pix_in = selected ? vicCe : vdcCe;

always @(posedge clk_video) begin
   reg [1:0] old_ce_pix_in;

   ce_pix <= 0;
   old_ce_pix_in <= {old_ce_pix_in[0], ce_pix_in};
   if (old_ce_pix_in[1] != old_ce_pix_in[0] && old_ce_pix_in[0] == ce_pix_in && pll_locked) begin
      ce_pix <= 1;
      vidq <= vids[selected];
   end
end

endmodule
