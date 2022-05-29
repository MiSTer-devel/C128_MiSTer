/********************************************************************************
 * Commodore 128 VDC
 * 
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 *
 * - timings not yet verified
 ********************************************************************************/

module vdc_video #(
	parameter 		S_LATCH_WIDTH,
	parameter 		A_LATCH_WIDTH,
	parameter 		C_LATCH_WIDTH
)(
	input    [1:0] version,   // 0=8563R7A, 1=8563R9, 2=8568

	input          clk,
	input          reset,
	input          enable,

   input    [1:0] reg_cm,                     // cursor mode
   input    [4:0] reg_cs,                     // cursor line start
   input    [4:0] reg_ce,                     // cursor line end
	input   [15:0] reg_cp,                     // cursor position address
                 
   input    [4:0] reg_ul,                     // underline position
   input          reg_cbrate,                 // character blink rate
	input          reg_text,                   // text/bitmap mode
	input          reg_atr,                    // attribute enable
   input          reg_semi,                   // semi-graphics mode 
   input          reg_rvs,                    // reverse video
   input    [3:0] reg_fg,                     // foreground color
   input    [3:0] reg_bg,                     // background color
                 
   input    [4:0] reg_vss,                    // vertical smooth scroll
   input    [3:0] reg_hss,                    // horizontal smooth scroll
               
	input          newFrame,                   // start of new frame
	input          newLine,                    // start of new line
	input          newRow,                     // start of new visible row
	input          newCol,                     // start of new column
               
   input          visible,                    // in visible part of display
   input          blank,                      // in blanking part of display
	input 			currbuf,                    // buffer containing current screen info
	input    [7:0] scrnbuf[2][S_LATCH_WIDTH],  // screen codes for current and next row
	input    [7:0] attrbuf[2][A_LATCH_WIDTH],  // latch for attributes for current and next row
	input    [7:0] charbuf[C_LATCH_WIDTH],     // character data for current line
   input          rowaddr,                    // address of current row

   output   [3:0] rgbi
);

always @(posedge clk) begin
   reg  [7:0] col;
   reg  [4:0] line;
   reg [15:0] coladdr;

   // reg [7:0] char;
   // reg [7:0] attr;   bit 6=rvs, 5=ul, 4=blink 3:0=rgbi

   if (reset) begin
      col <= 0;
      line <= 0;
   end
   else if (enable) begin
      if (newLine) begin
         col <= 0;
         if (newRow)
            line <= 0;
         else
            line <= line + 5'd1;
      end

      if (newCol) begin
         col <= col + 8'd1;
      end

      if (blank)
         rgbi <= 0;
      else if (visible) 
         rgbi <= 4'(col+line);
      else
         rgbi <= reg_bg;
   end
end

endmodule
