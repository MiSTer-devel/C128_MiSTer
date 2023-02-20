// C128 OSD info
//
// for the C128 MiSTer FPGA core, by Erik Scheffers

module osdinfo #(
	// delay ticks are approx. 1/32 seconds
	parameter    ROM_LOAD_DELAY = 255,
	parameter    STARTUP_DELAY = 7
) (
	input        clk,
	input        reset,
	input        kbd_reset,
	input        cpslk_mode,

	input  [1:0] rom_loaded,
	input        sftlk_sense,
	input        cpslk_sense,
	input        d4080_sense,
	input        noscr_sense,

	output       info_req,
	output [7:0] info
);

localparam ROM_LOAD_DELAY_BITS = $clog2(ROM_LOAD_DELAY);
localparam STARTUP_DELAY_BITS = $clog2(STARTUP_DELAY);

reg osd_clk;

always @(posedge clk) begin
	reg [19:0] count;

	if (reset)
		count <= '1;
	else 
		count <= count - 1'd1;
	
	osd_clk <= ~|count;
end

reg [1:0] missing_rom;

always @(posedge clk) begin
   reg [ROM_LOAD_DELAY_BITS-1:0] delay;

   if (reset || &rom_loaded) begin
		missing_rom <= 0;
      delay <= ROM_LOAD_DELAY_BITS'(ROM_LOAD_DELAY);
	end
   else if (|delay) begin
		if (osd_clk)
   	   delay <= delay - 1'd1;
	end
   else
      missing_rom <= rom_loaded[0] ? 2'd2 : 2'd1;
end

always @(posedge clk) begin
	reg kbd_reset_d;
	reg sftlk_sense0;
	reg cpslk_sense0;
	reg d4080_sense0;
	reg noscr_sense0;
	reg [STARTUP_DELAY_BITS-1:0] delay;

	kbd_reset_d <= kbd_reset;
	sftlk_sense0 <= sftlk_sense;
	cpslk_sense0 <= cpslk_sense;
	d4080_sense0 <= d4080_sense;
	noscr_sense0 <= noscr_sense;

	if (reset || !kbd_reset_d && kbd_reset) begin
		info_req <= 0;
		delay <= STARTUP_DELAY_BITS'(STARTUP_DELAY);
	end
	else if (|delay) begin
		if (osd_clk)
			delay <= delay - 1'd1;
	end
	else if (missing_rom) begin
		info <= missing_rom;
		info_req <= ~info_req;  // keep visible
	end		
	else begin
		info_req <= 0;

		if (sftlk_sense != sftlk_sense0) begin
			info <= sftlk_sense ? 8'd4 : 8'd3;
			info_req <= 1;
		end

		if (cpslk_sense != cpslk_sense0) begin
			info <= cpslk_mode ? (cpslk_sense ? 8'd8 : 8'd7) : (cpslk_sense ? 8'd6 : 8'd5);
			info_req <= 1;
		end

		if (d4080_sense != d4080_sense0) begin
			info <= d4080_sense ? 8'd10 : 8'd9;
			info_req <= 1;
		end

		if (noscr_sense != noscr_sense0) begin
			info <= noscr_sense ? 8'd12 : 8'd11;
			info_req <= 1;
		end
	end
end

endmodule
