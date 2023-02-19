module iecdrv_rom
(
   input             clk_sys,
   input             clk,
   input             reset,
   input             rom_loading,

   output reg        empty8k,
   output reg        rom_valid = 0,

   input       [3:0] rom_bank,
   input      [14:0] mem_a,
   output      [7:0] rom_do,

   output            rom_req,
	output reg [14:0] rom_addr,
	input             rom_wr,
	input       [7:0] rom_data
);

assign rom_req = ~(reset | rom_loading | rom_valid);

always @(posedge clk_sys) begin
   reg [3:0] rom_bank_n = 0;

   if (rom_loading)
      rom_valid <= 0;

   if (reset) begin
      rom_addr <= 0;
   end
   else if (rom_bank != rom_bank_n) begin
      rom_valid  <= 0;
      rom_addr   <= 0;
      rom_bank_n <= rom_bank;
   end
   else if (rom_req && rom_wr) begin
      if (&rom_addr)
         rom_valid <= 1;
      rom_addr <= rom_addr + 1'd1;
   end
end

always @(posedge clk_sys) begin
   if (rom_wr && !rom_addr) 
      empty8k <= 1;

   if (rom_wr && |rom_data && ~&rom_data && rom_addr[14:8] && !rom_addr[14:13]) 
      empty8k <= 0;
end

altsyncram altsyncram_component (
   .clock0 (clk_sys),
   .address_a (rom_addr),
   .addressstall_a (1'b0),
   .byteena_a (1'b1),
   .data_a (rom_data),
   .wren_a (rom_wr & rom_req),

   .clock1 (clk),
   .address_b (mem_a),
   .addressstall_b (1'b0),
   .byteena_b (1'b1),
   .rden_b (~reset & rom_valid),
   .q_b (rom_do)
);

defparam
   altsyncram_component.byte_size = 8,
   altsyncram_component.intended_device_family = "Cyclone V",
   altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
   altsyncram_component.lpm_type = "altsyncram",

   altsyncram_component.operation_mode = "DUAL_PORT",
   altsyncram_component.power_up_uninitialized = "FALSE",

   altsyncram_component.clock_enable_input_a = "BYPASS",
   altsyncram_component.clock_enable_output_a = "BYPASS",
   altsyncram_component.outdata_reg_a = "CLOCK0",
   altsyncram_component.outdata_aclr_a = "NONE",
   altsyncram_component.widthad_a = 15,
   altsyncram_component.width_a = 8,

   altsyncram_component.clock_enable_input_b = "BYPASS",
   altsyncram_component.clock_enable_output_b = "BYPASS",
   altsyncram_component.outdata_reg_b = "CLOCK1",
   altsyncram_component.outdata_aclr_b = "NONE",
   altsyncram_component.widthad_b = 15,
   altsyncram_component.width_b = 8;

endmodule
