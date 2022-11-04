//-------------------------------------------------------------------------------
//
// C1541/157x 64H156 drive signal processor
//
// Based on C1541 direct gcr module (C) 2021 Alexey Melnikov
//
// Changes for 157x by Erik Scheffers
//
//-------------------------------------------------------------------------------

module c157x_h156
(
	input        clk,
	input        reset,
	input        enable,
	input        mhz1_2,
	
	output		 hinit,
	input        hclk,
	input        hf,
	output       ht,
	input        mode,

	input  [7:0] din,
	output [7:0] dout,
	input        ted,
	input        soe,
	output       sync_n,
	output       byte_n
);

assign     sync_n     = ~enable | ~mode | ~&shcur;
assign     ht         = enable & ~mode & buff_di[~bit_cnt];
wire       byte_n_ena = enable & soe;

reg  [2:0] bit_cnt;
reg  [7:0] buff_di;

reg  [9:0] shreg;
wire [9:0] shcur = {shreg[8:0], hf};
reg  [1:0] bt_n;

always @(posedge clk) begin
	// detect track formatting and align first sector on buffer start.
	reg [9:0] fmtcnt;

	hinit <= 0;
	if (reset || !enable || mode) begin
		fmtcnt <= 0;
	end 
	else if (hclk && &bit_cnt) begin
		if (buff_di == 8'h55) begin
			if (~&fmtcnt) fmtcnt <= fmtcnt + 1'd1;
		end
		else begin
			if (&fmtcnt) hinit <= 1;
			fmtcnt <= 0;
		end
	end
end

always @(posedge clk) begin
	if (!bt_n[1] & byte_n_ena) 
		byte_n <= 0;
	else if (ted | ~byte_n_ena)
		byte_n <= 1;

	if(reset || !enable) begin
		bit_cnt <= 0;
		shreg   <= 0;
		byte_n  <= 1;
	end
	else begin
		bt_n <= {bt_n[0], |bit_cnt | mhz1_2};

		if (hclk) begin
			bit_cnt <= bit_cnt + 1'b1;
			shreg   <= shcur;

			if (!sync_n) bit_cnt <= 0;

			if (&bit_cnt) begin
				buff_di <= din;
				dout    <= shcur[7:0];
				if (mhz1_2) bt_n[0] <= 0;
			end
		end
	end
end

endmodule
