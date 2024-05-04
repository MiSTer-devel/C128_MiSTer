/********************************************************************************
 * Commodore 128 VDC
 *
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 *
 * - timing based on the excellent analysis by @remark on the C128 forum
 *   https://c-128.freeforums.net/post/5516/thread
 ********************************************************************************/

module vdc_ramiface #(
	parameter RAM_ADDR_BITS,

	parameter C_LATCH_WIDTH,
	parameter S_LATCH_WIDTH,

	parameter C_LATCH_BITS = $clog2(C_LATCH_WIDTH),
	parameter S_LATCH_BITS = $clog2(S_LATCH_WIDTH)
)(
	input          ram64k,   // 0 = 16kB, 1 = 64kB -- visible RAM
	input          initRam,  // 1 = initialize RAM on reset
	input          debug,

	input          clk,
	input          reset,
	input          enable,

	input    [5:0] regA,      // selected register
	input    [7:0] db_in,     // cpu data in
	input          enableBus,
	input          cs,
	input          rs,
	input          we,        // write registers

	input    [7:0] reg_ht,    // horizontal total
	input    [7:0] reg_hd,    // horizontal display
	input    [7:0] reg_ai,	  // address increment
	input          reg_copy,  // copy mode
	input          reg_ram,   // configured ram, 0=16kB, 1=64kB
	input          reg_atr,   // attribute enable
	input          reg_text,  // text/bitmap mode
	input    [4:0] reg_ctv,   // character Total Vertical (minus 1)
	input   [15:0] reg_ds,    // display start address
	input   [15:0] reg_aa,    // attribute start address
	input    [2:0] reg_cb,    // character start address
	input    [3:0] reg_drr,   // dynamic refresh count

	output  [15:0] reg_ua,    // update address
	output   [7:0] reg_wc,    // word count
	output   [7:0] reg_da,    // data
	output  [15:0] reg_ba,    // block start address

	input          fetchFrame,
	input          fetchLine,
	input          fetchRow,
	input          lastRow,
	input          newCol,
	input          endCol,
	input    [7:0] col,
	input    [4:0] line,

	output    wire busy,
	output         rowbuf,                     // buffer containing current screen info
	output   [7:0] attrbuf[2][S_LATCH_WIDTH],  // latch for attributes for current and next row
	output   [7:0] charbuf[C_LATCH_WIDTH],     // character data for current col
	output  [15:0] dispaddr
);

reg [7:0] scrnbuf[2][S_LATCH_WIDTH];  // screen codes for current and next row

typedef enum bit[2:0] {CA_IDLE, CA_READ, CA_WRITE, CA_FILL, CA_COPY[2]} cAction_t;
typedef enum bit[2:0] {RA_IDLE, RA_CHAR, RA_SCRN, RA_ATTR, RA_CPU, RA_RFSH} rAction_t;

cAction_t  cpuAction;
rAction_t  ramAction;

reg        ram_rd;
reg        ram_we;
reg [15:0] ram_addr;
reg  [7:0] ram_di;
reg  [7:0] ram_do;

function [RAM_ADDR_BITS-1:0] shuffleAddr;
	input [15:0] addr;
	input        has64k;
	input        ena64k;
begin
	if (RAM_ADDR_BITS > 14)
		shuffleAddr = RAM_ADDR_BITS'(
			ena64k ? {has64k & addr[15], addr[14:9], has64k & addr[8], addr[7:0]}
			       : {has64k & addr[15], addr[13:8], has64k & addr[8], addr[7:0]}
		);
	else
		shuffleAddr = RAM_ADDR_BITS'(ena64k ? {addr[14:9], addr[7:0]} : addr[13:0]);
end
endfunction

vdcram #(8, RAM_ADDR_BITS) ram
(
	.clk(clk),
	.rd(ram_rd),
	.we(ram_we),
	.addr(shuffleAddr(ram_addr, ram64k, reg_ram /*|| (ramAction==RA_IDLE || ramAction==RA_RFSH)*/)),
	.dai(ram_di),
	.dao(ram_do)
);

wire en_rfsh = col >= reg_hd && col <= reg_hd+reg_drr;
wire en_int = col < 2 || col >= reg_ht-8'd2;

wire [7:0] attrlen = lastRow ? 8'd2 : reg_hd;
wire [7:0] scrnlen = reg_hd;

always @(posedge clk) begin
	reg [15:0] scrnaddr;    // screen data row address
	reg [15:0] attraddr;    // attributes row address
	reg  [7:0] rfshaddr;    // refresh address
	reg  [7:0] wda, cda;    // write/copy data
	reg  [7:0] wc;          // block word count
	reg        en_char;     // enable char fetch
	reg        start_erase;
	reg        erasing;
	reg        firstLine, firstAttr;

	reg [C_LATCH_BITS-1:0] ci; // character index
	reg [S_LATCH_BITS-1:0] si; // screen index
	reg [S_LATCH_BITS-1:0] ai; // attribute index

	integer    i;

	busy = erasing || start_erase || reset || cpuAction != CA_IDLE;

	ram_rd <= 0;
	ram_we <= 0;

	if (reset) begin
		ci     = 0;
		si     = 0;
		ai     = 0;

		wc     <= 0;
		wda    <= 0;
		cda	 <= 0;
		reg_ua <= 0;
		reg_wc <= 0;
		reg_da <= 0;
		reg_ba <= 0;

		cpuAction <= CA_IDLE;
		ramAction <= RA_IDLE;
		start_erase <= initRam;
		ram_addr <= 16'hFFFF;
		ram_di <= 0;
		ram_rd <= 1;
		ram_we <= 0;

		dispaddr <= 16'hFFFF;
	end
	else begin
		if (enableBus && cs && rs) begin
			if (!we) begin
				// Reading DA loads next value into DA
				if (regA == 31) begin
					reg_ua    <= reg_ua + 16'd1;
					cpuAction <= CA_READ;
				end
			end
			else begin
				case (regA)
					// Updating UA loads value at new address into DA
					18: begin
						reg_ua[15:8] <= db_in;
						cpuAction    <= CA_READ;
					end
					19: begin
						reg_ua[7:0] <= db_in;
						cpuAction   <= CA_READ;
					end

					// Updating WC starts a COPY (from BA to UA) or FILL (to UA) for WC items
					// Does *not* change WC or DA
					30: begin
						reg_wc    <= db_in;
						wc        <= db_in;
						cpuAction <= reg_copy ? CA_COPY0 : CA_FILL;
					end

					// Updating DA writes databus to UA and loads next value into DA
					31: begin
						wda       <= db_in;
						cpuAction <= CA_WRITE;
					end

					// Updating BA does not change state
					32: reg_ba[15:8] <= db_in;
					33: reg_ba[7:0]  <= db_in;
				endcase
			end
		end

		if (start_erase) begin
			start_erase <= 0;
			erasing     <= 1;
			ram_di      <= 8'hFF;
			ram_addr    <= 0;
			ram_we      <= 1;
		end
		else if (erasing) begin
			if (ram_addr == 16'hFFFF) begin
				erasing  <= 0;
				ram_we   <= 0;
			end
			else begin
				ram_di   <= ram_addr[0] ? 8'h00 : 8'hFF;
				ram_addr <= ram_addr + 16'd1;
				ram_we   <= 1;
			end
		end
		else if (enable && endCol) begin
			charbuf[ci] <= ramAction == RA_IDLE && debug ? 8'h00 : ram_do;
			ci = C_LATCH_BITS'((ci + 1) % C_LATCH_WIDTH);

			case (ramAction)
				RA_SCRN: begin
					scrnbuf[~rowbuf][si] <= ram_do;
					si = S_LATCH_BITS'(si + 1);
				end

				RA_ATTR:  begin
					attrbuf[~rowbuf][ai] <= ram_do;
					ai = S_LATCH_BITS'(ai + 1);
				end

				RA_CPU:
					case (cpuAction)
						CA_READ: begin
							reg_da    <= ram_do;
							cpuAction <= CA_IDLE;
						end
						CA_WRITE: begin
							reg_ua    <= reg_ua + 16'd1;
							cpuAction <= CA_READ;
						end
						CA_FILL: begin
							reg_ua    <= reg_ua + 16'd1;
							wc        <= wc - 8'd1;
							cpuAction <= wc==1 ? CA_IDLE : CA_FILL;
						end
						CA_COPY0: begin
							cda       <= ram_do;
							reg_ba    <= reg_ba + 16'd1;
							cpuAction <= CA_COPY1;
						end
						CA_COPY1:  begin
							reg_ua    <= reg_ua + 16'd1;
							wc        <= wc - 8'd1;
							cpuAction <= wc==1 ? CA_IDLE : CA_COPY0;
						end
					endcase
			endcase
		end
		else if (enable && newCol) begin
			if (col == 0) begin
				if (fetchLine) begin
					ci = 0;
					en_char = 1;
				end

				if (fetchFrame) begin
					scrnaddr = reg_ds;
					firstLine <= |reg_ctv;
					firstAttr <= 1;
				end

				if (fetchRow || fetchFrame) begin
					rowbuf = ~rowbuf;

					if (!reg_text) begin
						si = 0;
						dispaddr <= scrnaddr;
					end
					else
						dispaddr <= 16'hffff;

					if (reg_atr) begin
						ai = 0;
						attraddr = fetchFrame ? reg_aa + ((reg_text && reg_ai) ? 16'd1 : 16'd0)
						                      : attraddr + reg_hd + reg_ai + ((firstAttr && reg_text && reg_ai) ? reg_ai-16'd2 : 16'd0);
						if (!fetchFrame)
							firstAttr <= 0;
					end
				end

				if (fetchRow || (reg_text && fetchLine)) begin
					scrnaddr = (fetchFrame || (reg_text && firstLine)) ? reg_ds : scrnaddr + reg_hd + reg_ai;
					firstLine <= 0;
				end
			end

			if (col == reg_hd) begin
				en_char = 0;
			end

			ram_di <= 8'hXX;

			if (en_char) begin
				// fetch character data
				ramAction <= RA_CHAR;

				if (reg_text)
					ram_addr <= 16'(scrnaddr + col);
				else if (col < S_LATCH_WIDTH) begin
					if (reg_ctv[4])
						ram_addr <= {reg_cb[2:1], reg_atr & attrbuf[rowbuf][col][7], scrnbuf[rowbuf][col], line[4:0]};
					else
						ram_addr <= {reg_cb,      reg_atr & attrbuf[rowbuf][col][7], scrnbuf[rowbuf][col], line[3:0]};
				end

				ram_rd <= 1;
			end
			else if (!en_int && en_rfsh) begin
				// ram refresh causes glitches in the last column when scrolling horizontally
				ramAction     <= RA_RFSH;
				ram_addr[7:0] <= rfshaddr;
				rfshaddr      <= rfshaddr + 1'd1;
				ram_rd        <= 1;
			end
			else if (!en_int && si < scrnlen) begin
				// fetch screen data
				ramAction <= RA_SCRN;
				ram_addr  <= scrnaddr + si;
				ram_rd    <= 1;
			end
			else if (!en_int && ai < attrlen) begin
				// fetch attribute data
				ramAction <= RA_ATTR;
				ram_addr  <= attraddr + ai;
				ram_rd    <= 1;
			end
			else if (cpuAction != CA_IDLE) begin
				// perform CPU action -- are these allowed during `en_int`?
				ramAction <= RA_CPU;

				case (cpuAction)
					CA_READ: begin
						ram_addr  <= reg_ua;
						ram_rd    <= 1;
					end
					CA_WRITE: begin
						ram_di    <= wda;
						ram_addr  <= reg_ua;
						ram_we    <= 1;
					end
					CA_FILL: begin
						ram_di    <= wda;
						ram_addr  <= reg_ua;
						ram_we    <= 1;
					end
					CA_COPY0: begin
						ram_addr  <= reg_ba;
						ram_rd    <= 1;
					end
					CA_COPY1: begin
						ram_di    <= cda;
						ram_addr  <= reg_ua;
						ram_we    <= 1;
					end
				endcase
			end
			else begin
				ram_addr  <= 16'hffff;
				ram_rd    <= 1;
				ramAction <= RA_IDLE;
			end
		end
	end
end

endmodule
