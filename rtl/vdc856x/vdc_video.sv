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
	input    [1:0] version,                    // 0=8563R7A, 1=8563R9, 2=8568

	input          clk,
	input          reset,
	input          enable,

   input    [3:0] reg_cth,                    // character total horizontal                 
   input    [3:0] reg_cdh,                    // character displayed horizontal                 
   input    [4:0] reg_vss,                    // vertical smooth scroll
   input    [3:0] reg_hss,                    // horizontal smooth scroll
               
   input    [4:0] reg_ul,                     // underline position
   input          reg_cbrate,                 // character blink rate
	input          reg_text,                   // text/bitmap mode
	input          reg_atr,                    // attribute enable
   input          reg_semi,                   // semi-graphics mode 
   input          reg_rvs,                    // reverse video
   input    [3:0] reg_fg,                     // foreground color
   input    [3:0] reg_bg,                     // background color

   input    [1:0] reg_cm,                     // cursor mode
   input    [4:0] reg_cs,                     // cursor line start
   input    [4:0] reg_ce,                     // cursor line end
	input   [15:0] reg_cp,                     // cursor position
                 
	input    [1:0] newFrame,                   // start of new frame
	input          newLine,                    // start of new line
	input          newRow,                     // start of new visible row
	input          newCol,                     // start of new column
   input          endCol,                     // end of column
               
   input    [1:0] visible,                    // in visible part of display
   input          blank,                      // blanking
   input          blink[2],                   // blink rates
	input 			rowbuf,                     // buffer # containing current screen info
   input    [7:0] col,                        // current column
   input    [4:0] line,                       // current line
	input    [7:0] scrnbuf[2][S_LATCH_WIDTH],  // screen codes for current and next row
	input    [7:0] attrbuf[2][A_LATCH_WIDTH],  // latch for attributes for current and next row
	input    [7:0] charbuf[C_LATCH_WIDTH],     // character data for current line
   input   [15:0] dispaddr,                   // address of current row

   output   [3:0] rgbi
);

wire [7:0] vcol = col - 8'd8;

always @(posedge clk) begin
   reg [7:0] bitmap;
   reg [3:0] fg, bg;
   reg [2:0] ca;
   reg       crs, rvs;

   if (reset) begin
      fg = 0;
      bg = 0;
      ca = 0;
      bitmap = 0;
      crs = 0;
   end
   else if (enable) begin
      if (visible[1]) begin
         if (newCol) begin
            // fetch colors and attributes
            fg = reg_atr ? attrbuf[rowbuf][vcol][3:0] : reg_fg;
            bg = reg_text && reg_atr ? attrbuf[rowbuf][vcol][7:4] : reg_bg;
            ca = ~reg_text && reg_atr ? attrbuf[rowbuf][vcol][6:4] : 3'b000;

            // apply cursor
            crs = (
               ~reg_text
               && (dispaddr+vcol == reg_cp)
               && (reg_cm == 2'b00 || reg_cm[1] && blink[reg_cm[0]]) 
               && reg_cs <= line && line <= reg_ce
            );

            // get bitmap
            if (ca[0] && blink[reg_cbrate])
               bitmap = 8'h00;
            else if (ca[1] && line == reg_ul)
               bitmap = 8'hff;
            else
               bitmap = charbuf[vcol % C_LATCH_WIDTH];

            // reversed
            rvs = reg_rvs ^ ca[2] ^ crs;
            if (rvs) bitmap = ~bitmap;
         end
         else if (!(ca[1] && line == reg_ul))
            bitmap = {bitmap[6:0], reg_semi ? bitmap[0] : rvs};

         rgbi = bitmap[7] ? fg : bg;
      end
      else if (blank)
         rgbi = 0;
      else 
         rgbi = reg_bg;
   end
end


endmodule
