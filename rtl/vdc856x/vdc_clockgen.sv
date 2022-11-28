/********************************************************************************
 * Commodore 128 VDC
 * 
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 *
 * - timing not verified
 ********************************************************************************/

module vdc_clockgen (
	input         clk,
	input         reset,
	input         init,
	input         enable0,
 
	input   [7:0] reg_ht,         // R0      7E/7F 126/127 Horizontal total (minus 1) [126 for original ROM, 127 for PAL on DCR]
	input   [7:0] reg_hd,         // R1         50 80      Horizontal displayed
	input   [7:0] reg_hp,         // R2         66 102     Horizontal sync position 
	input   [3:0] reg_vw,         // R3[7:4]     4 4       Vertical sync width
	input   [3:0] reg_hw,         // R3[3:0]     9 9       Horizontal sync width (plus 1)
	input   [7:0] reg_vt,         // R4      20/27 32/39   Vertical total (minus 1) [32 for NTSC, 39 for PAL]
	input   [4:0] reg_va,         // R5         00 0       Vertical total adjust
	input   [7:0] reg_vd,         // R6         19 25      Vertical displayed
	input   [7:0] reg_vp,         // R7      1D/20 29/32   Vertical sync position (plus 1) [29 for NTSC, 32 for PAL]
	input   [1:0] reg_im,         // R8          0 off     Interlace mode **TODO**
	input   [4:0] reg_ctv,        // R9         07 7       Character Total Vertical (minus 1)
	input  [15:0] reg_cp,         // R14/R15  0000 0000    Cursor position
	input   [3:0] reg_cth,        // R22[7:4]    7 7       Character total horizontal (minus 1)
	input   [3:0] reg_cdh,        // R22[3:0]    8 8       Character displayed horizontal (plus 1 in double width mode)
	input   [4:0] reg_cdv,        // R23        08 8       Character displayed vertical (minus 1)
	input   [4:0] reg_vss,        // R24[4:0]   00 0       Vertical smooth scroll
	input   [3:0] reg_hss,        // R25[3:0]  0/7 0/7     Smooth horizontal scroll [0 for v0, 7 for v1]
	input   [3:0] reg_fg,         // R26[7:4]    F white   Foreground RGBI
	input   [3:0] reg_bg,         // R26[3:0]    0 black   Background RGBI
	input   [7:0] reg_deb,        // R34        7D 125     Display enable begin
	input   [7:0] reg_dee,        // R35        64 100     Display enable end

	output  [1:0] newFrame,       // pulses at the start of a new frame, 11=single frame, 01=odd frame, 10=even frame
	output        newRow,         // pulses at the start of a new visible row
	output        newLine,        // pulses at the start of a new scan line
	output        newCol,         // pulses on first pixel of a column
	output        endCol,         // pulses on the last pixel of a column

	output  [7:0] col,            // current column
	output  [7:0] row,            // current row
	output  [4:0] line,           // current row line 

	output        hVisible,       // visible column
	output        vVisible,       // visible line
	output        blink[2],       // blink state. blink[0]=1/16, blink[1]=1/30

	output        hsync,          // horizontal sync
	output        vsync,          // vertical sync
	output        hblank,         // horizontal blanking
	output        vblank          // vertical blanking
);

wire [12:0] vtotal  = 13'(((reg_ctv + 13'd1) * reg_vt) + reg_va);                         // total scanlines
wire [12:0] vsstart = 13'((reg_ctv + 13'd1) * reg_vp);                                    // vsync start scanline
wire [10:0] vbfront = 11'(vtotal < 264 ? 0 : ((vtotal-13'd264)*17'd9)/17'd48);            // # of scanlines vblank comes before vsync

wire  [4:0] vswidth = 5'(|reg_vw ? reg_vw : 16);                                          // # of vsync scanlines 
wire [12:0] vbstart = 13'((vbfront > vsstart ? vsstart + vtotal : vsstart) - vbfront);    // vblank start scanline
wire  [5:0] vbwidth = 6'(vswidth + (vtotal < 246 ? 0 : ((vtotal-13'd246)*17'd7)/17'd12)); // # of vblank scanlines

reg   [7:0] hCnt, vCnt;
assign hVisible = |hCnt;
assign vVisible = |vCnt;

reg  [3:0] hsCount;     // horizontal sync counter
reg  [4:0] vsCount;     // vertical sync counter
reg  [7:0] hbCount;     // horizontal blank counter
reg  [5:0] vbCount;     // vertical blank counter

reg  hdisen; // horizontal display enable

assign hsync = |hsCount;
assign vsync = |vsCount;
assign vblank = |vbCount;
assign hblank = ~hdisen | hsync;

// Dot, Pixel and Scanline counters
always @(posedge clk) begin
	reg  [4:0] pCnt, lCnt;  // pixel and line counters
	reg  [7:0] nrow;        // next row
	reg [12:0] scanline;    // *next* scanline

	if (reset || init) begin
		row <= reg_vp > 0 ? reg_vp-8'd1 : reg_vt-8'd1;
		nrow <= reg_vp;
		line <= 0;
		newFrame <= 0;
		newRow <= 1;
		newLine <= 1;
		newCol <= 0;
		endCol <= 0;
		col <= 0;
		hCnt <= 0;
		vCnt <= 0;
		pCnt <= reg_ctv;
		lCnt <= reg_cth;
		hsCount <= 0;
		vsCount <= 0;
		vbCount <= 0;
		scanline <= 0;
		hdisen <= 0;
	end
	else if (enable0) begin
		newFrame <= 0;
		newRow <= 0;
		newLine <= 0;
		newCol <= 0;
		endCol <= 0;

		if (reg_ctv == 0 || pCnt == 1) begin
			// last pixel of column
			endCol <= 1;
		end

		if (pCnt == 0) begin
			// new column
			col <= col + 8'd1;

			pCnt <= reg_ctv;
			newCol <= 1;

			if (col == reg_deb || reg_deb > reg_ht) hdisen <= 1;
			if (col == reg_dee) hdisen <= 0;
			if (col == 7) row <= nrow;
			if (col == reg_ht) begin
				// new line
				newLine <= 1;
				col <= 0;
				hCnt <= 0;

				if (lCnt == 0) begin
					// new row
					lCnt <= reg_cth;
					line <= 0;
					nrow <= nrow + 8'd1;
					newRow <= 1;

					if (nrow == 0)
						vCnt <= reg_vd;
					else if (|vCnt)
						vCnt <= vCnt - 8'd1;
				end
				else begin
					lCnt <= lCnt - 5'd1;
					line <= line + 5'd1;
				end

				scanline <= scanline + 13'd1;

				// new frame
				if (scanline == vtotal) begin
					newFrame <= 2'b11;
					newRow <= 8'd1;
					line <= 0;

					nrow <= 0;
					vCnt <= 0;
					scanline <= 1;
					lCnt <= reg_cth;
				end

				// vertical sync start
				if (scanline == vsstart) vsCount <= vswidth;
				else if (|vsCount) vsCount <= vsCount - 5'd1;

				// vblank
				if (scanline == vbstart || (vbstart == 0 && scanline == vtotal)) vbCount <= vbwidth;
				else if (|vbCount) vbCount <= vbCount - 5'd1;
			end

			if (|vCnt) begin
				if (col == 7) hCnt <= reg_hd;
				else if (|hCnt) hCnt <= hCnt - 8'd1;
			end

			// horizontal sync
			if (col == reg_hp-1) hsCount <= reg_hw;
			if (|hsCount) hsCount <= hsCount - 4'd1;

		end
		else
			pCnt <= pCnt - 5'd1;
	end
end

// 16 frames blink rate
always @(posedge clk) begin
	reg [2:0] counter;

	if (reset||init)
		{blink[0], counter} <= 0;
	else if (enable0 && |newFrame)
		{blink[0], counter} <= 4'({blink[0], counter} + 1);
end

// 30 frames blink rate
always @(posedge clk) begin
	reg [3:0] counter;

	if (reset||init)
		{blink[1], counter} <= 0;
	else if (enable0 && |newFrame) begin
		counter = counter + 1'd1;
		if (counter == 14) begin
			blink[1] <= ~blink[1];
			counter <= 4'd0;
		end
	end
end

endmodule
