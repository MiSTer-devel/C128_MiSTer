/********************************************************************************
 * Commodore 128 VDC
 *
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 ********************************************************************************/

module vdc_signals (
	input            clk,
	input            reset,
	input            enable,

	input      [7:0] db_in,

	input      [7:0] reg_ht,         // R0      7E/7F 126/127 Horizontal total (minus 1) [126 for original ROM, 127 for PAL on DCR]
	input      [7:0] reg_hd,         // R1         50 80      Horizontal displayed
	input      [7:0] reg_hp,         // R2         66 102     Horizontal sync position
	input      [3:0] reg_vw,         // R3[7:4]     4 4       Vertical sync width
	input      [3:0] reg_hw,         // R3[3:0]     9 9       Horizontal sync width (plus 1)
	input      [7:0] reg_vt,         // R4      20/27 32/39   Vertical total (minus 1) [32 for NTSC, 39 for PAL]
	input      [4:0] reg_va,         // R5         00 0       Vertical total adjust
	input      [7:0] reg_vd,         // R6         19 25      Vertical displayed
	input      [7:0] reg_vp,         // R7      1D/20 29/32   Vertical sync position (plus 1) [29 for NTSC, 32 for PAL]
	input      [1:0] reg_im,         // R8          0 off     Interlace mode
	input      [4:0] reg_ctv,        // R9         07 7       Character Total Vertical (minus 1)
	input      [4:0] reg_cs,         // R10[4:0]    0 0       Cursor scanline start
	input      [4:0] reg_ce,         // R11        07 7       Cursor scanline end (plus 1?)
	input      [3:0] reg_cth,        // R22[7:4]    7 7       Character total horizontal (minus 1)
	input      [4:0] reg_vss,        // R24[4:0]   00 0       Vertical smooth scroll
	input            reg_text,       // R25[7]      0 text    Mode select (text/bitmap)
	input            reg_atr,        // R25[6]      1 on      Attribute enable
	input            reg_dbl,        // R25[4]      0 off     Pixel double width
	input      [7:0] reg_ai,	      // R27        00 0       Address increment per row
	input      [7:0] reg_deb,        // R34        7D 125     Display enable begin
	input      [7:0] reg_dee,        // R35        64 100     Display enable end

	output reg       fetchFrame,     // pulses at the start of a new frame
	output reg       fetchRow,       // pulses at the start of a new visible row
	output reg       fetchLine,      // pulses at the start of a new visible line
	output reg       cursorV,

	output           lastRow,
	output reg       newCol,         // pulses on first pixel of a column
	output reg       endCol,         // pulses on the last pixel of a column

	output reg [7:0] col,            // current column
	output reg [7:0] row,            // current row
	output reg [3:0] pixel,          // current column pixel
	output reg [4:0] line,           // current row line

	output reg       hVisible,       // visible column
	output reg       vVisible,       // visible line
	output reg       hdispen,        // horizontal display enable
	output reg [1:0] blink,          // blink state. blink[0]=1/16, blink[1]=1/30

	output reg       hsync,          // horizontal sync
	output reg       vsync           // vertical sync
);

vdc_signals_h signals_h (
	.clk(clk),
	.reset(reset),
	.enable(enable),
	.db_in(db_in),

	.reg_ht(reg_ht),
	.reg_hd(reg_hd),
	.reg_hw(reg_hw),
	.reg_cth(reg_cth),
	.reg_atr(reg_atr),
	.reg_dbl(reg_dbl),
	.reg_ai(reg_ai),
	.reg_deb(reg_deb),
	.reg_dee(reg_dee),

	.hSyncStart(hSyncStart),

	.newCol(newCol),
	.endCol(endCol),

	.col(col),
	.pixel(pixel),

	.hVisible(hVisible),
	.hdispen(hdispen),

	.hsync(hsync)
);

wire [7:0] hp = (reg_hp ? reg_hp-8'd1 : reg_ht);

wire lineStart    = newCol && col==0;
wire displayStart = endCol && col==7;
wire half1End     = endCol && col==(reg_ht/2)-1;
wire half2Start   = newCol && col==reg_ht/2;
wire hSyncStart   = endCol && col==hp;
wire vSyncStartF1 = endCol && col==(hp + (reg_ht>>1) - 1) % reg_ht;
wire lineEnd      = endCol && col==reg_ht;

reg  updateBlink;

vdc_signals_v signals_v (
	.clk(clk),
	.reset(reset),
	.enable(enable),

	.reg_vw(reg_vw),
	.reg_vt(reg_vt),
	.reg_va(reg_va),
	.reg_vd(reg_vd),
	.reg_vp(reg_vp),
	.reg_im(reg_im),
	.reg_ctv(reg_ctv),
	.reg_cs(reg_cs),
	.reg_ce(reg_ce),
	.reg_vss(reg_vss),
	.reg_text(reg_text),

	.lineStart(lineStart),
	.displayStart(displayStart),
	.half1End(half1End),
	.half2Start(half2Start),
	.hSyncStart(hSyncStart),
	.vSyncStart({vSyncStartF1, hSyncStart}),
	.lineEnd(lineEnd),

	.fetchFrame(fetchFrame),
	.fetchLine(fetchLine),
	.fetchRow(fetchRow),
	.cursor(cursorV),
	.lastRow(lastRow),

	.row(row),
	.line(line),

	.vVisible(vVisible),

	.vsync(vsync),

	.updateBlink(updateBlink)
);

// blinking

always @(posedge clk) begin
	reg [2:0] bcnt16;
	reg [3:0] bcnt30;

	if (reset) begin
		blink <= '0;
		bcnt16 <= 0;
		bcnt30 <= 0;
	end
	else if (enable && updateBlink) begin
		{blink[0], bcnt16} <= {blink[0], bcnt16}+4'd1;

		bcnt30 <= bcnt30+1'd1;
		if (bcnt30==14) begin
			blink[1] <= ~blink[1];
			bcnt30 <= 4'd0;
		end
	end
end

endmodule
