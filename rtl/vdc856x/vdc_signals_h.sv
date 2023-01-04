/********************************************************************************
 * Commodore 128 VDC
 * 
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 ********************************************************************************/


module vdc_signals_h (
	input            clk,
	input            reset,
	input            enable,
 
	input      [7:0] reg_ht,         // R0      7E/7F 126/127 Horizontal total (minus 1) [126 for original ROM, 127 for PAL on DCR]
	input      [7:0] reg_hd,         // R1         50 80      Horizontal displayed
	input      [7:0] reg_hp,         // R2         66 102     Horizontal sync position 
	input      [3:0] reg_hw,         // R3[3:0]     9 9       Horizontal sync width (plus 1)
	input      [3:0] reg_cth,        // R22[7:4]    7 7       Character total horizontal (minus 1)
	input            reg_atr,        // R25[6]      1 on      Attribute enable
	input            reg_dbl,        // R25[4]      0 off     Pixel double width
	input      [7:0] reg_ai,	     // R27        00 0       Address increment per row
	input      [7:0] reg_deb,        // R34        7D 125     Display enable begin
	input      [7:0] reg_dee,        // R35        64 100     Display enable end

	input            hSyncStart,
   
	output reg       newCol,         // pulses on first pixel of a column
	output reg       endCol,         // pulses on the last pixel of a column

	output reg [7:0] col,            // current column
	output reg [4:0] pixel,          // current column pixel

	output           hVisible,       // visible column
	output reg       hdispen,        // horizontal display enable

	output reg       hsync,          // horizontal sync
	output           hblank          // horizontal blanking
);

reg [3:0] hbCount; 
reg       hviscol; 

assign hblank   = |hbCount;
assign hVisible = hviscol & hdispen;

always @(posedge clk) begin
	if (reset) begin
		col <= 0;
		pixel <= 0;

		hsync <= 0;
		hbCount <= 0;

		newCol <= 0;
		endCol <= 0;

		hviscol <= 0;
		hdispen <= 0;
	end
	else if (enable) begin
		newCol <= endCol;
		endCol <= pixel==(reg_cth-1'd1);

		if (endCol) begin
			pixel <= {4'b0000, reg_dbl};
			if (col==reg_ht)
				col <= 0;
			else
				col <= col+8'd1;

			// visible column start
			if (col==8) hviscol <= 1;

			// hdisplay enable
			if (col==(reg_deb==reg_ht ? 0 : reg_deb+1)) hdispen <= 1;
			if (col==(reg_dee==reg_ht ? 0 : reg_dee+1)) hdispen <= 0;

			// hsync
			hsync <= hSyncStart;

			// hblank
			if (hSyncStart) 
				hbCount <= reg_hw >> reg_dbl;
			else if (hblank) 
				hbCount <= hbCount-1'd1;
		end
		else
			pixel <= pixel+4'd1;

		// visible column end
		if (
			(reg_dbl && newCol && col==reg_hd+9) 
			|| (!reg_dbl && endCol && col==reg_hd+((|reg_ai && !reg_atr) ? 7 : 8))
		)
			hviscol <= 0;
	end
end

endmodule
