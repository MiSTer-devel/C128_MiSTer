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

module vdc_ramiface #(
	parameter		RAM_ADDR_BITS,

	parameter		C_LATCH_WIDTH,
	parameter 		S_LATCH_WIDTH,
	parameter 		A_LATCH_WIDTH,

	parameter      C_LATCH_BITS = $clog2(C_LATCH_WIDTH),
	parameter      S_LATCH_BITS = $clog2(S_LATCH_WIDTH),
	parameter      A_LATCH_BITS = $clog2(A_LATCH_WIDTH)
)(
	input          ram64k,   // 0 = 16kB, 1 = 64kB -- visible RAM
	input          initRam,  // 1 = initialize RAM on reset

	input          clk,
	input          reset,
	input          enable,

	input    [5:0] regA,      // selected register
	input    [7:0] db_in,     // cpu data in
	input				enableBus,
	input          cs,
	input				rs,
	input          we,        // write registers

	input		[7:0]	reg_ht,    // horizontal total
	input		[7:0]	reg_hd,    // horizontal display
	input    [7:0] reg_ai,	  // address increment
	input          reg_copy,  // copy mode
	input          reg_ram,   // configured ram, 0=16kB, 1=64kB
	input          reg_atr,   // attribute enable
	input          reg_text,  // text/bitmap mode
	input    [4:0] reg_ctv,   // character Total Vertical (minus 1)
	input	  [15:0] reg_ds,    // display start address
	input   [15:0] reg_aa,    // attribute start address
	input    [2:0] reg_cb,    // character start address
	input    [3:0] reg_drr,   // dynamic refresh count

	output  [15:0] reg_ua,    // update address
	output   [7:0] reg_wc,    // word count
	output   [7:0] reg_da,    // data
	output  [15:0] reg_ba,    // block start address

	input    [1:0] newFrame,  // 11: new full frame, 01: new odd frame, 10: new even frame
	input          newLine,
	input          newRow,    
	input          newCol,
	input          endCol,
	input    [1:0] visible,
	input    [7:0] row,
	input    [7:0] col,
	input    [4:0] line,

	output    wire busy,
	output			rowbuf,                     // buffer containing current screen info
	output   [7:0] scrnbuf[2][S_LATCH_WIDTH],  // screen codes for current and next row
	output   [7:0] attrbuf[2][A_LATCH_WIDTH],  // latch for attributes for current and next row
	output   [7:0] charbuf[C_LATCH_WIDTH],     // character data for current col
	output  [15:0] dispaddr
);


typedef enum bit[2:0] {CA_NONE, CA_READ, CA_WRITE, CA_FILL, CA_COPY[2]} cAction_t;
typedef enum bit[2:0] {RA_NONE, RA_CHAR, RA_SCRN, RA_ATTR, RA_CPU} rAction_t;

reg		  ram_rd;
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
	.addr(shuffleAddr(ram_addr, ram64k, reg_ram)),
	.dai(ram_di),
	.dao(ram_do)
);

wire en_rfsh = (col >= reg_hd && col < reg_hd+reg_drr);
wire en_scac = ~en_rfsh && col >= 2 && col < reg_ht-2;
wire en_cpu  = ~en_rfsh;

always @(posedge clk) begin
	cAction_t cpuAction;
	rAction_t ramAction;

	reg [15:0] scrnaddr;    // screen data row address
	reg [15:0] attraddr;    // attributes row address
	reg  [7:0] wda, cda;    // write/copy data
	reg  [7:0] wc;          // block word count
	reg        start_erase;
	reg        lastrowvisible;
	reg        erasing;

	reg [C_LATCH_BITS-1:0] ci; // character index
	reg [S_LATCH_BITS-1:0] si; // screen index
	reg [A_LATCH_BITS-1:0] ai; // attribute index

	integer    i;

	busy = erasing || start_erase || reset || cpuAction != CA_NONE;
	
	ram_rd <= 0;
	ram_we <= 0;

	if (reset) begin
		ci     = 0;
		si     = 0;
		ai     = 0;
		rowbuf = 0;

		wc     <= 0;
		wda    <= 0;
		cda	 <= 0;
		reg_ua <= 0;
		reg_wc <= 0;
		reg_da <= 0;
		reg_ba <= 0;
		lastrowvisible <= 1;

		cpuAction <= CA_NONE;
		ramAction <= RA_NONE;
		start_erase <= initRam;
		ram_addr <= 16'hFFFF;
		ram_di <= 0;

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
					// Does *not* change WC or DA (verified on real v1 VDC)
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
			ram_di      <= 0;
			ram_addr    <= 0;
			ram_we      <= 1;
		end
		else if (erasing) begin
			if (ram_addr == 16'hFFFF) begin
				erasing  <= 0;
				ram_we   <= 0;
			end
			else begin
				ram_di   <= (ram_addr + 16'd1) & 16'h0001 ? 8'h00 : 8'hFF;
				ram_addr <= ram_addr + 16'd1;
				ram_we   <= 1;
			end
		end 
		else if (~enable && endCol) begin
			case (ramAction)
				RA_CHAR: begin
					charbuf[ci] <= ram_do;
					ci = C_LATCH_BITS'((ci + 1) % C_LATCH_WIDTH);
				end

				RA_SCRN: begin
					// TODO: unknown how hw responds to buffer overflow
					scrnbuf[~rowbuf][si] <= ram_do;
					si = S_LATCH_BITS'(si + 1);
				end

				RA_ATTR:  begin
					// TODO: unknown how hw responds to buffer overflow
					attrbuf[~rowbuf][ai] <= ram_do;
					ai = A_LATCH_BITS'(ai + 1);
				end

				RA_CPU:
					case (cpuAction)
						CA_READ: begin
							reg_da    <= ram_do;
							cpuAction <= CA_NONE;
						end
						CA_WRITE: begin
							reg_ua    <= reg_ua + 16'd1;
							cpuAction <= CA_READ;
						end
						CA_FILL: begin
							reg_ua    <= reg_ua + 16'd1;
							wc        <= wc - 8'd1;
							cpuAction <= wc==1 ? CA_NONE : CA_FILL;
						end
						CA_COPY0: begin
							cda       <= ram_do;
							reg_ba    <= reg_ba + 16'd1;
							cpuAction <= CA_COPY1;
						end
						CA_COPY1:  begin
							reg_ua    <= reg_ua + 16'd1;
							wc        <= wc - 8'd1;
							cpuAction <= wc==1 ? CA_NONE : CA_COPY0;
						end
					endcase
			endcase
		end
		else if (enable && newCol) begin
			ram_addr <= 16'hFFFF;

			if (newLine) begin
				ci = 0;
			end;

			if (newRow) begin
				lastrowvisible <= visible[0];
				if (visible[0] || (!visible[0] && lastrowvisible)) begin
					rowbuf = ~rowbuf;

					if (~reg_text) begin
						si = 0;
						dispaddr <= scrnaddr;
					end
					else
						dispaddr <= 0;

					if (reg_atr) ai = 0;
				end
				attraddr = visible[0] ? attraddr + reg_hd + reg_ai : reg_aa;
			end

			if ((newLine && reg_text) || newRow) begin
				scrnaddr = (visible[0] && (~reg_text || |row || |line)) ? scrnaddr + reg_hd + reg_ai : reg_ds;
			end

			if (visible[0] && col < reg_hd) begin
				// fetch character data
				ramAction <= RA_CHAR;

				// TODO: unknown how hw responds to attr/scrn buffer overflow
				if (reg_text)
					ram_addr <= 16'(scrnaddr + col);
				else if (reg_ctv[4])
					ram_addr <= {reg_cb[2:1], reg_atr & attrbuf[rowbuf][col][7], scrnbuf[rowbuf][col], line[4:0]};
				else
					ram_addr <= {reg_cb,      reg_atr & attrbuf[rowbuf][col][7], scrnbuf[rowbuf][col], line[3:0]};

				ram_rd    <= 1;
			end
			else if (en_scac && si < reg_hd) begin
				// fetch screen data
				ramAction <= RA_SCRN;
				ram_addr  <= scrnaddr + si;
				ram_rd    <= 1;
			end 
			else if (en_scac && ai < reg_hd) begin
				// fetch attribute data
				ramAction <= RA_ATTR;
				ram_addr  <= attraddr + ai;
				ram_rd    <= 1;
			end
			else if (en_cpu && cpuAction != CA_NONE) begin
				// perform CPU action
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
			else
				ramAction <= RA_NONE;
		end
	end
end

endmodule
