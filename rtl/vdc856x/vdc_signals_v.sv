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

	output reg       field,          // 0=first half, 1=second half
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

wire [7:0] fh = reg_vt+8'(|reg_va);
wire [4:0] rh = nrow==reg_vt+1 ? reg_va-5'd1 : ctv;
wire [4:0] el = nrow==reg_vt+1 ? reg_va-(~reg_va[0] && &reg_im ? 5'd0 : 5'd1) : ctv;
wire       ncfield = reg_im[0] & ~cfield;

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
		updateBlink <= 0;
	end
  	else if (enable) begin
		updateBlink <= 0;

		if (half1End) begin
			fetchLine <= 0;
			fetchRow <= 0;
			fetchFrame <= 0;
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
					
					if (reg_vd==fh) begin
						fetchRow <= 0;
						fetchLine <= 0;
						if (cfield || ~&reg_im || !reg_text)
							fetchFrame <= 1;
					end
				end
			end
			else begin
				// update row/line
				if (ncline==ctv) begin
					ncline <= 0;
					if (lineEnd)
						line <= 0;

					if (nrow<=reg_vd)
						fetchRow <= 1;
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
				
					if (nrow==reg_vd) begin	
						fetchRow <= 0;
						fetchLine <= 0;
						if (cfield || ~&reg_im || !reg_text)
							fetchFrame <= 1;
					end

				end
				else begin
					nsline <= nsline+5'd1;

					if (|nrow && nrow<=reg_vd)
						fetchLine <= 1;
				end
			end
		end

		if (displayStart && row != nrow) begin
			row <= nrow;

			if (nrow==1 && |ctv)
				vVisible <= 1;

			if (nrow==reg_vd+1)
				vVisible <= 0;

			if (nrow==reg_vp)
				updateBlink <= 1;
		end
	end
end

// vsync/vblank

localparam VB_BITS = $clog2(VB_WIDTH+1);

reg [VB_BITS-1:0] vbCount;
assign vblank = |vbCount;

wire [4:0] vsWidth = {~|reg_vw, reg_vw};
reg  [4:0] vsCount;
assign vsync = |vsCount;
wire   swap = ~reg_ctv[0] & reg_vp[0];

always @(posedge clk) begin
	reg       vbDelay; 
	reg [5:0] vbFront;

	if (reset) begin
		vsCount <= 0;
		vbCount <= 0;
		vbFront <= 0;
		vbDelay <= 0;
	end 
	else if (enable) begin
		if (
			(half1End || hSyncStart) && (vbDelay || (
				nrow == (reg_vp>1 ? reg_vp-8'd2 : reg_vt+8'(|reg_va)-8'd1) 
				&& nsline == (|reg_vp || ~|reg_va ? reg_ctv : reg_va-5'd1)
			))
		) begin
			vbDelay <= half1End;
			if (hSyncStart) begin
				vbFront <= reg_ctv > 2 ? (6'(reg_ctv)>>reg_im[0])+6'd1 : 6'd2;
				vbCount <= VB_BITS'(VB_WIDTH);
				field <= ncfield;
			end
		end

		if (|vbCount && hSyncStart) 
			vbCount <= vbCount-1'd1;

		if (|vbFront && hSyncStart) begin
			vbFront <= vbFront-1'd1;
			if (vbFront == 1) 
				vsCount <= vsWidth>>reg_im[0];
		end

		if (|vsCount && hSyncStart) 
			vsCount <= vsCount-1'd1;
	end
end

endmodule
