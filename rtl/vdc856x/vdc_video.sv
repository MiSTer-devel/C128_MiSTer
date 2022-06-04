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
               
	input    [1:0] newFrame,                   // start of new frame
	input          newLine,                    // start of new line
	input          newRow,                     // start of new visible row
	input          newCol,                     // start of new column
   input          endCol,                     // end of column
               
   input    [1:0] visible,                    // in visible part of display
   input          blink[2],                   // blink rates
	input 			rowbuf,                     // buffer # containing current screen info
   input    [7:0] col,                        // current column
   input    [4:0] line,                       // current line
	input    [7:0] scrnbuf[2][S_LATCH_WIDTH],  // screen codes for current and next row
	input    [7:0] attrbuf[2][A_LATCH_WIDTH],  // latch for attributes for current and next row
	input    [7:0] charbuf[C_LATCH_WIDTH],     // character data for current line
   input   [15:0] dispaddr,                   // address of current row

   output reg [3:0] rgbi
);

reg [7:0] bitmap;

wire [7:0] vcol = col - 8'd8;
wire [7:0] attr = attrbuf[rowbuf][vcol];
wire [3:0]   fg = reg_atr ? attr[3:0] : reg_fg;                               // foreground color
wire [3:0]   bg = visible[1] && reg_text && reg_atr ? attr[7:4] : reg_bg;     // background color
wire [2:0]   ca = ~reg_text && reg_atr ? attr[6:4] : 3'b000;                  // character attributes (bit 0=blink, bit 1=underline, bit 2=reverse)
wire        crs = (dispaddr+vcol == reg_cp);

assign     rgbi = bitmap[7] ? fg : bg;

always @(posedge clk) begin
   if (reset)
      bitmap = 0;
   else if (enable) begin
      if (newCol) begin
         if (visible[1]) begin
            if (ca[0] && blink[reg_cbrate])
               bitmap = 8'h00;
            else if (ca[1] && line == reg_ul)
               bitmap = 8'hff;
            else
               bitmap = charbuf[vcol % C_LATCH_WIDTH];

            if (reg_rvs ^ ca[2] ^ crs) bitmap = ~bitmap;
         end
         else 
            bitmap = 0;
      end
      else
         bitmap = { bitmap[6:0], reg_semi & bitmap[0] };
   end
end

endmodule
