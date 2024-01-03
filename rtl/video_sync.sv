//============================================================================
//
//  C128 Video sync
//  Copyright (C) 2023 Erik Scheffers
//
//============================================================================

module video_sync
(
	input        clk32,
   input        video_out,  // 1=VIC, 0=VDC
   input        bypass,
   input        pause,
   input        wide,

   input        hsync,
   input        vsync,

   output       hsync_out,
   output       vsync_out,
   output       hblank,
   output       vblank
);

reg[11:0] dot_count;
reg[11:0] hres;

reg[8:0]  line_count;
reg[8:0]  vres_buf[2];
wire[8:0] vres = vres_buf[0] > vres_buf[1] ? vres_buf[0] : vres_buf[1];

always @(posedge clk32) begin
   reg hsync_r0;
   reg vsync_r0;
   reg newfield;

   if (!pause) begin
      vsync_r0 <= vsync;
      if (!vsync_r0 && vsync) begin
         newfield = 1;
      end

      hsync_r0 <= hsync;
      if (!hsync_r0 && hsync) begin
         dot_count <= 0;
         hres <= dot_count;
         
         if (newfield) begin
            newfield = 0;

            line_count <= 0;
            vres_buf[0] <= vres_buf[1];
            vres_buf[1] <= line_count;
         end 
         else if (line_count < 511) begin
            line_count <= line_count + 9'd1;
         end
      end 
      else if (dot_count < 4095) begin
         dot_count <= dot_count + 12'd1;
      end
   end
end

wire[11:0] hshift_l50 = video_out ? 12'd0 : 12'd12;
wire[11:0] hshift_r50 = video_out ? 12'd0 : 12'd32;

wire[11:0] hshift_l60 = video_out ? 12'd0 : 12'd70;
wire[11:0] hshift_r60 = video_out ? 12'd0 : 12'd30;

always @(posedge clk32) begin
   if (!pause) begin
      if (!bypass && (hres >= 1994 && hres < 2103) && (vres >= 250 && vres < 272)) begin
         // NTSC
         if (dot_count == 216) hsync_out <= 0;
         if (dot_count == 64) begin
            hsync_out <= 1;
            if (line_count == 0)        vsync_out <= 1;
            if (line_count == vres-258) vsync_out <= 0;
         end

         if (line_count == 0)        vblank <= 1;
         if (line_count == vres-253) vblank <= 0;

         if (!wide) begin
            if (dot_count == (hres-3)-hshift_r60) hblank <= 1;
            if (dot_count == 460-hshift_l60)       hblank <= 0;
         end
         else begin
            if (dot_count == (hres-71)-hshift_r60) hblank <= 1;
            if (dot_count == 540-hshift_l60)       hblank <= 0;
         end
      end
      else if (!bypass && (hres >= 1994 && hres < 2103) && (vres >= 298 && vres < 329)) begin
         // PAL
         if (dot_count == 192) hsync_out <= 0;
         if (dot_count == 40) begin
            hsync_out <= 1;
            if (line_count == vres-4) vsync_out <= 1;
            if (line_count == vres)   vsync_out <= 0;
         end

         if (line_count == vres-17)  vblank <= 1;
         if (line_count == vres-287) vblank <= 0;

         if (!wide) begin
            if (dot_count == (hres-59)-hshift_r50) hblank <= 1;
            if (dot_count == 428-hshift_l50)       hblank <= 0;
         end
         else begin
            if (dot_count == (hres-151)-hshift_r50) hblank <= 1;
            if (dot_count == 544-hshift_l50)        hblank <= 0;
         end
      end
      else if (hres >= 512 && vres >= 128) begin
         // Non-standard video mode
         hblank <= hsync;
         hsync_out <= hsync;

         if (vsync) begin
            vblank <= 1;
            if (hsync_out && !hsync) vsync_out <= 1;
         end 
         else if (vsync_out) begin
            if (hsync_out && !hsync) vsync_out <= 0;
         end
         else if (vblank) begin
            if (!hsync_out && hsync) vblank <= 0;
         end
      end
      else begin
         // Illegal video mode
         hsync_out <= 0;
         vsync_out <= 0;
         hblank <= 0;
         vblank <= 0;
      end
   end
end

endmodule
