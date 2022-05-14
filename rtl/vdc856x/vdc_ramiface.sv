// `define VDC16K  // Enable to reduce memory usage during debugging

module vdc_ramiface (
	input          ram64k,   // 0 = 16kB, 1 = 64kB -- available RAM

	input          clk,
	input          reset,
	input          enable,

	input    [7:0] regA,      // selected register
	input    [7:0] db_in,     // cpu data in
	input          cs,
	input				rs,
	input          we,        // write registers

	input          reg_copy,  // copy mode
	input          reg_ram,   // configured ram, 0=16kB, 1=64kB
	output  [15:0] reg_ua,    // update address
	output   [7:0] reg_wc,    // word count
	output   [7:0] reg_da,    // data
	output  [15:0] reg_ba,    // block start address

	output         busy
);

typedef enum {R_IDLE, R_READ, R_READ2, R_READINCR, R_READINCR2, R_WRITE, R_WRITE2, R_COPY, R_COPY2, R_COPY3} rState_t;
typedef enum {D_IDLE} dState_t;

rState_t regState  = R_IDLE;
dState_t dispState = D_IDLE;

reg        ram_we;
reg [15:0] ram_addr;
reg  [7:0] ram_di;
reg  [7:0] ram_do;

`ifndef VDC16K
function [15:0] shuffleAddr;
	input [15:0] addr;
	input        has64k;
	input        ena64k;
begin
	if (has64k & ena64k)
		shuffleAddr = {addr[15], addr[14:9], addr[8], addr[7:0]};
	else if (ena64k)
		shuffleAddr = {1'b0,     addr[14:9], 1'b0,    addr[7:0]};
	else
		shuffleAddr = {1'b0,     addr[13:8], 1'b0,    addr[7:0]};
end
endfunction
`else
function [13:0] shuffleAddr;
	input [15:0] addr;
	input        has64k;
	input        ena64k;
begin
	if (ena64k)
		shuffleAddr = {addr[14:9], addr[7:0]};
	else
		shuffleAddr = addr[13:0];
end
endfunction
`endif

`ifndef VDC16K
vdcram #(8, 16) ram
`else
vdcram #(8, 14) ram
`endif
(
	.clk(clk),
	.we(ram_we),
	.addr(shuffleAddr(ram_addr, ram64k, reg_ram)),
	.dai(ram_di),
	.dao(ram_do)
);

// RAM interface registers
always @(posedge clk) begin
	if (reset) begin
		regState <= R_IDLE;
		dispState <= D_IDLE;
		reg_ua <= 0;
		reg_wc <= 1;
		reg_da <= 0;
		reg_ba <= 0;
	end
	else if (cs && !busy) begin
		if (!rs && we) begin
			// Writing 31 to $D600 triggers a READ cycle without increment of UA
			if (db_in == 31) regState <= R_READ;
		end
		else if (rs && !we) begin
			// Reading from $D601 with register 31 selected triggers a READ cycle with increment of UA
			if (regA == 31) regState <= R_READINCR;
		end
		else if (rs && we) begin
			case (regA)
				8'd18: reg_ua[15:8] <= db_in;
				8'd19: reg_ua[7:0]  <= db_in;
				8'd30: begin 
							// Writing to $D601 with register 30 selected starts a COPY or WRITE block cycle
							reg_wc     <= db_in;
							regState   <= reg_copy ? R_COPY : R_WRITE;
						end 
				8'd31: begin 
							// Writing to $D601 with register 31 selected starts one WRITE cycle
							reg_da     <= db_in;
							reg_wc     <= 1;
							regState   <= R_WRITE;
						end 
				8'd32: reg_ba[15:8] <= db_in;
				8'd33: reg_ba[7:0]  <= db_in;
			endcase
		end
	end
	
	if (enable) begin
		ram_we <= 0;
		if (regState == R_READ) begin
			ram_addr <= reg_ua;
			regState <= R_READ2;
		end
		else if (regState == R_READ2) begin
			reg_da   <= ram_do;
			regState <= R_IDLE;
		end
		else if (regState == R_READINCR) begin
			ram_addr <= reg_ua;
			regState <= R_READINCR2;
		end
		else if (regState == R_READINCR2) begin
			reg_ua   <= reg_ua + 16'd1;
			reg_da   <= ram_do;
			regState <= R_IDLE;
		end
		else if (regState == R_WRITE) begin
			ram_addr <= reg_ua;
			ram_di   <= reg_da;
			ram_we   <= 1;
			regState <= R_WRITE2;
		end
		else if (regState == R_WRITE2) begin
			reg_ua   <= reg_ua + 16'd1;
			ram_addr <= reg_ua;
			ram_di   <= reg_da;
			ram_we   <= 1;
			if (reg_wc == 1)
				regState <= R_IDLE;
			else
				reg_wc   <= reg_wc - 8'd1;
		end
		else if (regState == R_COPY) begin
			ram_addr <= reg_ba;
			regState <= R_COPY2;
		end
		else if (regState == R_COPY2) begin
			ram_di   <= ram_do;
			reg_ba   <= reg_ba + 16'd1;
			ram_addr <= reg_ua;
			ram_we   <= 1;
			regState <= R_COPY3;
		end
		else if (regState == R_COPY3) begin
			reg_ua   <= reg_ua + 16'd1;
			if (reg_wc == 1) 
				regState <= R_IDLE;
			else begin
				reg_wc   <= reg_wc - 8'd1;
				ram_addr <= reg_ba;
				regState <= R_COPY2;
			end
		end
	end

	busy <= regState != R_IDLE;
end

endmodule
