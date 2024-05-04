/********************************************************************************
 * Commodore 128 VDC
 *
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 ********************************************************************************/

module vdc_video #(
	parameter 	 	 S_LATCH_WIDTH,
	parameter 	 	 C_LATCH_WIDTH
)(
	input            debug,

	input            clk,
	input            reset,
	input            enable,

	input      [7:0] reg_hd,                     // horizontal displayed
	input      [3:0] reg_cth,                    // character total horizontal (minus 1)
	input      [3:0] reg_cdh,                    // character displayed horizontal
	input      [4:0] reg_cdv,                    // character displayed vertical
	input      [3:0] reg_hss,                    // horizontal smooth scroll

	input      [4:0] reg_ul,                     // underline position
	input            reg_cbrate,                 // character blink rate
	input            reg_text,                   // text/bitmap mode
	input            reg_atr,                    // attribute enable
	input            reg_semi,                   // semi-graphics mode
	input            reg_dbl,                    // double pixel mode
	input            reg_rvs,                    // reverse video
	input      [3:0] reg_fg,                     // foreground color
	input      [3:0] reg_bg,                     // background color

	input      [1:0] reg_cm,                     // cursor mode
	input     [15:0] reg_cp,                     // cursor position

	input            fetchFrame,                 // start of new frame
	input            fetchLine,                  // start of new visible line
	input            fetchRow,                   // start of new visible row
	input            cursorV,                    // show cursor on current line

	input            hVisible,                   // in visible part of display (horizontal)
	input            vVisible,                   // in visible part of display (vertical)
	input            hdispen,                    // horizontal display enable
	input            blank,                      // blanking
	input      [1:0] blink,                      // blink rates
	input            rowbuf,                     // buffer # containing current screen info
	input      [7:0] col,                        // current column
	input      [3:0] pixel,                      // current pixel
	input      [4:0] line,                       // current line

`ifdef VERILATOR
	input      [7:0] attrbuf,
	input      [7:0] charbuf,
`else
	input      [7:0] attrbuf[2][S_LATCH_WIDTH],  // latch for attributes for current and next row
	input      [7:0] charbuf[C_LATCH_WIDTH],     // character data for current line
`endif
	input     [15:0] dispaddr,                   // address of current row

	output reg [3:0] rgbi
);

reg  [7:0] attr;
wire [3:0] fg = reg_atr ? attr[3:0] : reg_fg;
wire [3:0] bg = reg_text && reg_atr ? attr[7:4] : reg_bg;
wire [2:0] ca = !reg_text && reg_atr ? attr[6:4] : 3'b000;

reg  cursorH;
wire cursor = cursorV && cursorH;

wire [7:0] vcol = col - 8'd8;

// note: in double pixel mode, `pixel` starts at 1 instead of 0
reg [4:0] bl;
reg [4:0] ps;
reg [3:0] pe;

always @(*) begin
	if (reg_dbl) begin
		bl = reg_hss + 5'd1;

		if (reg_cdh != reg_cth || (reg_cth > 8 || reg_hss==0)) begin
			ps = reg_hss + 5'd1;
			pe = |reg_cdh ? reg_cdh : reg_cth;
		end
		else begin
			ps = 5'(reg_hss);
			pe = reg_cth - 4'd1;
		end
	end else
	begin
		bl = 5'(reg_hss);
		ps = 5'(reg_hss);

		// todo: (some of) reg_hss below might be reg_ctv
		if (reg_cdh == 0)
			pe = reg_cth;
		else if (reg_cdh == reg_cth+1)
			pe = reg_cth + 4'd1;
		else
			pe = reg_cdh - 4'd1;
	end
end

`ifdef VDC_XRAY
wire showFetch = debug && col == 4;
`endif

always @(posedge clk) begin
	reg [7:0] bitmap;
	reg       enbitm;

	if (reset) begin
		bitmap <= 0;
		enbitm <= 0;
	end
	else if (enable) begin
		if (pixel == pe)
			enbitm <= 0;

		if (line > reg_cdv)
			bitmap <= 8'h00;
		else if (5'(pixel) == ps) begin
`ifdef VERILATOR
			attr    <= attrbuf;
			bitmap  <= charbuf;
`else
			attr    <= (vcol < reg_hd && vcol < S_LATCH_WIDTH) ? attrbuf[rowbuf][vcol] : 8'h00;
			bitmap  <= charbuf[vcol % C_LATCH_WIDTH];
`endif
			cursorH <= !reg_text && reg_cp == dispaddr+16'(vcol) && (~|reg_cm || reg_cm[1] && blink[reg_cm[0]]);

			if (reg_cdh == reg_hss && !reg_semi)
				bitmap <= 0;

			enbitm <= (pixel != pe);
		end
		else if (enbitm)
			bitmap <= {bitmap[6:0], 1'b0};
		else if (!reg_semi && (reg_cdh != reg_cth))
			bitmap <= 0;

		if (vVisible && hVisible)
			rgbi <= (
				(bl <= 5'(reg_cth))
					? (((~(ca[0] & blink[reg_cbrate]) & ((ca[1] && line == reg_ul) | bitmap[7])) ^ reg_rvs ^ ca[2] ^ cursor) ? fg : bg)
					: 4'd0
			);
`ifdef VDC_XRAY
		else if (showFetch && fetchFrame)
			rgbi <= 4'b1111;
		else if (showFetch && pixel == 0 && line[1])
			rgbi <= 4'b1111;
		else if (showFetch && pixel == 1 && line[0])
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
