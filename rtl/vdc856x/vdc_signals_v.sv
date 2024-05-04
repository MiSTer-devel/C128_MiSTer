/********************************************************************************
 * Commodore 128 VDC
 *
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 ********************************************************************************/

module vdc_signals_v (
	input            clk,
	input            reset,
	input            enable,

	input      [3:0] reg_vw,         // R3[7:4]     4 4       Vertical sync width
	input      [7:0] reg_vt,         // R4      20/27 32/39   Vertical total (minus 1) [32 for NTSC, 39 for PAL]
	input      [4:0] reg_va,         // R5         00 0       Vertical total adjust
	input      [7:0] reg_vd,         // R6         19 25      Vertical displayed
	input      [7:0] reg_vp,         // R7      1D/20 29/32   Vertical sync position (plus 1) [29 for NTSC, 32 for PAL]
	input      [1:0] reg_im,         // R8          0 off     Interlace mode
	input      [4:0] reg_ctv,        // R9         07 7       Character Total Vertical (minus 1)
	input      [4:0] reg_cs,         // R10[4:0]    0 0       Cursor scanline start
	input      [4:0] reg_ce,         // R11        07 7       Cursor scanline end (plus 1?)
	input      [4:0] reg_vss,        // R24[4:0]   00 0       Vertical smooth scroll
	input            reg_text,       // R25[7]      0 text    Mode select (text/bitmap)

	input            lineStart,
	input            displayStart,
	input            half1End,
	input            half2Start,
	input            hSyncStart,
	input      [1:0] vSyncStart,
	input            lineEnd,

	output reg       fetchFrame,     // indicates start of a new frame (only valid at lineStart)
	output reg       fetchRow,       // indicates start of a new visible row (only valid at lineStart)
	output reg       fetchLine,      // indicates start of a new visible line (only valid at lineStart)
	output reg       cursor,         // show cursor vertically

	output reg       lastRow,
	output reg [7:0] row,            // current row
	output reg [4:0] line,           // current row line

	output reg       vVisible,       // visible line

	output           vsync,          // vertical sync

	output reg       updateBlink
);

// control signals

reg  [7:0] crow, srow;
reg  [5:0] ncline, nsline;
reg        cfield, ncfield;
reg        newsrow;

wire [7:0] vd = 8'(reg_vd - (|reg_vss ? 0 : 1));

function [5:0] firstRowHeight;
   input [4:0] ctv;

	if (cfield && (ctv[0]|reg_vt[0]) != reg_va[0])
		return ctv + reg_va - 1;
	else
		return ctv + reg_va;
endfunction

function [5:0] lastRowHeight;
   input [4:0] ctv;

	if (cfield && (ctv[0]|reg_vt[0]) != reg_va[0])
		return ctv - 1;
	else
		return ctv;
endfunction

always @(posedge clk) begin
	reg [4:0] ctv;
	reg       frameFetched;

	if (reset) begin
		row <= 0;
		crow <= 0;
		srow <= 0;

		cfield <= 0;
		ncfield <= 0;
		nsline <= 0;

		ncline <= 0;
		line <= 0;

		ctv <= 0;

		fetchLine <= 0;
		fetchRow <= 0;
		fetchFrame <= 0;
		lastRow <= 0;

		frameFetched <= 0;

		updateBlink <= 0;
	end
  	else if (enable) begin
		updateBlink <= 0;

		if (half1End) begin
			fetchRow <= 0;
			fetchFrame <= 0;
			lastRow <= 0;
			newsrow <= 0;
		end

		if (lineEnd)
			ctv <= reg_ctv;

		if (lineEnd || (&reg_im && half1End)) begin
			if (srow==reg_vt && nsline==lastRowHeight(ctv)) begin
				if (lineEnd || ncfield) begin
					cfield <= ncfield;
					ncfield <= reg_im[0] & ~ncfield;

					nsline <= 0;
					ncline <= reg_vss;
					if (lineEnd)
						line <= reg_vss;

					crow <= 0;
					srow <= 0;
					newsrow <= 1;

					frameFetched <= 0;
					if (~&reg_im || cfield || !reg_text)
						fetchFrame <= ~frameFetched;

					fetchLine <= cfield & reg_text & |ctv;
				end
			end
			else begin
				if (!crow) begin
					if (ncline==firstRowHeight(ctv)) begin
						crow <= 8'd1;
						ncline <= 0;

						if (lineEnd)
							line <= 0;

						fetchRow <= 1;
					end
					else begin
						ncline <= ncline+1'd1;

						if (lineEnd)
							line <= 5'(ncline+1'd1);
					end
				end
				else begin
					if (ncline==ctv) begin
						crow <= crow+1'd1;
						ncline <= 0;

						if (lineEnd)
							line <= 0;

						if (crow<=vd)
							fetchRow <= 1;
						else if (!frameFetched && (~&reg_im || ncfield || !reg_text)) begin
							fetchFrame <= 1;
							frameFetched <= 1;
						end

						if (crow==vd)
							lastRow <= 1;
					end
					else begin
						ncline <= 5'(ncline+1'd1);

						if (lineEnd)
							line <= 5'(ncline+1'd1);
					end
				end

				if (!srow) begin
					if (nsline==firstRowHeight(ctv)) begin
						newsrow <= 1;
						srow <= 8'd1;
						nsline <= 0;
						fetchLine <= |ctv;
					end
					else begin
						nsline <= nsline+1'd1;

						if (nsline==reg_va)
							fetchLine <= 0;
					end
				end
				else begin
					if (nsline==ctv) begin
						newsrow <= 1;
						srow <= srow+1'd1;
						nsline <= 0;

						if (srow==reg_vd)
							fetchLine <= 0;
					end
					else
						nsline <= 5'(nsline+1'd1);
				end
			end
		end

		if (row != crow && displayStart)
			row <= crow;

		if (newsrow && lineStart) begin
			if (srow==1 && |ctv)
				vVisible <= 1;

			if (srow==reg_vd+1 || srow==0)
				vVisible <= 0;

			if (srow==reg_vp+1)
				updateBlink <= 1;
		end
	end
end

// vsync

reg [4:0] vsCount;
assign vsync = |vsCount;

always @(posedge clk) begin
	reg [4:0] ctv;
	reg       vsBegin;

	if (reset) begin
		vsCount <= 0;
	end
	else if (enable) begin
		if (newsrow && lineStart)
			ctv <= reg_ctv;

		if (vSyncStart[0] || (reg_im[0] && vSyncStart[1])) begin
			vsBegin <= 0;

			if (srow == reg_vp-1 && nsline == ctv)
				vsBegin <= 1;

			if (vsBegin)
				vsCount <= {~|reg_vw, reg_vw};
			else if (|vsCount)
				vsCount <= vsCount-1'd1;
		end
	end
end

// cursor

always @(posedge clk) begin
   reg cursorSet, cursorReset;

	if (reset) begin
		cursor <= 0;
		cursorSet = 0;
		cursorReset = 0;
	end

	if (enable && (lineStart || (&reg_im && half2Start))) begin
		if (ncline==reg_cs)
			cursorSet = 1;

		if (ncline==reg_ce)
			cursorReset = 1;
	end

	if (lineStart) begin
		if (cursorSet)   cursor <= 1;
		if (cursorReset) cursor <= 0;

		cursorSet = 0;
		cursorReset = 0;
	end
end

endmodule
