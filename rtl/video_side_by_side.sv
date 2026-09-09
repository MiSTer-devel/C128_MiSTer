//============================================================================
//
//  C128 side-by-side video mux
//  Copyright (C) 2026 Erik Scheffers
//
//============================================================================
// VIC-clocked dual display. VIC pixels cross through a pair of line buffers;
// VDC pixels cross through a FIFO into a 1024 x 1024 RGBI framebuffer in DDR.
// No VDC sync signal participates in output timing.

module video_side_by_side #(
   // Base address in 64-bit DDR words; the framebuffer occupies 512 KiB.
   parameter [28:0] DDR_BASE_ADDR = 29'h06080000
) (
   input reset,
   input clk_vic, clk_video, clk_vdc,
   input vic_hs, vic_vs,
   input [23:0] vic_rgb,
   input vdc_ce, vdc_h, vdc_v,
   input [3:0] vdc_pixel,
   input [3:0] palette,
   output reg ce,
   output reg hs, vs, hb, vb,
   output [23:0] rgb,
   output reg [9:0] height = 270,
   output ddr_clk,
   input ddr_busy,
   output [7:0] ddr_burst,
   output [28:0] ddr_addr,
   output [63:0] ddr_din,
   output [7:0] ddr_be,
   output ddr_rd, ddr_we,
   input [63:0] ddr_dout,
   input ddr_ready
);

wire sh, sv, bh, bv;
video_sync vic_sync (
   .reset(reset), .clk32(clk_vic), .pause(1'b0),
   .hshift_r60(12'd15), .hshift_l60(12'd56),
   .hshift_r50(12'd59), .hshift_l50(12'd30),
   .hsync(vic_hs), .vsync(vic_vs),
   .hsync_out(sh), .vsync_out(sv), .hblank(bh), .vblank(bv),
   .ilace(), .field(), .valid(), .ce()
);

(* ramstyle = "M10K, no_rw_check" *) reg [23:0] vic_line[0:1023];
reg [1:0] vic_phase = 0;
reg [8:0] vic_x = 0;
reg vic_bank = 0, complete_bank = 0, complete_blank = 1, complete_vs = 0;
reg old_bh = 1, old_sh = 0;
always @(posedge clk_vic) begin
   old_bh <= bh;
   old_sh <= sh;
   vic_phase <= vic_phase + 1'd1;
   if (sh && !old_sh) vic_phase <= 0;
   if (bh) vic_x <= 0;
   else if (vic_phase == 0) begin
      if (!vic_x[8] || vic_x < 9'd511)
         vic_line[{vic_bank, vic_x}] <= vic_rgb;
      if (vic_x != 511) vic_x <= vic_x + 1'd1;
   end
   if (bh && !old_bh) begin
      complete_bank <= vic_bank;
      complete_blank <= bv;
      complete_vs <= sv;
      vic_bank <= !vic_bank;
   end
   if (reset) begin
      vic_bank <= 0;
      complete_blank <= 1;
      complete_vs <= 0;
      vic_x <= 0;
   end
end

// Pack sixteen pixels per DDR word. A short final word is flushed at the
// right edge, so widths that aren't multiples of sixteen retain their edge.
reg [10:0] wx = 0;
reg [9:0] wy = 0;
reg old_h = 0, old_v = 0;
reg [63:0] packed_pixels = 0;
reg [79:0] fifo_data;
reg fifo_wr = 0;
wire fifo_full, fifo_empty;
wire [79:0] fifo_q;
wire fifo_rd;
reg [10:0] frame_width = 0, frame_height = 0, measured_width = 0;
reg frame_toggle = 0, frame_bad = 0;

always @(posedge clk_vdc) begin
   fifo_wr <= 0;
   if (reset) begin
      wx <= 0;
      wy <= 0;
      old_h <= 0;
      old_v <= 0;
      frame_width <= 0;
      frame_height <= 0;
      frame_toggle <= 0;
      frame_bad <= 0;
   end else if (vdc_ce) begin
      old_h <= vdc_h;
      old_v <= vdc_v;
      if (vdc_v && !old_v) begin
         wy <= 0;
         measured_width <= 0;
         frame_bad <= 0;
      end
      if (!vdc_v && old_v) begin
         frame_width <= frame_bad ? 11'd0 : measured_width;
         frame_height <= frame_bad ? 11'd0 : {1'b0, wy};
         frame_toggle <= !frame_toggle;
      end
      if (vdc_h && vdc_v) begin
         packed_pixels[wx[3:0]*4 +: 4] <= vdc_pixel;
         if (wx < 1024) wx <= wx + 1'd1;
         if (&wx[3:0] && wx < 1024) begin
            fifo_data <= {wy, wx[9:4], vdc_pixel, packed_pixels[59:0]};
            fifo_wr <= !fifo_full;
            if (fifo_full) frame_bad <= 1;
         end
      end
      if (!vdc_h) begin
         wx <= 0;
         if (old_h && old_v) begin
            if (wx > measured_width) measured_width <= wx;
            if (wy != 1023) wy <= wy + 1'd1;
            if (|wx[3:0]) begin
               fifo_data <= {wy, wx[9:4], packed_pixels};
               fifo_wr <= !fifo_full;
               if (fifo_full) frame_bad <= 1;
            end
         end
      end
   end
end

dcfifo #(
   .lpm_width(80), .lpm_numwords(256), .lpm_widthu(8),
   .lpm_showahead("ON"), .overflow_checking("ON"),
   .underflow_checking("ON"), .use_eab("ON"),
   .rdsync_delaypipe(4), .wrsync_delaypipe(4)
) pixels (
   .aclr(reset), .wrclk(clk_vdc), .wrreq(fifo_wr), .data(fifo_data),
   .wrfull(fifo_full), .rdclk(clk_video), .rdreq(fifo_rd),
   .q(fifo_q), .rdempty(fifo_empty)
);

// Metadata stays constant for a field. The toggle is synchronized first;
// geometry is then applied only at the VIC frame boundary.
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] frame_sync = 0;
reg [10:0] pending_width = 0, pending_height = 0;
reg [10:0] view_width = 0, view_height = 0;
wire [10:0] fitted_height = pending_height > height ? pending_height >> 1 : pending_height;
reg shrink_x = 0, shrink_y = 0;
reg [9:0] top = 0;
always @(posedge clk_video) begin
   frame_sync <= {frame_sync[1:0], frame_toggle};
   if (frame_sync[2] != frame_sync[1]) begin
      pending_width <= frame_width;
      pending_height <= frame_height;
   end
   if (reset) begin
      pending_width <= 0;
      pending_height <= 0;
   end
end

// In dual mode clk_video uses the VIC PLL frequency and phase reference.
// Output counters run independently of DDR and VDC timing.
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] hs_sync = 0;
reg [1:0] vs_sync = 0, bank_sync = 0, blank_sync = 3;
reg [12:0] ticks = 0;
reg [12:0] period = 4032;
reg [12:0] since_hs = 0;
wire line_start = hs_sync[1] && !hs_sync[2];
// VIC lines contain an integer number of CPU cycles, each 64 output clocks.
// Round the measured period to remove clock-domain sampling uncertainty.
wire [13:0] rounded_period = {1'b0, since_hs} + 14'd33;
wire [12:0] vic_period = {rounded_period[12:6], 6'd0};
reg [9:0] line_y = 0;
reg prev_blank = 1, read_bank = 0;
reg line_blank = 1, line_vs = 0;
wire [11:0] x = ticks[12:1];
wire [10:0] screen_x = x - 11'd256;
wire [10:0] vdc_x = screen_x - 11'd768;
// A 736-pixel VIC panel leaves a 32-pixel gutter before the VDC. Crop only
// border pixels, balancing the 320-pixel display within the remaining border.
// The normalized NTSC input has nine more native pixels on its left edge.
wire [8:0] vic_read_x = screen_x[9:1] + (period >= 4096 ? 9'd18 : 9'd9);
wire [9:0] source_y = shrink_y ? ((line_y - top) << 1) : (line_y - top);
wire [9:0] source_x = shrink_x ? (vdc_x[9:0] << 1) : vdc_x[9:0];
reg [23:0] vic_q;
reg [63:0] vdc_q;
reg [3:0] nibble;
reg use_vic, use_vdc;
reg [23:0] vic_out;
wire [23:0] vdc_rgb;
reg [3:0] color;
rgbicolor colors(.palette(palette), .rgbi(color),
   .r(vdc_rgb[23:16]), .g(vdc_rgb[15:8]), .b(vdc_rgb[7:0]));
assign rgb = use_vic ? vic_out : use_vdc ? vdc_rgb : 24'd0;

// Fetch a whole VDC line early in horizontal blanking. DDR writes run
// between these bursts. If a read misses its deadline, blank that line;
// memory backpressure must never change the video counters.
(* ramstyle = "M10K, no_rw_check" *) reg [63:0] vdc_line[0:63];
reg fetch_pending = 0, line_ready = 0;
reg [9:0] fetch_y = 0;
reg [5:0] returned = 0;
localparam IDLE = 2'd0, READ_REQUEST = 2'd1, READ_DATA = 2'd2, WRITE = 2'd3;
reg [1:0] dma = IDLE;
assign ddr_clk = clk_video;
assign ddr_burst = dma == WRITE ? 8'd1 : 8'd64;
assign ddr_addr = DDR_BASE_ADDR + (dma == WRITE ? {13'd0, fifo_q[79:64]} : {13'd0, fetch_y, 6'd0});
assign ddr_din = fifo_q[63:0];
assign ddr_be = 8'hFF;
assign ddr_rd = dma == READ_REQUEST;
assign ddr_we = dma == WRITE;
assign fifo_rd = dma == WRITE && !ddr_busy;

always @(posedge clk_video) begin
   hs_sync <= {hs_sync[1:0], sh};
   // Sync and blanking describe the same buffered VIC line. In NTSC the
   // undelayed VSync would otherwise overlap the final visible output line.
   vs_sync <= {vs_sync[0], complete_vs};
   bank_sync <= {bank_sync[0], complete_bank};
   blank_sync <= {blank_sync[0], complete_blank};
   since_hs <= since_hs + 1'd1;
   ticks <= ticks == period - 1'd1 ? 13'd0 : ticks + 1'd1;
   ce <= ticks[0];
   if (line_start) begin
      if (since_hs >= 3900 && since_hs <= 4200) begin
         period <= vic_period;
      end
      since_hs <= 0;
      // Re-anchor every line. The video PLL's phase corrections otherwise
      // accumulate until a source-line handoff lands inside a visible panel.
      // Any one-clock sampling uncertainty is confined to horizontal blanking.
      ticks <= 0;
      ce <= 0;
      read_bank <= bank_sync[1];
      line_blank <= blank_sync[1];
      line_vs <= vs_sync[1];
      prev_blank <= blank_sync[1];
      if (blank_sync[1]) begin
         if (!prev_blank) height <= line_y + 1'd1;
         line_y <= 0;
      end else if (!prev_blank) line_y <= line_y + 1'd1;
      if (blank_sync[1] && !prev_blank) begin
         shrink_x <= pending_width > 768;
         shrink_y <= pending_height > height;
         view_width <= pending_width > 768 ? pending_width >> 1 : pending_width;
         view_height <= fitted_height;
         top <= fitted_height < height ? (height - fitted_height) >> 1 : 11'd0;
      end
      line_ready <= 0;
   end

   // Allow for the PAL/NTSC change in video_sync's horizontal sync offset
   // before fetching the row. 1792 clocks remain before the VDC panel.
   if (ticks == 256 && !line_blank && line_y >= top && line_y < top + view_height) begin
      fetch_pending <= 1;
   end
   case (dma)
      IDLE: if (fetch_pending) begin
         fetch_pending <= 0;
         fetch_y <= source_y;
         returned <= 0;
         dma <= READ_REQUEST;
      end else if (!fifo_empty) dma <= WRITE;
      READ_REQUEST: if (!ddr_busy) dma <= READ_DATA;
      READ_DATA: if (ddr_ready) begin
         vdc_line[returned] <= ddr_dout;
         returned <= returned + 1'd1;
         if (&returned) begin
            line_ready <= 1;
            dma <= IDLE;
         end
      end
      WRITE: if (!ddr_busy) dma <= IDLE;
   endcase

   // Synchronous RAM read, followed by pixel selection on the other phase.
   vic_q <= vic_line[{read_bank, vic_read_x}];
   vdc_q <= vdc_line[source_x[9:4]];
   nibble <= source_x[3:0];
   if (ticks[0]) begin
      vic_out <= vic_q;
      color <= vdc_q[nibble*4 +: 4];
      use_vic <= screen_x < 736 && !line_blank;
      use_vdc <= screen_x >= 768 && screen_x < 1536 &&
                 vdc_x < view_width && line_y >= top &&
                 line_y < top + view_height && line_ready && !line_blank;
      hs <= x >= 32 && x < 108;
      if (x == 128) begin
         vs <= line_vs;
         vb <= line_blank;
      end
      hb <= x < 256 || x >= 1792;
   end
   if (reset) begin
      ticks <= 0;
      line_y <= 0;
      line_blank <= 1;
      view_width <= 0;
      view_height <= 0;
      fetch_pending <= 0;
      line_ready <= 0;
      dma <= IDLE;
   end
end
endmodule
