/********************************************************************************
 * Commodore 128 VDC
 * 
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 ********************************************************************************/

module vdc_signals_v #(
	parameter VB_FRONT_PORCH,  // vertical blanking front porch
	parameter VB_WIDTH         // vertical blanking width
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
	output reg       vblank,         // vertical blanking

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

			// $display("lineEnd=%d, nrow=%d, ncline=%d, nsline=%d, ctv=%d, fh=%d, el=%d, vVisible=%d", lineEnd, nrow, ncline, nsline, ctv, fh, el, vVisible);
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
						if (cfield || ~&reg_im || !reg_text) begin
							fetchFrame <= 1;
							fetchRow <= 0;
							fetchLine <= 0;
						end
						else
							fetchLine <= 1;
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
						if (cfield || ~&reg_im || !reg_text) begin
							fetchFrame <= 1;
							fetchRow <= 0;
							fetchLine <= 0;
						end
						else
							fetchLine <= 1;
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

// calculate vsync/vblank row/line

reg [7:0] vsrow, vbrow[2];
reg [4:0] vsline, vbline[2];

function [12:0] decrl;
	input [7:0] ri;
	input [4:0] li;
	if (|li) 
		return { ri, li-5'd1 };
	else if (|ri)
		return { ri-8'd1, reg_ctv };
	else if (|reg_va)
		return { reg_vt+8'd1, reg_va-5'd1 };
	else
		return { reg_vt, reg_ctv };
endfunction

always @(posedge clk) begin
	reg [7:0] last_vp, last_vt, ri;
	reg [4:0] last_ctv, last_va, li;

	if (reset) begin
		vsrow <= 0;
		vsline <= 0;
		vbrow <= '{0, 0};
		vbline <= '{0, 0};

		last_vp <= '1;
		last_vt <= '1;
		last_va <= '1;
		last_ctv <= '1;
	end
	else if (enable) begin
		last_vp <= reg_vp;
		last_vt <= reg_vt;
		last_va <= reg_va;
		last_ctv <= reg_ctv;

		if (reg_vp != last_vp || reg_vt != last_vt || reg_va != last_va || reg_ctv != last_ctv) begin
			repeat(2) {ri, li} = decrl(|reg_vp ? reg_vp-8'd1 : reg_vt, 5'd0);
			// $display("vsync: %d, %d", ri, li);
			vsrow <= ri; 
			vsline <= li;

			repeat(VB_FRONT_PORCH) {ri, li} = decrl(ri, li);
			// $display("vblank[0]: %d, %d", ri, li);
			vbrow[0] <= ri; 
			vbline[0] <= li;

			{ri, li} = decrl(ri, li);
			// $display("vblank[1]: %d, %d", ri, li);
			vbrow[1] <= ri; 
			vbline[1] <= li;
		end
	end
end

// vsync

wire [4:0] vswidth = {~|reg_vw, reg_vw};   // vsync width
reg  [4:0] vsCount;                        // vertical sync counter

assign vsync = |vsCount;

always @(posedge clk) begin
	reg [2:0] vsstart;

	if (reset) begin
		vsCount <= 0;
		vsstart <= 0;
		field <= 0;
	end 
	else if (enable) begin
		if (nrow==vsrow && nsline==vsline && ((reg_im[0] && half1End) || lineEnd))
			vsstart <= {1'b0, lineEnd, half1End};
		else if (lineEnd)
			vsstart <= {vsstart[1:0], 1'b0};

		if (vsstart[1] && ((lineStart && (!reg_im[0] || !cfield)) || (half2Start && (reg_im[0] && cfield)))) begin
			vsCount <= vswidth;
		end
		else if (|vsCount && (lineStart || (half2Start && reg_im[0]))) 
			vsCount <= vsCount-5'd1;

		if (vsstart[2] && lineStart)
			field <= ncfield;
	end
end

// always @(posedge clk) begin
// 	reg vsstart;

// 	if (reset) begin
// 		vsCount <= 0;
// 		vsstart <= 0;
// 	end 
// 	else if (enable) begin
// 		if (nrow==vsrow && nsline==vsline && (half1End || lineEnd))
// 			vsstart <= 1;

// 		if (vsstart && lineStart) begin
// 			vsCount <= vswidth;
// 			vsstart <= 0;
// 		end
// 		else if (|vsCount && (lineStart || (half2Start && reg_im[0]))) 
// 			vsCount <= vsCount-5'd1;
// 	end
// end

// vblank

localparam VB_BITS = $clog2(VB_WIDTH+1);
localparam VSCNT_BITS = $clog2(256*32);  // maximum number of vertical lines supported

reg [VB_BITS-1:0] vbCount;
assign vblank = |vbCount;

always @(posedge clk) begin
	reg [1:0] vbstart;
	reg       nextfield;

	if (reset) begin
		vbCount <= 0;
		vbstart <= 0;
	end
	else if (enable) begin
		if ((lineStart || half2Start) && nrow==vbrow[ncfield] && nsline==vbline[ncfield])
			vbstart <= 2'b01;

		if (hSyncStart) begin
			vbstart <= {vbstart[0], 1'b0};

			if (vbstart[0])
				vbCount <= VB_BITS'(VB_WIDTH);
			else if (|vbCount)
				vbCount <= vbCount-1'd1;
		end
	end
end

endmodule
