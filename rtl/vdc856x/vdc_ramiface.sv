/********************************************************************************
 * Commodore 128 VDC
 * 
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 ********************************************************************************/

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

typedef enum {R_IDLE, R_READ[2], R_READINCR[2], R_WRITE[2], R_FILL[3], R_COPY[3]} rState_t;
typedef enum {D_IDLE} dState_t;

rState_t regState  = R_IDLE;
dState_t dispState = D_IDLE;

reg        ram_we;
reg [15:0] ram_addr;
reg  [7:0] ram_di;
reg  [7:0] ram_do;

reg  [7:0] counter;
reg        started;

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
		busy <= 0;
		started <= 0;
		reg_ua <= 0;
		reg_wc <= 0;
		reg_da <= 0;
		reg_ba <= 0;
	end
	else if (cs) begin
		if (rs && !busy) begin
			if (!we) begin
				// Reading from $D601 with register 31 selected triggers a READ cycle with increment of UA
				if (regA == 31) begin
					regState <= R_READINCR0;
					busy <= 1;
					started <= 1;
				end
			end
			else begin
				case (regA)
					8'd18: begin
								// Updating UA triggers a read cycle without increment
								reg_ua[15:8] <= db_in;
								regState     <= R_READ0;
								busy         <= 1;
								started      <= 1;
							end
					8'd19: begin
								// Updating UA triggers a read cycle without increment
								reg_ua[7:0]  <= db_in;
								regState     <= R_READ0;
								busy         <= 1;
								started      <= 1;
							end
					8'd30: begin 
								// Writing to $D601 with register 30 selected starts a COPY or FILL block cycle
								reg_wc       <= db_in;
								counter      <= db_in;
								regState     <= reg_copy ? R_COPY0 : R_FILL0;
								busy         <= 1;
								started      <= 1;
							end 
					8'd31: begin 
								// Writing to $D601 with register 31 selected starts one WRITE followed by a READ
								ram_di       <= db_in;
								regState     <= R_WRITE0;
								busy         <= 1;
								started      <= 1;
							end 
					8'd32: reg_ba[15:8]   <= db_in;
					8'd33: reg_ba[7:0]    <= db_in;
				endcase
			end
		end
	end
	else
		started <= 0;
	
	if (enable) begin
		ram_we <= 0;
		case (regState)
			R_IDLE: if (!started) busy <= 0;

			// Read current UA
			R_READ0: begin
				ram_addr <= reg_ua;
				regState <= R_READ1;
			end
			R_READ1: begin
				reg_da   <= ram_do;
				regState <= R_IDLE;
			end

			// Read current UA and incement UA
			R_READINCR0: begin
				ram_addr <= reg_ua;
				regState <= R_READINCR1;
			end
			R_READINCR1: begin
				reg_ua   <= reg_ua + 16'd1;
				reg_da   <= ram_do;
				regState <= R_IDLE;
			end

			// Write `ram_di` to UA, increment UA and read
			R_WRITE0: begin
				ram_addr <= reg_ua;
				ram_we   <= 1;
				regState <= R_WRITE1;
			end
			R_WRITE1: begin
				reg_ua   <= reg_ua + 16'd1;
				regState <= R_READ0;
			end

			// Fill range with `ram_di`
			R_FILL0: begin
				ram_addr <= reg_ua;
				ram_we   <= 1;
				regState <= R_FILL1;
			end
			R_FILL1: begin
				reg_ua   <= reg_ua + 16'd1;
				counter  <= counter - 8'd1;
				regState <= R_FILL2;
			end
			R_FILL2: begin
				ram_addr = reg_ua;
				if (counter == 0)
					regState <= R_IDLE;
				else begin
					ram_we <= 1;
					regState <= R_FILL1;
				end
			end

			// Copy range from BA to UA
			R_COPY0: begin
				ram_addr <= reg_ba;
				regState <= R_COPY1;
			end
			R_COPY1: begin
				ram_di   <= ram_do;
				reg_ba   <= reg_ba + 16'd1;
				counter  <= counter - 8'd1;
				ram_addr <= reg_ua;
				ram_we   <= 1;
				regState <= R_COPY2;
			end
			R_COPY2: begin
				reg_ua <= reg_ua + 16'd1;
				if (counter == 0)
					regState <= R_IDLE;
				else begin
					ram_addr <= reg_ba;
					regState <= R_COPY1;
				end
			end
		endcase
	end
end

endmodule
