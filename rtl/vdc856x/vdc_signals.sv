/********************************************************************************
 * Commodore 128 VDC
 * 
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 ********************************************************************************/

module vdc_signals (
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
	input   [3:0] reg_cth,        // R22[7:4]    7 7       Character total horizontal (minus 1)
	input   [3:0] reg_cdh,        // R22[3:0]    8 8       Character displayed horizontal (plus 1 in double width mode)
	input   [4:0] reg_vss,        // R24[4:0]   00 0       Vertical smooth scroll
	input         reg_dbl,        // R25[4]      0 off     Pixel double width
	input   [3:0] reg_hss,        // R25[3:0]  0/7 0/7     Smooth horizontal scroll [0 for v0, 7 for v1] (decr=left, incr=right)
	input   [3:0] reg_fg,         // R26[7:4]    F white   Foreground RGBI
	input   [3:0] reg_bg,         // R26[3:0]    0 black   Background RGBI
	input   [7:0] reg_deb,        // R34        7D 125     Display enable begin
	input   [7:0] reg_dee,        // R35        64 100     Display enable end

	output        fetchFrame,     // pulses at the start of a new frame
	output        fetchRow,       // pulses at the start of a new visible row
	output        fetchLine,      // pulses at the start of a new visible line
	output        newCol,         // pulses on first pixel of a column
	output        endCol,         // pulses on the last pixel of a column

	output  [7:0] col,            // current column
	output  [4:0] pixel,          // current column pixel (0=leftmost pixel in normal mode; 1=leftmost pixel in double width mode)
	output  [4:0] line,           // current row line 

	output        hVisible,       // visible column
	output        vVisible,       // visible line
	output        blink[2],       // blink state. blink[0]=1/16, blink[1]=1/30

	output        hsync,          // horizontal sync
	output        vsync,          // vertical sync
	output        hblank,         // horizontal blanking
	output        vblank,         // vertical blanking
	output        frame,          // 0=first half, 1=second half
	output        display         // display enable
);

// horizontal timing
wire lastCol = col == reg_ht;

reg  [3:0] hsCount;     // horizontal sync counter
assign hsync = |hsCount;

always @(posedge clk) begin
	if (reset || init) begin
		col <= 0;
		pixel <= 0;

		hsCount <= 0;

		newCol <= 0;
		endCol <= 0;
	end
	else if (enable0) begin
		newCol <= endCol;
		endCol <= pixel == (reg_cth - 1'd1);

		if (endCol) begin
			pixel <= reg_dbl;
			if (lastCol)
				col <= 0;
			else
				col <= col + 8'd1;

			// hVisible
			if (col == 7) hVisible <= 1;
			if (col == reg_hd + 8'd7) hVisible <= 0;

			// hblank
			if (col == reg_deb || reg_deb > reg_ht) hblank <= 0;
			if (col == reg_dee) hblank <= 1;

			// hsync
			if (col == reg_hp-1) hsCount <= reg_hw;
			if (|hsCount) hsCount <= hsCount - 4'd1;
		end
		else
			pixel <= pixel + 4'd1;
	end
end

// vertical timing

wire [4:0] vswidth = 5'(|reg_vw ? reg_vw : 16);   // vsync width
wire [1:0] li = 2'(il_video ? 2 : 1);              // line increment
wire [7:0] last_row =  reg_vd + (reg_vss ? 1'd1 : 1'd0);
wire [4:0] line_wrap = reg_ctv - (il_video ? 5'd1 : 5'd0);
wire       start_line = reg_ctv && frame && il_video;

reg  [4:0] vsCount;     // vertical sync counter
reg  [7:0] row;         // current row
reg  [4:0] sline;       // scanline (modulo reg_ctv+1)
reg        il_scan;     // interlace scanlines (bit 0 0f reg_im set)
reg        il_video;    // interlace video (bit 0 and 1 of reg_im set)

assign     vsync = |vsCount;

always @(posedge clk) begin
	if (reset) begin
		il_scan <= 0;
		il_video <= 0;
	end

	if (reset || init) begin
		row <= 0;
		sline <= 0;
		line <= reg_vss;

		// vbCount <= 0;
		vsCount <= 0;

		fetchLine <= 0;
		fetchRow <= 0;
		fetchFrame <= 0;
		// frame <= 0;
	end
	else if (enable0) begin
		fetchLine <= 0;
		fetchRow <= 0;
		fetchFrame <= 0;

		if (endCol && lastCol) begin
			// last pixel of last column

			if (row <= last_row) begin
				if (!reg_ctv || line >= line_wrap) begin
					line <= reg_ctv ? line - line_wrap : 0;

					if (row != last_row)
						fetchRow <= 1;
				end
				else
					line <= line + li;
			end

			if (!reg_ctv || sline >= (row > reg_vt ? reg_va : line_wrap)) begin
				if ((row == reg_vt && !reg_va) || row > reg_vt) begin
					// end of frame
					row <= 0;
					line <= reg_vss + start_line > reg_ctv ? 0 : reg_vss + start_line;
					sline <= start_line;
				end
				else begin
					// end of row
					row <= row + 1'd1;
					sline <= reg_ctv ? sline - line_wrap : 0;
				end

				if (row < reg_vd) begin
					vVisible <= 1;
					fetchLine <= 1;
				end
				else if (row == reg_vd) begin
					vVisible <= 0;
					fetchFrame <= 1;
				end
			end
			else begin
				fetchLine <= vVisible;
				sline <= sline + li;
			end
		end

		// vsync
		if (endCol && col == reg_ht>>frame) begin
			if (!vsCount && row == reg_vp-8'd1 && sline >= line_wrap) begin
				vsCount <= vswidth;

				il_scan <= reg_im[0];
				il_video <= &reg_im;
			end
			else if (vsCount > li) 
				vsCount <= vsCount - li;
			else
				vsCount <= 0;
		end
	end
end

// vblank & display enable
reg    [1:0] stable;
assign       display = stable[0] & (~il_scan | stable[1]);

always @(posedge clk) begin
	reg [9:0] vscnt, vbstart[2];
	reg [1:0] lastvs;
	reg       frame_n;

	if (reset) begin
		lastvs <= 0;
		vscnt <= '1;
		vbstart <= '{'1, '1};
		vblank <= 1;
		frame <= 0;
		frame_n <= 0;
		stable <= 0;
	end
	else if (enable0 && newCol && col == 0) begin
		lastvs <= {lastvs[0], vsync};

		if (&vscnt) begin
			stable <= 0;
			vbstart <= '{'1, '1};
		end
		else begin
			vscnt <= vscnt + 1'd1;
			vbstart[frame_n] <= vbstart[frame_n] - 1'd1;
		end

		if (vbstart[frame_n] == 2)
			vblank <= 1;

		if (vbstart[frame_n] == 1)
			frame <= ~frame_n;

		if (!lastvs[0] && vsync) begin
			stable[frame_n] <= !vbstart[frame_n];
			vbstart[frame_n] <= vscnt;
			vscnt <= 0;
			vblank <= 1;
			frame_n <= ~frame_n & il_scan;
		end

		if (lastvs[1] && !lastvs[0]) 
			vblank <= 0;
	end
end

// blinking
always @(posedge clk) begin
	reg [2:0] bcnt16;
	reg [3:0] bcnt30;

	if (reset) begin
		blink[0] <= 0;
		blink[1] <= 0;
		bcnt16 <= 0;
		bcnt30 <= 0;
	end 
	else if (enable0 && endCol && lastCol && row == reg_vp && sline >= line_wrap) begin
		{blink[0], bcnt16} <= 4'({blink[0], bcnt16} + 1);

		bcnt30 <= bcnt30 + 1'd1;
		if (bcnt30 == 14) begin
			blink[1] <= ~blink[1];
			bcnt30 <= 4'd0;
		end
	end
end

endmodule
