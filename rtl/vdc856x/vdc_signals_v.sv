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
	input      [7:0] reg_ai,	     // R27        00 0       Address increment per row
   
	input            lineStart,
	input            displayStart,
	input            half1End,
	input            hSyncStart,
	input            lineEnd,

	output reg       fetchFrame,     // pulses at the start of a new frame
	output reg       fetchRow,       // pulses at the start of a new visible row
	output reg       fetchLine,      // pulses at the start of a new visible line

	output reg [7:0] row,            // current row
	output reg [4:0] line,           // current row line 

	output reg       vVisible,       // visible line

	output           vsync,          // vertical sync
	output reg       vblank,         // vertical blanking
	output reg       frame,          // 0=first half, 1=second half

	output reg       updateBlink
);

reg  [4:0] cline;
reg        vsstart;

function [4:0] correct_line(
	input ilmode, 
	input cframe, 
	input [4:0] vss,
	input [4:0] line
);
begin
	// correct line number for current frame, vertical scroll state and character height
	return {line[4:1], ilmode ? cframe^vss[0] : line[0]};
end
endfunction

always @(posedge clk) begin
	reg       ilmode;
	reg       cframe;

	reg [4:0] ncline;
	reg [4:0] nsline;
	reg [7:0] nrow;

	if (reset) begin
		row <= 0;
		nrow <= 0;

		line <= reg_vss;
		ncline <= reg_vss;
		ilmode <= &reg_im;
		cframe <= 0;

		nsline <= 0;

		fetchLine <= 0;
		fetchRow <= 0;
		fetchFrame <= 0;
		updateBlink <= 0;
	end
  	else if (enable) begin
		if (lineStart) begin
			vsstart <= 0;
			fetchRow <= 0;
			fetchFrame <= 0;
			updateBlink <= 0;

			if (|reg_va 
				? (nrow==reg_vt+1 && nsline==correct_line(ilmode, cframe, 0, reg_va)) 
				: (nrow==reg_vt && nsline==correct_line(ilmode, cframe, 0, reg_ctv))
			) begin
				ilmode <= &reg_im;
				cframe <= &reg_im & frame;
				
				nsline <= (&reg_im & frame) ? 5'd1 : 5'd0;
				ncline <= (&reg_im & frame) ? (reg_vss==reg_ctv ? 5'd0 : reg_vss+5'd1) : reg_vss;

				nrow <= 0;
				if (reg_vp==0)
					vsstart <= 1;

				if (reg_vd==nrow) begin	
					fetchFrame <= 1;
					fetchLine <= 0;
				end
			end
			else begin
				// update row/line
				if (ncline==correct_line(ilmode, cframe, reg_vss, reg_ctv)) begin
					ncline <= correct_line(ilmode, cframe, reg_vss, 0);
					if (nrow<=reg_vd)
						fetchRow <= 1;
				end
				else 
					ncline <= ncline+(ilmode ? 5'd2 : 5'd1);

				if (nsline==correct_line(ilmode, cframe, 0, reg_ctv)) begin
					nsline <= cframe ? 5'd1 : 5'd0;
				
					nrow <= nrow+8'd1;
					if (nrow==0) 
						fetchLine <= 1;

					if (|reg_vp && (reg_vp-1==nrow+1))
						vsstart <= 1;

					if (reg_vp==nrow)
						updateBlink <= 1;

					if (reg_vd==nrow) begin	
						fetchFrame <= 1;
						fetchLine <= 0;
						fetchRow <= 0;
					end
				end
				else
					nsline <= nsline+(ilmode ? 5'd2 : 5'd1);
			end
		end

		if (displayStart) begin
			row <= nrow;
			cline <= ncline;
		end

		if (lineEnd) begin
			line <= cline;

			if (nsline==correct_line(ilmode, cframe, 0, 0)) begin
				if (nrow==1 && |reg_ctv)
					vVisible <= 1;

				if (nrow==reg_vd+1)
					vVisible <= 0;
			end
		end
	end
end

// vsync

wire [4:0] vswidth = {~|reg_vw, reg_vw};   // vsync width
reg  [4:0] vsCount;                        // vertical sync counter

assign vsync = |vsCount;

always @(posedge clk) begin
	if (reset) begin
		vsCount <= 0;
	end 
	else if (enable) begin
		if (|vsCount && (lineEnd || (reg_im[0] && half1End)))
			vsCount <= vsCount-5'd1;
		else if (vsstart && (frame ? half1End : lineEnd))
			vsCount <= vswidth;
	end
end

// vblank & frame

always @(posedge clk) begin
	reg [$clog2(VB_WIDTH)-1:0] vbCount;
	reg [9:0] vscnt, vbstart[2];
	reg       frame_n;

	if (reset) begin
		vscnt <= '1;
		vbstart <= '{'1, '1};
		frame <= 0;
		vblank <= 0;
		vbCount <= 0;
	end
	else if (enable) begin
		if (lineStart) begin
			if (&vscnt) begin
				vbstart <= '{'1, '1};
			end
			else begin
				vscnt <= vscnt+1'd1;
				vbstart[frame_n] <= vbstart[frame_n]-1'd1;
			end

			if (vsstart) begin
				vbstart[frame_n] <= vscnt;
				vscnt <= 0;
				frame_n <= ~frame_n & reg_im[0];
			end

			if (vbstart[frame_n]==10'(VB_FRONT_PORCH+1))
				vbCount <= $clog2(VB_WIDTH)'(VB_WIDTH);
			else if (|vbCount)
				vbCount <= vbCount-1'd1;
		end

		if (hSyncStart) begin
			vblank <= |vbCount;
			if (vbstart[frame_n]==10'(VB_FRONT_PORCH))
				frame <= frame_n;
		end
	end
end

endmodule
