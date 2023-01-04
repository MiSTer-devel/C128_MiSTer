/********************************************************************************
 * Commodore 128 VDC
 *
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 ********************************************************************************/

module vdc_video #(
	parameter 		S_LATCH_WIDTH,
	parameter 		C_LATCH_WIDTH
)(
	input    [1:0] version,                    // 0=8563R7A, 1=8563R9, 2=8568
	input          debug,

	input          clk,
	input          enable,

	input    [7:0] reg_hd,                     // horizontal displayed
	input    [3:0] reg_cth,                    // character total horizontal (minus 1)
	input    [3:0] reg_cdh,                    // character displayed horizontal
	input    [4:0] reg_cdv,                    // character displayed vertical
	input    [3:0] reg_hss,                    // horizontal smooth scroll

	input    [4:0] reg_ul,                     // underline position
	input          reg_cbrate,                 // character blink rate
	input          reg_text,                   // text/bitmap mode
	input          reg_atr,                    // attribute enable
	input          reg_semi,                   // semi-graphics mode
	input          reg_dbl,                    // double pixel mode
	input          reg_rvs,                    // reverse video
	input    [3:0] reg_fg,                     // foreground color
	input    [3:0] reg_bg,                     // background color

	input    [1:0] reg_cm,                     // cursor mode
	input    [4:0] reg_cs,                     // cursor line start
	input    [4:0] reg_ce,                     // cursor line end
	input   [15:0] reg_cp,                     // cursor position

	input          fetchFrame,                 // start of new frame
	input          fetchLine,                  // start of new visible line
	input          fetchRow,                   // start of new visible row

	input          hVisible,                   // in visible part of display
	input          vVisible,                   // in visible part of display
	input          hdispen,                    // horizontal display enable
	input          blank,                      // blanking
	input    [1:0] blink,                      // blink rates
	input          rowbuf,                     // buffer # containing current screen info
	input    [7:0] col,                        // current column
	input    [4:0] pixel,                      // current pixel
	input    [4:0] line,                       // current line

	input    [7:0] scrnbuf[2][S_LATCH_WIDTH],  // screen codes for current and next row
	input    [7:0] attrbuf[2][S_LATCH_WIDTH],  // latch for attributes for current and next row
	input    [7:0] charbuf[C_LATCH_WIDTH],     // character data for current line
	input   [15:0] dispaddr,                   // address of current row

	output   [3:0] rgbi
);

reg  [7:0] attr;
wire [3:0] fg = reg_atr ? attr[3:0] : reg_fg;
wire [3:0] bg = reg_text && reg_atr ? attr[7:4] : reg_bg;
wire [2:0] ca = !reg_text && reg_atr ? attr[6:4] : 3'b000;
wire [7:0] vcol = col - 8'd8;
wire [4:0] hss = reg_hss + (reg_dbl ? 5'd1 : 5'd0);
reg        crscol, crsline;

always @(posedge clk) begin
	reg [7:0] bitmap;
`ifdef VDC_XRAY
	reg [1:0] showFetch; 
	reg [7:0] lcol;

	lcol <= col;

	if (showFetch)
		showFetch <= showFetch - 2'd1;
	else if (debug && !col && lcol)
		showFetch <= 2'd3;
`endif 

	if (enable) begin
		if (line==reg_cs)
			crsline <= 1;
		else if (line==reg_ce)
			crsline <= 0;

		if (line > reg_cdv)
			bitmap <= 8'h00;
		else if (pixel == hss) begin
			attr   <= (vcol < reg_hd && vcol < S_LATCH_WIDTH) ? attrbuf[rowbuf][vcol] : 8'h00;
			crscol <= !reg_text && dispaddr+vcol == reg_cp && (!reg_cm || reg_cm[1] && blink[reg_cm[0]]);
			bitmap <= charbuf[vcol % C_LATCH_WIDTH];
		end
		else if (pixel == reg_cdh)
			bitmap <= reg_semi && bitmap[7] ? 8'hff : 8'h00;
		else
			bitmap <= {bitmap[6:0], 1'b0};

		if (vVisible && hVisible)
			rgbi <= (
				hss <= reg_cth 
					? (((~(ca[0] & blink[reg_cbrate]) & ((ca[1] && line == reg_ul) | bitmap[7])) ^ reg_rvs ^ ca[2] ^ (crscol&crsline)) ? fg : bg) 
					: 0
			);
`ifdef VDC_XRAY
		else if (showFetch && ~&showFetch)
			rgbi <= rgbi;
		else if (showFetch && fetchFrame)
			rgbi <= 4'b1111;
		else if (showFetch && fetchRow)
			rgbi <= 4'b0011;
		else if (showFetch && fetchLine)
			rgbi <= 4'b0010;
		else if (debug && bitmap[7])
			rgbi <= 0;
`endif 
		else if (blank || !(debug || hdispen))
			rgbi <= 0;
		else
			rgbi <= reg_bg ^ (debug ? {~hVisible, ~vVisible, ~hdispen, 1'b0} : 4'h0);
	end
end

endmodule
