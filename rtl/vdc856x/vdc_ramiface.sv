/********************************************************************************
 * Commodore 128 VDC
 * 
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 *
 * - timing not verified
 ********************************************************************************/

// `define VDC16K  // Enable to reduce memory usage during debugging

module vdc_ramiface (
	input          ram64k,   // 0 = 16kB, 1 = 64kB -- available RAM

	input          clk,
	input          reset,
	input          enable,

	input    [7:0] regA,      // selected register
	input    [7:0] db_in,     // cpu data in
	input				enableBus,
	input          cs,
	input				rs,
	input          we,        // write registers

	input          reg_copy,  // copy mode
	input          reg_ram,   // configured ram, 0=16kB, 1=64kB
	output  [15:0] reg_ua,    // update address
	output   [7:0] reg_wc,    // word count
	output   [7:0] reg_da,    // data
	output  [15:0] reg_ba,    // block start address

	output    wire busy
);

typedef enum {R_RESET, R_IDLE, R_READNEXT[1], R_READ[2], R_WRITE[1], R_FILL[2], R_COPY[3]} rState_t;
typedef enum {D_IDLE} dState_t;

rState_t   regState  = R_IDLE;
dState_t   dispState = D_IDLE;

reg        ram_we;
reg [15:0] ram_addr;
reg  [7:0] ram_di;
reg  [7:0] ram_do;

reg  [7:0] counter;

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

function rState_t nextRegState;
	input rState_t next;
begin
	if (reset)
		nextRegState = R_RESET;
	else
		nextRegState = next;
end
endfunction	

always @(posedge clk) begin
	if (enable) begin
		regState <= nextRegState(R_IDLE);
		ram_we   <= 0;
		busy     <= 1;

		case (regState)
			R_RESET: begin
				reg_ua   <= 0;
				reg_wc   <= 0;
				reg_da   <= 0;
				reg_ba   <= 0;
				ram_addr <= 0;
				ram_di   <= 0;
			end 

			R_IDLE: begin
				busy <= 0;
				if (enableBus && cs && rs) begin
					counter <= 1;

					if (!we) begin
						// Reading from $D601 with register 31 selected increments UA and reads
						if (regA == 31) begin
							regState <= nextRegState(R_READNEXT0);
							busy     <= 1;
						end
					end
					else begin
						case (regA)
							// Updating UA reads from new UA
							8'd18: begin
										reg_ua[15:8] <= db_in;
										regState     <= nextRegState(R_READ0);
										busy      	 <= 1;
									end
							8'd19: begin
										reg_ua[7:0]  <= db_in;
										regState     <= nextRegState(R_READ0);
										busy      	 <= 1;
									end

							// Updating WC starts a copy or fill cycle
							8'd30: begin 
										reg_wc       <= db_in;
										counter      <= db_in;
										regState     <= nextRegState(reg_copy ? R_COPY0 : R_FILL0);
										busy      	 <= 1;
									end 

							// Updating DA writes to UA, increments UA and reads from UA
							8'd31: begin 
										ram_di       <= db_in;
										regState     <= nextRegState(R_WRITE0);
										busy      	 <= 1;
									end 

							// Updating BA does not change state
							8'd32: reg_ba[15:8]   <= db_in;
							8'd33: reg_ba[7:0]    <= db_in;
						endcase
					end
				end
			end

			R_WRITE0: begin
				ram_addr <= reg_ua;
				ram_we   <= 1;
				regState <= nextRegState(R_READNEXT0);
			end
			R_READNEXT0: begin
				ram_addr <= reg_ua + 16'd1;
				reg_ua   <= reg_ua + 16'd1;
				regState <= nextRegState(R_READ1);
			end
			R_READ0: begin
				ram_addr <= reg_ua;
				regState <= nextRegState(R_READ1);
			end
			R_READ1: begin
				reg_da   <= ram_do;
			end

			R_FILL0: begin
				ram_addr <= reg_ua;
				ram_we   <= 1;
				regState <= nextRegState(R_FILL1);
			end
			R_FILL1: begin
				reg_ua   <= reg_ua + 16'd1;
				if (counter != 1) begin
					ram_we   <= 1;
					ram_addr <= reg_ua + 16'd1;
					counter  <= counter - 8'd1;
					regState <= nextRegState(R_FILL1);
				end
			end

			R_COPY0: begin
				ram_addr <= reg_ba;
				regState <= nextRegState(R_COPY1);
			end
			R_COPY1: begin
				ram_di   <= ram_do;
				reg_ba   <= reg_ba + 16'd1;
				counter  <= counter - 8'd1;
				ram_addr <= reg_ua;
				ram_we   <= 1;
				regState <= nextRegState(R_COPY2);
			end
			R_COPY2: begin
				reg_ua   <= reg_ua + 16'd1;
				if (counter > 0) begin
					ram_addr <= reg_ba;
					regState <= nextRegState(R_COPY1);
				end
			end
		endcase
	end
end

endmodule
