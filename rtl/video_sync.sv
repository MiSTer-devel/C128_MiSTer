//============================================================================
//
//  C128 Video sync
//  Copyright (C) 2023 Erik Scheffers
//
//============================================================================

module video_sync (
   input        reset,
	input        clk32,
   input        pause,

   input [11:0] hshift_r60,
   input [11:0] hshift_l60,
   input [11:0] hshift_r50,
   input [11:0] hshift_l50,

   input        hsync,
   input        vsync,

   output       hsync_out,
   output       vsync_out,
   output       hblank,
   output       vblank,
   output       ilace,
   output       field,
   output       valid,
   output       ce
);

reg  [11:0] dot_count;
reg  [11:0] hres;

reg   [9:0] line_count;
reg   [9:0] vres;

reg  [11:0] hsync_in_len;
reg   [9:0] vsync_in_len;
reg   [1:0] field_detect;

reg  [21:0] valid_count;

assign      valid = |valid_count;

always @(posedge clk32) begin
   reg hsync_r0;
   reg vsync_r0;
   reg newfield;

   if (reset) begin
      hsync_r0 <= 0;
      vsync_r0 <= 0;

      dot_count <= '1;
      hres <= 0;
      line_count <= '1;
      vres <= 0;

      hsync_in_len <= 0;
      vsync_in_len <= 0;

      valid_count <= 0;
   end
   else if (!pause) begin
      vsync_r0 <= vsync;
      if (!vsync_r0 && vsync) begin
         newfield = 1;
         if (hsync)
            field_detect = {field_detect[0], 1'b0};
         else
            field_detect = 2'b01;

         if (dot_count && ~&dot_count && line_count && ~&line_count)
            valid_count <= '1;
      end

      if (vsync_r0 && !vsync && !field_detect[0])
         vsync_in_len <= line_count;

      hsync_r0 <= hsync;
      if (!hsync_r0 && hsync) begin
         dot_count <= 0;
         hres <= dot_count;

         if (newfield) begin
            newfield = 0;

            line_count <= 0;

            if (!field_detect[1])
               vres <= line_count;
         end
         else if (~&line_count)
            line_count <= line_count + 9'd1;
         else if (valid_count)
            valid_count <= valid_count - 1'd1;
      end
      else if (~&dot_count)
         dot_count <= dot_count + 12'd1;
      else begin
         hres <= 0;
         vres <= 0;
         hsync_in_len <= 0;
         vsync_in_len <= 0;

         if (valid_count)
            valid_count <= valid_count - 1'd1;
      end

      if (hsync_r0 && !hsync)
         hsync_in_len <= dot_count;
   end
end

reg  [11:0] hsync_start_dot;
reg  [11:0] hsync_end_dot;

reg  [11:0] hblank_start_dot;
reg  [11:0] hblank_end_dot;

wire [11:0] hresh = hres>>1;

always_comb begin
   if (vres < 285) begin
      hblank_start_dot = 12'(hres-hshift_r60);
      hsync_start_dot  = 12'd64;
      hsync_end_dot    = 12'd216;
      hblank_end_dot   = 12'(hsync_in_len+hshift_l60);
   end
   else begin
      hblank_start_dot = 12'(hres-hshift_r50);
      hsync_start_dot  = 12'd40;
      hsync_end_dot    = 12'd192;
      hblank_end_dot   = 12'(hsync_in_len+hshift_l50);
   end
end

reg  [9:0] vsync_start_line;
reg  [9:0] vsync_len;

reg  [9:0] vblank_start_line;
reg  [9:0] vblank_len;

wire [11:0] vblank_start_dot = hsync_start_dot;
reg  [11:0] vsync_start_dot;

always @(posedge clk32) begin
   if (line_count == (vres>32 ? vres-32 : 0) && dot_count == 0) begin
      if (!field_detect && (hres >= 1994 && hres < 2103) && (vres >= 250 && vres < 272)) begin
         vblank_start_line = 9'(vres-5);
         vsync_start_line  = 9'(vres-5);
         vsync_len         = 9'd4;
         vblank_len        = 9'(vres <= 252 ? 5 : vres-247);
      end
      else if (!field_detect && (hres >= 1994 && hres < 2103) && (vres >= 298 && vres < 329)) begin
         vblank_start_line = 9'(vres-18);
         vsync_start_line  = 9'(vres-9);
         vsync_len         = 9'd4;
         vblank_len        = 9'(vres-268);
      end
      else begin
         vblank_start_line = 9'(vres-3);
         vsync_start_line  = 9'(field_detect[1] ? vres : 0);
         vsync_len         = 9'(vsync_in_len+1);
         vblank_len        = 9'(vsync_in_len+6);
      end

      if (!field_detect[1])
         vsync_start_dot = hsync_start_dot;
      else
         vsync_start_dot = hsync_start_dot >= hresh ? hsync_start_dot - hresh : hsync_start_dot + hresh;
   end
end

always @(posedge clk32) begin
   if (reset) begin
      ilace <= 0;
      field <= 0;
   end
   else if (!pause) begin
      if (dot_count == hsync_start_dot && line_count == vblank_start_line+1) begin
         ilace <= |field_detect;
         field <= field_detect[0];
      end
   end
end

always @(posedge clk32) begin
   if (reset) begin
      hblank <= 0;
      hsync_out <= 0;
   end
   else if (valid & !pause) begin
      if (dot_count == hblank_start_dot) hblank <= 1;
      if (dot_count == hsync_start_dot)  hsync_out <= 1;
      if (dot_count == hsync_end_dot)    hsync_out <= 0;
      if (dot_count == hblank_end_dot)   hblank <= 0;
   end
end

reg [9:0] vsync_cnt = 0;
reg [9:0] vblank_cnt = 0;

assign vsync_out = |vsync_cnt;
assign vblank    = |vblank_cnt;

always @(posedge clk32) begin
   if (reset) begin
      vsync_cnt <= 0;
      vblank_cnt <= 0;
   end
   else if (valid & !pause) begin
      if (dot_count == vblank_start_dot) begin
         if (line_count == vblank_start_line)
            vblank_cnt <= vblank_len;
         else if (vblank_cnt)
            vblank_cnt <= vblank_cnt-9'd1;
      end

      if (dot_count == vsync_start_dot) begin
         if (line_count == vsync_start_line)
            vsync_cnt <= vsync_len;
         else if (vsync_cnt)
            vsync_cnt <= vsync_cnt-9'd1;
      end
   end
end

reg [1:0] ce_cnt;

assign ce = ce_cnt[1];

always @(posedge clk32) begin
   reg old_vsync;

   old_vsync <= vsync_out;
   if (reset)
      ce_cnt <= 0;
   else if (!field && !old_vsync && vsync_out)
      ce_cnt <= {~ce_cnt[1], 1'b0};
   else
      ce_cnt <= ce_cnt + 1'd1;

end

endmodule
