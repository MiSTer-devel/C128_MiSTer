module iec_io
(
	input  clk,
	input  ext_en,

	input  cpu_o,
	input  drive_o,
	input  ext_o,

	output cpu_i,
	output drive_i,
	output ext_i
);

always @(posedge clk) begin
	cpu_i <= drive_o & (ext_o | ~ext_en);
	drive_i <= cpu_o & (ext_o | ~ext_en);
	ext_i <= (cpu_o & drive_o) | ~ext_en;
end

endmodule
