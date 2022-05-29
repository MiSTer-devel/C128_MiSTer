/********************************************************************************
 * Commodore 128 VDC
 * 
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 *
 * - timing based on the excellent analysis by @remark on the C128 forum
 *   https://c-128.freeforums.net/post/5516/thread
 *
 * - timings not yet verified
 ********************************************************************************/

// `define VDC16K  // Enable to reduce memory usage during debugging

module vdc_ramiface #(
	parameter 		S_LATCH_WIDTH,
	parameter 		A_LATCH_WIDTH,
	parameter 		C_LATCH_WIDTH
)(
	input          ram64k,   // 0 = 16kB, 1 = 64kB -- available RAM

	input          clk,
	input          reset,
	input          enable,

	input    [5:0] regA,      // selected register
	input    [7:0] db_in,     // cpu data in
	input				enableBus,
	input          cs,
	input				rs,
	input          we,        // write registers

	input				reg_hd,    // horizontal display
	input          reg_copy,  // copy mode
	input          reg_ram,   // configured ram, 0=16kB, 1=64kB
	input          reg_atr,   // attribute enable
	input          reg_text,  // text/bitmap mode
	input	  [15:0] reg_ds,    // display start address
	input   [15:0] reg_aa,    // attribute start address
	input  [15:13] reg_cb,    // character start address
	input    [3:0] reg_drr,   // dynamic refresh count

	output  [15:0] reg_ua,    // update address
	output   [7:0] reg_wc,    // word count
	output   [7:0] reg_da,    // data
	output  [15:0] reg_ba,    // block start address
	output    wire busy,

	input          newFrame,
	input          newLine,
	input          newRow,
	input          newCol,

	output			currbuf,                    // buffer containing current screen info
	output   [7:0] scrnbuf[2][S_LATCH_WIDTH],  // screen codes for current and next row
	output   [7:0] attrbuf[2][A_LATCH_WIDTH],  // latch for attributes for current and next row
	output   [7:0] charbuf[C_LATCH_WIDTH],     // character data for current line
	output  [15:0] rowaddr
);

// Cycles: (from https://c-128.freeforums.net/post/5516/thread)

// 1: 80 C | 5 R | 40 S | 3 I		S: 40 screen bytes next character row
// 2: 80 C | 5 R | 40 S | 3 I		S: 40 screen bytes next character row
// 3: 80 C | 5 R | 40 A | 3 I		A: 40 attribute bytes next character row
// 4: 80 C | 5 R | 40 A | 3 I	   A: 40 attribute bytes next character row
// 5: 80 C | 5 R | 43 I
// 6: 80 C | 5 R | 43 I
// 7: 80 C | 5 R | 43 I
// 8: 80 C | 5 R | 43 I

// C: Character data bytes current line
// S: Screen memory bytes for next character row (character pointers)
// A: Attribute bytes for next character row
// R: Refresh dram bytes (R36)
// I: Internal/idle cycle ($3FFF/$FFFF on address bus)

// After the last line of the last character row the screen bytes and attribute bytes for the first character row are read :

//  2 I | 78 S |  5 R | 2 S | 38 A |  3 I    S:$0000-$004f	A:$0800-$0825
//  2 I | 42 A | 36 I | 5 R | 43 I				A:$0826-$084f
// 80 I |  5 R | 43 I

// The last line shown is repeated until you get to the first line of the first character row (I didn't check all lines)


typedef enum {R_RESET, R_IDLE, R_READNEXT[1], R_READ[2], R_WRITE[1], R_FILL[2], R_COPY[3], R_SCREEN, R_ATTR, R_CHAR, R_REFRESH} rState_t;

rState_t   regState  = R_RESET;

reg        ram_we;
reg [15:0] ram_addr;
reg  [7:0] ram_di;
reg  [7:0] ram_do;

reg  [7:0] wrdcnt;

`ifndef VDC16K
function [15:0] shuffleAddr;
	input [15:0] addr;
	input        has64k;
	input        ena64k;
begin
	shuffleAddr = ena64k ? {has64k & addr[15], addr[14:9], has64k & addr[8], addr[7:0]} 
 	                     : {has64k & addr[15], addr[13:8], has64k & addr[8], addr[7:0]};
end
endfunction
`else
function [13:0] shuffleAddr;
	input [15:0] addr;
	input        has64k;
	input        ena64k;
begin
	shuffleAddr = ena64k ? {addr[14:9], addr[7:0]} : addr[13:0];
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

integer i;

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

				currbuf  <= 0;
				for (i=0; i<S_LATCH_WIDTH; i=i+1) begin
					scrnbuf[0][i] <= 0;
					scrnbuf[1][i] <= 0;
				end
				for (i=0; i<A_LATCH_WIDTH; i=i+1) begin
					attrbuf[0][i] <= 0;
					attrbuf[1][i] <= 0;
				end
				for (i=0; i<C_LATCH_WIDTH; i=i+1) begin
					charbuf[i] <= 0;
				end

				rowaddr  <= reg_ds;
			end 

			R_IDLE: begin
				busy <= 0;
				if (enableBus && cs && rs) begin
					wrdcnt <= 1;

					if (!we) begin
						// Reading DA loads next value into DA
						if (regA == 31) begin
							regState <= nextRegState(R_READNEXT0);
							busy     <= 1;
						end
					end
					else begin
						case (regA)
							// Updating UA loads value at new address into DA
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

							// Updating WC starts a COPY (from BA to UA) or FILL (to UA) for WC items
							// Does *not* change WC or DA (verified on real v1 VDC)
							8'd30: begin 
										reg_wc       <= db_in;
										wrdcnt       <= db_in;
										regState     <= nextRegState(reg_copy ? R_COPY0 : R_FILL0);
										busy      	 <= 1;
									end 

							// Updating DA writes databus to UA and loads next value into DA
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
				if (wrdcnt != 1) begin
					ram_we   <= 1;
					ram_addr <= reg_ua + 16'd1;
					wrdcnt   <= wrdcnt - 8'd1;
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
				wrdcnt   <= wrdcnt - 8'd1;
				ram_addr <= reg_ua;
				ram_we   <= 1;
				regState <= nextRegState(R_COPY2);
			end
			R_COPY2: begin
				reg_ua   <= reg_ua + 16'd1;
				if (|wrdcnt) begin
					ram_addr <= reg_ba;
					regState <= nextRegState(R_COPY1);
				end
			end
		endcase
	end
end

endmodule
