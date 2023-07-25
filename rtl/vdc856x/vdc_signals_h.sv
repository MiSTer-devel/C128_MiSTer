/********************************************************************************
 * Commodore 128 VDC
 * 
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 ********************************************************************************/


module vdc_signals_h (
	input            clk,
	input            reset,
	input            enable,

	input      [7:0] db_in,          // CPU data bus, used as a crude random value
 
	input      [7:0] reg_ht,         // R0      7E/7F 126/127 Horizontal total (minus 1) [126 for original ROM, 127 for PAL on DCR]
	input      [7:0] reg_hd,         // R1         50 80      Horizontal displayed
	input      [3:0] reg_hw,         // R3[3:0]     9 9       Horizontal sync width (plus 1)
	input      [3:0] reg_cth,        // R22[7:4]    7 7       Character total horizontal (minus 1)
	input            reg_atr,        // R25[6]      1 on      Attribute enable
	input            reg_dbl,        // R25[4]      0 off     Pixel double width
	input      [7:0] reg_ai,	      // R27        00 0       Address increment per row
	input      [7:0] reg_deb,        // R34        7D 125     Display enable begin
	input      [7:0] reg_dee,        // R35        64 100     Display enable end

	input            hSyncStart,
   
	output reg       newCol,         // pulses on first pixel of a column
	output reg       endCol,         // pulses on the last pixel of a column

	output reg [7:0] col,            // current column
	output reg [3:0] pixel,          // current column pixel

	output           hVisible,       // visible column
	output reg       hdispen,        // horizontal display enable

	output           hsync           // horizontal sync
);

reg [3:0] hsCount; 
reg       hviscol; 

assign hsync    = |hsCount;
assign hVisible = hviscol & hdispen;

wire [7:0] deb = (reg_deb>=7 && reg_deb<reg_hd+7) ? reg_deb+8'd2 : reg_deb+8'd1;
wire [7:0] dee = (reg_dee>=7 && reg_dee<reg_hd+7) ? reg_dee+8'd2 : reg_dee+8'd1;

always @(posedge clk) begin
	if (reset) begin
		col <= 0;
		pixel <= {3'b000, reg_dbl};

		hsCount <= 0;

		newCol <= 0;
		endCol <= 1;

		hviscol <= 0;
		hdispen <= 0;
	end
	else if (enable) begin
		newCol <= endCol;
		endCol <= pixel==(reg_cth-1'd1);

		if (endCol) begin
			pixel <= {3'b000, reg_dbl};
			if (col==reg_ht) begin
				col <= 0;
				if (deb>=reg_ht) hdispen <= 1;
			end
			else
				col <= col+8'd1;

			// visible column start
			if (col==8) hviscol <= 1;

			if (deb==dee) begin
				if (col==deb) hdispen <= db_in[0]^db_in[1]^db_in[5]^db_in[7];  // "random"
			end 
			else begin
				if (col==deb) hdispen <= 1;
				if (col==dee) hdispen <= 0;
			end
			
			// hsync
			if (hSyncStart) 
				hsCount <= reg_hw>>reg_dbl;
			else if (|hsCount) 
				hsCount <= hsCount-1'd1;
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
