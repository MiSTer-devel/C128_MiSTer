/********************************************************************************
 * Commodore 128 VDC
 * 
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 ********************************************************************************/

module vdc_signals_v #(
	parameter VB_WIDTH  // vertical blanking width
)(
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
	input            lineEnd,

	output reg       fetchFrame,     // indicates start of a new frame (only valid at lineStart)
	output reg       fetchRow,       // indicates start of a new visible row (only valid at lineStart)
	output reg       fetchLine,      // indicates start of a new visible line (only valid at lineStart)
	output reg       cursor,         // show cursor vertically

	output reg       field,          // 0=first half, 1=second half
	output reg       lastRow,
	output reg [7:0] row,            // current row
	output reg [4:0] line,           // current row line 

	output reg       vVisible,       // visible line

	output           vsync,          // vertical sync
	output           vblank,         // vertical blanking

	output reg       updateBlink
);

// control signals

reg  [7:0] nrow;
reg  [4:0] ncline, nsline;
reg  [4:0] ctv;
reg        cfield;

wire       ncfield = reg_im[0] & ~cfield;
wire [5:0] va = reg_va+(ncfield ? 6'd1 : 6'd0);
wire [7:0] fh = reg_vt+(|va ? 8'd1 : 8'd0);
wire [4:0] rh = nrow==reg_vt+1 ? 5'(va-6'd1) : ctv;
wire [4:0] el = rh; //nrow==reg_vt+1 ? 5'(va-(~va[0] && &reg_im ? 6'd0 : 6'd1)) : ctv;

always @(posedge clk) begin
	if (reset) begin
		row <= 0;
		nrow <= 0;

		cfield <= 0;
		nsline <= 0;

		ncline <= 0;
		line <= 0;

		ctv <= 0;

		fetchLine <= 0;
		fetchRow <= 0;
		fetchFrame <= 0;
		lastRow <= 0;

		updateBlink <= 0;
	end
  	else if (enable) begin
		updateBlink <= 0;

		if (half1End) begin
			fetchLine <= 0;
			fetchRow <= 0;
			fetchFrame <= 0;
			lastRow <= 0;
		end

		if (lineEnd || (&reg_im && half1End)) begin
			ctv <= reg_ctv;

			if (nrow==fh && nsline==el) begin
				if (lineEnd) begin
					cfield <= ncfield;

					if (&reg_im && ncfield) begin
						nsline <= 5'd1;
						ncline <= reg_vss==reg_ctv ? 5'd0 : reg_vss+5'd1;
						line   <= reg_vss==reg_ctv ? 5'd0 : reg_vss+5'd1;
					end
					else begin
						nsline <= 0;
						ncline <= reg_vss;
						line   <= reg_vss;
					end

					nrow <= 0;
					
					if (nrow==reg_vd && (cfield || ~&reg_im || !reg_text))
						fetchFrame <= 1;
				end
			end
			else begin
				// update row/line
				if (ncline==ctv) begin
					ncline <= 0;
					if (lineEnd)
						line <= 0;

					if (nrow <= reg_vd-(|reg_vss ? 0 : 1))
						fetchRow <= 1;

					if (nrow == reg_vd-(|reg_vss ? 0 : 1))
						lastRow <= 1;
				end
				else begin
					ncline <= ncline+5'd1;
					if (lineEnd)
						line <= ncline+5'd1;
				end

				if (nsline==el) begin
					nrow <= nrow+8'd1;
					nsline <= 0;

					if (nrow<reg_vd)
						fetchLine <= 1;

					if (nrow==reg_vd && (cfield || ~&reg_im || !reg_text))
						fetchFrame <= 1;
				end
				else begin
					nsline <= nsline+5'd1;

					if (|nrow && nrow<=reg_vd)
						fetchLine <= 1;
				end
			end
		end

		if (row != nrow) begin
			if (lineStart) begin
			if (nrow==1 && |ctv)
				vVisible <= 1;

			if (nrow==reg_vd+1)
				vVisible <= 0;

			if (nrow==reg_vp+1)
				updateBlink <= 1;
			end

			if (displayStart)
				row <= nrow;
		end
	end
end

// vsync/vblank

localparam VB_BITS = $clog2(VB_WIDTH+2);

reg [VB_BITS-1:0] vbCount;
assign vblank = |vbCount;

reg [1:0] vsCount;
assign vsync = vsCount==2'd1;

always @(posedge clk) begin
	reg vsDetect; 
	reg vbStart;

	if (reset) begin
		vsCount <= 0;
		vbCount <= 0;
		vsDetect <= 0;
		field <= 0;
	end 
	else if (enable) begin
		if ((half1End || hSyncStart) && (vsDetect || (nrow == reg_vp && nsline == 0))) begin
			vsDetect <= half1End;
			if (hSyncStart) begin
				vbStart <= 1;
				field <= ncfield;
			end
		end

		if (vbStart && lineStart) begin
			vbStart <= 0;
			vbCount <= VB_BITS'(VB_WIDTH) - VB_BITS'(field ? 1 : 0);
			vsCount <= 2'd3;
		end

		if (|vbCount && lineStart) 
			vbCount <= vbCount-1'd1;

		if (|vsCount && hSyncStart) 
			vsCount <= vsCount-1'd1;
	end
end

// cursor

always @(posedge clk) begin
	if (reset)
		cursor <= 0;
	else if (enable && (lineStart || (&reg_im && half2Start))) begin
		if (ncline==reg_cs)
			cursor <= 1;

		if (ncline==reg_ce)  // todo off by one when cs>ce?
			cursor <= 0;
	end
end

endmodule
