`timescale 1 ps / 1 ps

module vdcram
#(
parameter DATA_WIDTH    = 8,
parameter ADDRESS_WIDTH = 16
)
(
input                           clk,
input                           rd,
input                           we,
input      [ADDRESS_WIDTH-1:0]  addr,
input      [DATA_WIDTH-1:0]     dai,
output     [DATA_WIDTH-1:0]     dao
);

altsyncram	altsyncram_component (
		.address_a (addr),
		.clock0 (clk),
		.data_a (dai),
		.rden_a (rd),
		.wren_a (we),
		.q_a (dao),
		.aclr0 (1'b0),
		.aclr1 (1'b0),
		.address_b (1'b1),
		.addressstall_a (1'b0),
		.addressstall_b (1'b0),
		.byteena_a (1'b1),
		.byteena_b (1'b1),
		.clock1 (1'b1),
		.clocken0 (1'b1),
		.clocken1 (1'b1),
		.clocken2 (1'b1),
		.clocken3 (1'b1),
		.data_b (1'b1),
		.eccstatus (),
		.q_b (),
		.rden_b (1'b1),
		.wren_b (1'b0));

defparam
altsyncram_component.byte_size = 8,
altsyncram_component.clock_enable_input_a = "BYPASS",
altsyncram_component.clock_enable_output_a = "BYPASS",
altsyncram_component.intended_device_family = "Cyclone V",
altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO,INSTANCE_NAME=VDC",
altsyncram_component.lpm_type = "altsyncram",
altsyncram_component.numwords_a = 2**ADDRESS_WIDTH,
altsyncram_component.operation_mode = "SINGLE_PORT",
altsyncram_component.outdata_aclr_a = "NONE",
altsyncram_component.outdata_reg_a = "UNREGISTERED",
altsyncram_component.power_up_uninitialized = "FALSE",
altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
altsyncram_component.widthad_a = ADDRESS_WIDTH,
altsyncram_component.width_a = DATA_WIDTH;

endmodule
