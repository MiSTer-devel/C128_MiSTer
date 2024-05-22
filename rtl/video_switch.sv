//============================================================================
//
//  C128 Video switch
//  Copyright (C) 2024 Erik Scheffers
//
//============================================================================

module video_switch (
   input        RESET,
   input        CLK_50M,

   input        reset_n,
   input        c64_pause,
   input        ntsc,
   input        wide,
   input        mode,
   input        vdc_position,

   input        clk_vic,
   input        vicHsync,
   input        vicVsync,
   input  [7:0] vicR,
   input  [7:0] vicG,
   input  [7:0] vicB,

   input        clk_vdc,
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

reg  pll_phase_en;
reg  pll_updn;
wire pll_phase_done;
wire pll_locked;

pll_video pll_video
(
   .refclk(CLK_50M),
   .outclk_0(clk_video),
   .reconfig_to_pll(reconfig_to_pll),
   .reconfig_from_pll(reconfig_from_pll),
   .phase_en(pll_phase_en),
   .updn(pll_updn),
   .cntsel(4'd0),
   .phase_done(pll_phase_done),
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
         5: begin
               cfg_address <= 7;
               cfg_data <= selected_r ? (ntsc_r ? 3357876127 : 1503512573) : 2233382994;
               cfg_write <= 1;
            end
         7: begin
               cfg_address <= 2;
               cfg_data <= 0;
               cfg_write <= 1;
            end
      endcase
   end
end

wire vicHblank, vicVblank;
wire vicHsync_out, vicVsync_out;
wire vicIlace, vicF1, vicValid, vicCe;

video_sync videoSyncVIC (
   .reset(RESET),
   .clk32(clk_vic),
   .pause(c64_pause),
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

(* syn_encoding = "safe,johnson" *) reg [2:0] swstate;
reg mode_change;

wire [1:0] sel_sync = {vicVsync_out & !vicF1, vdcVsync_out & !vdcF1};
wire [1:0] valid    = {vicValid, vdcValid};
wire       switching = swstate != 0;

always @(posedge clk_video) begin
   mode_change <= 0;

   if (!reset_n || !pll_locked)
      swstate <= 3'd1;
   else
      case (swstate)
         0: if (selected != mode && (sel_sync[selected] || !valid[selected])) begin
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
               mode_change <= 1;
               swstate <= 3'd4;
            end
         4: if (!sel_sync[selected]) begin
               swstate <= 3'd5;
            end
         5: if (sel_sync[selected]) begin
               swstate <= 3'd0;
            end
      endcase
end

reg  [7:0] ro, go, bo;
reg [30:0] vids[2], vidout;

assign     vids[0] = {vdcVsync_out, vdcHsync_out, vdcVblank, vdcHblank, vdcIlace, vdcF1, ~vdcValid, vdcR, vdcG, vdcB};
assign     vids[1] = {vicVsync_out, vicHsync_out, vicVblank, vicHblank, vicIlace, vicF1, ~vicValid, vicR, vicG, vicB};
assign     {vsync, hsync, vblank, hblank, ilace, field1, vga_disable, ro, go, bo} = vidout;

assign     r = switching ? 8'h00 : ro;
assign     g = switching ? 8'h00 : go;
assign     b = switching ? (valid[mode] ? 8'h00 : 8'hCF) : bo;

localparam DRIFT_THRESHOLD = 8;

wire       ce_pix_in = selected ? vicCe : vdcCe;
reg        pll_shift, pll_shift_done;

always @(posedge clk_video) begin
   reg              ce_sync;
   reg        [1:0] ce_cnt;
   reg        [1:0] old_ce_pix_in;
   reg signed [4:0] pll_drift;
   reg              vsync_l;

   vsync_l <= vsync;

   old_ce_pix_in <= {old_ce_pix_in[0], ce_pix_in};
   ce_cnt <= ce_cnt + 1'd1;
   ce_pix <= 0;

   if (RESET || !pll_locked || mode_change) begin
      old_ce_pix_in <= 0;
      ce_cnt <= 0;
      ce_sync <= 0;
      vsync_l <= 0;
      pll_shift <= 0;
      pll_drift <= 0;
   end

   if (!field1 && !vsync_l && vsync) begin
      ce_sync <= 0;
   end

   if (!ce_sync && old_ce_pix_in[1] != old_ce_pix_in[0] && old_ce_pix_in[0] == ce_pix_in) begin
      ce_cnt <= 0;
      ce_sync <= 1;
      pll_drift <= 0;
   end

   if (&ce_cnt) begin
      ce_pix <= 1;
      vidout <= vids[selected];
   end

   if (pll_shift || pll_shift_done || pll_phase_en || !pll_phase_done) begin
      if (pll_shift_done) pll_shift <= 0;
      pll_drift <= 0;
   end
   else if (ce_sync && &ce_cnt && old_ce_pix_in[0] == ce_pix_in) begin
      if (old_ce_pix_in[1] == ce_pix_in) begin
         if (pll_drift < DRIFT_THRESHOLD)
            pll_drift <= pll_drift + 1'd1;
         else begin
            pll_updn <= 1;
            pll_shift <= 1;
            pll_drift <= 0;
         end
      end
      else begin
         if (pll_drift > -DRIFT_THRESHOLD)
            pll_drift <= pll_drift - 1'd1;
         else begin
            pll_updn <= 0;
            pll_shift <= 1;
            pll_drift <= 0;
         end
      end
   end
end

always @(posedge CLK_50M) begin
   (* syn_encoding = "safe,johnson" *) reg [1:0] shstate;

   pll_shift_done <= 0;
   pll_phase_en <= 0;

   if (RESET || !pll_locked)
      shstate <= 0;
   else
      case (shstate)
         0: begin
               if (pll_shift) shstate <= 1;
            end
         1: begin
               pll_phase_en <= 1;
               if (!pll_phase_done) shstate <= 2;
            end
         2: begin
               if (pll_phase_done) shstate <= 3;
            end
         3: begin
               pll_shift_done <= 1;
               if (!pll_shift) shstate <= 0;
            end
      endcase
end

endmodule
