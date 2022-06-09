// C128 OSD info
//
// for the C128 MiSTer FPGA core, by Erik Scheffers

module osdinfo #(
	parameter    STARTUP_DELAY = 4_000_000,
	parameter    OSD_DELAY = 16_000_000,
	parameter    DELAY_BITS = $clog2(OSD_DELAY)
) (
	input        clk,
	input        reset,

	input        sftlk_sense,
	input        cpslk_sense,
	input        d4080_sense,
	input        noscr_sense,

	input        cpslk_mode,

	output       info_req,
	output [7:0] info
);

always @(posedge clk) begin
	reg sftlk_sense0;
	reg cpslk_sense0;
	reg d4080_sense0;
	reg noscr_sense0;
	reg startup;
	reg [DELAY_BITS-1:0] delay;

	sftlk_sense0 <= sftlk_sense;
	cpslk_sense0 <= cpslk_sense;
	d4080_sense0 <= d4080_sense;
	noscr_sense0 <= noscr_sense;

	if (reset) begin
		info <= 0;
		info_req <= 0;

		// prevent OSD messages from popping up after reset
		startup <= 1;
		delay <= DELAY_BITS'(STARTUP_DELAY);
	end
	else begin
		if (!startup) begin
			if (sftlk_sense != sftlk_sense0) begin
				info <= sftlk_sense ? 8'd2 : 8'd1;
				info_req <= 1;
				delay <= DELAY_BITS'(OSD_DELAY);
			end

			if (cpslk_sense != cpslk_sense0) begin
				info <= cpslk_mode ? (cpslk_sense ? 8'd6 : 8'd5) : (cpslk_sense ? 8'd4 : 8'd3);
				info_req <= 1;
				delay <= DELAY_BITS'(OSD_DELAY);
			end

			if (d4080_sense != d4080_sense0) begin
				info <= d4080_sense ? 8'd8 : 8'd7;
				info_req <= 1;
				delay <= DELAY_BITS'(OSD_DELAY);
			end

			if (noscr_sense != noscr_sense0) begin
				info <= noscr_sense ? 8'd10 : 8'd9;
				info_req <= 1;
				delay <= DELAY_BITS'(OSD_DELAY);
			end
		end

		if (~|delay) begin
			delay <= delay - DELAY_BITS'(1);
		end
		else if (info_req) begin
			info_req <= 0;
		end
		else if (startup) begin
			startup <= 0;
		end
	end
end

endmodule
