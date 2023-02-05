
module iecdrv_sync #(parameter WIDTH = 1) 
(
	input                  clk,
	input      [WIDTH-1:0] in,
	output reg [WIDTH-1:0] out
);

reg [WIDTH-1:0] s1,s2;
always @(posedge clk) begin
	s1 <= in;
	s2 <= s1;
	if(s1 == s2) out <= s2;
end

endmodule

module iecdrv_reset_filter #(parameter WIDTH = 1) 
(
	input              clk,
	input  [WIDTH-1:0] reset,
	input  [WIDTH-1:0] in,
	output             out
);

reg [WIDTH-1:0] active;

assign out = &{in | reset | ~active};

generate
	genvar i;
	for(i=0; i<WIDTH; i=i+1) begin :reset_filter_active
		always @(posedge clk)
			if(reset[i] || !active[i])
				active[i] <= in[i];
	end
endgenerate

endmodule

// -------------------------------------------------------------------------------

module iecdrv_mem #(parameter DATAWIDTH, ADDRWIDTH, INITFILE=" ")
(
	input	                     clock_a,
	input	     [ADDRWIDTH-1:0] address_a,
	input	     [DATAWIDTH-1:0] data_a,
	input	                     wren_a,
	output reg [DATAWIDTH-1:0] q_a,

	input	                     clock_b,
	input	     [ADDRWIDTH-1:0] address_b,
	input	     [DATAWIDTH-1:0] data_b,
	input	                     wren_b,
	output reg [DATAWIDTH-1:0] q_b
);

(* ram_init_file = INITFILE *) reg [DATAWIDTH-1:0] ram[1<<ADDRWIDTH];

reg                 wren_a_d;
reg [ADDRWIDTH-1:0] address_a_d;
always @(posedge clock_a) begin
	wren_a_d    <= wren_a;
	address_a_d <= address_a;
end

always @(posedge clock_a) begin
	if(wren_a_d) begin
		ram[address_a_d] <= data_a;
		q_a <= data_a;
	end else begin
		q_a <= ram[address_a_d];
	end
end

reg                 wren_b_d;
reg [ADDRWIDTH-1:0] address_b_d;
always @(posedge clock_b) begin
	wren_b_d    <= wren_b;
	address_b_d <= address_b;
end

always @(posedge clock_b) begin
	if(wren_b_d) begin
		ram[address_b_d] <= data_b;
		q_b <= data_b;
	end else begin
		q_b <= ram[address_b_d];
	end
end

endmodule

module iecdrv_trackmem #(parameter ADDRWIDTH, parameter WORDS, parameter DATAWIDTH=8)
(
	input	                     clock_a,
	input	     [ADDRWIDTH-1:0] address_a,
	input	     [DATAWIDTH-1:0] data_a,
	input	                     wren_a,
	output reg [DATAWIDTH-1:0] q_a,

	input	                     clock_b,
	input	     [ADDRWIDTH-1:0] address_b,
	input	     [DATAWIDTH-1:0] data_b,
	input	                     wren_b,
	output reg [DATAWIDTH-1:0] q_b
);

altsyncram altsyncram_component (
	.clock0 (clock_a),
	.address_a (address_a),
	.addressstall_a (1'b0),
	.byteena_a (1'b1),
	.data_a (data_a),
	.rden_a (1'b1),
	.wren_a (wren_a),
	.q_a (q_a),

	.clock1 (clock_b),
	.address_b (address_b),
	.addressstall_b (1'b0),
	.byteena_b (1'b1),
	.data_b (data_b),
	.rden_b (1'b1),
	.wren_b (wren_b),
	.q_b (q_b)
);

defparam
	altsyncram_component.byte_size = DATAWIDTH,
	altsyncram_component.intended_device_family = "Cyclone V",
	altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
	altsyncram_component.lpm_type = "altsyncram",

	altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
	altsyncram_component.power_up_uninitialized = "FALSE",

	altsyncram_component.clock_enable_input_a = "BYPASS",
	altsyncram_component.clock_enable_output_a = "BYPASS",
	altsyncram_component.outdata_reg_a = "CLOCK0",
	altsyncram_component.outdata_aclr_a = "NONE",
	altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
	altsyncram_component.widthad_a = ADDRWIDTH,
	altsyncram_component.width_a = DATAWIDTH,
	altsyncram_component.numwords_a = WORDS,

	altsyncram_component.clock_enable_input_b = "BYPASS",
	altsyncram_component.clock_enable_output_b = "BYPASS",
	altsyncram_component.outdata_reg_b = "CLOCK1",
	altsyncram_component.outdata_aclr_b = "NONE",
	altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
	altsyncram_component.widthad_b = ADDRWIDTH,
	altsyncram_component.width_b = DATAWIDTH,
	altsyncram_component.numwords_b = WORDS;

endmodule
