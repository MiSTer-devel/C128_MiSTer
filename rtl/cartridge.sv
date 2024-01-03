/*
	CRT cartridge handling for C64 L.C.Ashmore 2017

	Improvements by Sorgelig
	C128 changes by Erik Scheffers
*/

module cartridge
#(
	parameter RAM_ADDR,
	parameter CRM_ADDR,
	parameter ROM_ADDR,
	parameter IFR_ADDR,
	parameter CRT_ADDR,
	parameter GEO_ADDR
)
(
	input             clk32,				 	// 32mhz clock source
	input             reset_n,					// reset signal
	input             c128_n,              // 0: C128 mode, 1: C64 mode

	input             cart_loading,
	input             cart_c128,  	      // C128 cart
	input      [15:0] cart_id,					// cart ID or cart type
	input       [6:0] cart_int_rom,        // internal function rom size mask: 00h=none 01h=16k, 03h=32k, 07h=64k, 0Fh=128k, 1Fh=256k, 3Fh=512k, 7Fh=1M
	input       [1:0] cart_ext_rom,        // external function rom size mask: 0=none, 1=16k, 3=32k
	input       [7:0] cart_exrom,				// CRT file EXROM status
	input       [7:0] cart_game,				// CRT file GAME status
	input      [15:0] cart_bank_laddr,		// bank loading address
	input      [15:0] cart_bank_size,		// length of each bank
	input      [15:0] cart_bank_num,
	input       [7:0] cart_bank_type,
	input      [24:0] cart_bank_raddr,		// chip packet address
	input             cart_bank_wr,
	input       [4:0] cart_bank_int,       // Internal function ROM bank number (MegaBit128)

	output            exrom,					// exrom line output (from cartridge)
	input					exrom_in,				// exrom line input (to cartridge)
	output            game,						// game line output (from cartridge)
	input					game_in,				   // game line input (to cartridge)

	input             sysRom,              // select system ROM
	input       [4:0] sysRomBank,          // system ROM bank

	input             romFL,					// romFL signal in
	input             romFH,					// romFH signal in
	input             romL,						// romL signal in
	input             romH,						// romH signal in
	input             UMAXromH,				// romH VIC II address signal
	input             IOE,						// IOE control signal
	input             IOF,						// IOF control signal
	input             mem_write,				// memory write active
	input             mem_ce,
	output            mem_ce_out,
	output reg        mem_write_out,
	output            IO_rom,					// FLAG to enable IOE/IOF address relocation
	output            IO_rd,
	output reg  [7:0] IO_data,
	input      [17:0] addr_in,             // address from cpu
	input       [7:0] data_in,  			   // data from cpu going to sdram
	output reg [24:0] addr_out, 	         // translated address output
	output reg        data_floating,

	input             freeze_key,
	input             mod_key,
	output reg        nmi,
	input             nmi_ack
);

reg        bank_lo_en;
reg  [6:0] bank_lo;
reg        bank_hi_en;
reg  [6:0] bank_hi;
reg [13:0] mask_lo;

reg [13:0] geo_bank;
reg  [6:0] IOE_bank;
reg  [6:0] IOF_bank;
reg        IOE_wr_ena;
reg        IOF_wr_ena;

reg        exrom_overide;
reg        game_overide;
assign     exrom = exrom_overide |  force_ultimax;
assign     game  = game_overide  & ~force_ultimax;

// C64 cart: 64 banks of 8K, C128 cart: 32 banks of 16K
(* ramstyle = "logic" *) reg [6:0] lobanks[0:63];
(* ramstyle = "logic" *) reg [6:0] hibanks[0:63];

reg  [7:0] bank_cnt;
always @(posedge clk32) begin
	reg old_loading;
	old_loading <= cart_loading;

	if(~old_loading & cart_loading) bank_cnt <= 0;
	if(cart_bank_wr) begin
		bank_cnt <= bank_cnt + 1'd1;
		if(cart_bank_num<(cart_c128 ? 32 : 64)) begin
			if(cart_bank_laddr <= 'h8000) begin
				lobanks[cart_bank_num[5:0]] <= cart_bank_raddr[19:13];
				if (cart_c128) begin
					if(cart_bank_size > 'h4000) hibanks[cart_bank_num[5:0]] <= cart_bank_raddr[19:13]+2'd2;
				end
				else begin
					if(cart_bank_size > 'h2000) hibanks[cart_bank_num[5:0]] <= cart_bank_raddr[19:13]+1'd1;
				end
			end
			else hibanks[cart_bank_num[5:0]] <= cart_bank_raddr[19:13];
		end
	end
end

reg IOE_ena,IOF_ena;
reg IOE_rd,IOF_rd;

assign IO_rom = (IOE & IOE_ena & ~IOE_rd) | (IOF & IOF_ena & ~IOF_rd);
assign IO_rd  = IOE_rd | IOF_rd;

reg romL_we = 0;
reg romH_we = 0;

reg old_ioe, old_iof;
always @(posedge clk32) begin
	old_ioe <= IOE;
	old_iof <= IOF;
end

wire stb_ioe = (~old_ioe & IOE);
wire stb_iof = (~old_iof & IOF);

wire ioe_wr = stb_ioe & mem_write;
wire ioe_rd = stb_ioe & ~mem_write;

wire iof_wr = stb_iof & mem_write;
//wire iof_rd = stb_iof & ~mem_write;

reg  old_freeze = 0;
wire freeze_req = (~old_freeze & freeze_key);

reg  old_nmiack = 0;
wire freeze_ack = (nmi & ~old_nmiack & nmi_ack);
wire freeze_crt = freeze_ack & ~mod_key;

reg  cart_disable = 0;
reg  allow_bank;
reg  ram_bank;
reg  reu_map;
reg  clock_port;
reg  rom_kbb;
reg  force_ultimax;

// 0018 - EXROM line status
// 0019 - GAME line status

always @(posedge clk32) begin
	reg        init_n = 0;
	reg        allow_freeze = 0;
	reg        saved_d6 = 0;
	reg [15:0] count;
	reg        count_ena;
	reg [15:0] old_id;
	reg        old_c128;

	old_freeze <= freeze_key;
	if(freeze_req & (allow_freeze | mod_key)) nmi <= 1;

	old_nmiack <= nmi_ack;
	if(freeze_ack) nmi <= 0;

	init_n <= 1;
	old_id <= cart_id;
	old_c128 <= cart_c128;

	if(~reset_n || (old_id != cart_id) || (old_c128 != cart_c128)) begin
		cart_disable <= 0;
		bank_lo_en <= 0;
		bank_lo <= 0;
		bank_hi_en <= 0;
		bank_hi <= 0;
		IOE_ena <= 0;
		IOF_ena <= 0;
		IOE_wr_ena <= 0;
		IOF_wr_ena <= 0;
		romL_we <= 0;
		romH_we <= 0;
		init_n <= 0;
		allow_freeze <= 1;
		nmi <= 0;
		saved_d6 <= 0;
		mask_lo <= 14'h3FFF;
		exrom_overide <= 1;
		game_overide <= 1;
		rom_kbb <= 0;
		geo_bank <= 0;
	end
	else if (cart_id == 255) begin
		bank_lo_en <= 0;
		bank_hi_en <= 0;
	end
	else if (cart_id == 99) begin
		// GeoRAM
		bank_lo_en <= 0;
		bank_hi_en <= 0;
		IOE_ena    <= 1;
		IOE_wr_ena <= 1;
		if(iof_wr && &addr_in[7:1]) begin
			if(addr_in[0]) geo_bank[13:6] <= data_in;
			else           geo_bank[5:0]  <= data_in[5:0];
		end
	end
	else if (cart_c128) begin
		// C128 cartridges
		exrom_overide <= 1;
		game_overide <= 1;

		case(cart_id)
			// Generic cartridge (exrom=1, game=1)
			0: begin
					bank_lo_en <= cart_ext_rom[0];
					bank_lo <= 0;
					bank_hi_en <= cart_ext_rom[1];
					bank_hi <= 1;
				end

			// Warpspeed 128
			// 16KiB ROML, 9e00-9fff mirrored to de00-dfff
			1: begin
					bank_lo_en <= 1;
					IOE_bank <= 0;
					IOE_ena  <= 1;
					IOF_bank <= 0;
					IOF_ena  <= 1;
				end

			// Comal80 128
			// 6 banks of 16KiB mapped to ROMH
			3: begin
					bank_hi_en <= 1;

					if(!init_n) begin
						bank_hi <= 0;
					end

					if(ioe_wr) begin
						bank_hi[0] <= data_in[4];
						case(data_in[6:5])
							2'b00: bank_hi[2:1] <= 2'd0;
							2'b01: bank_hi[2:1] <= 2'd1;
							2'b10: bank_hi[2:1] <= 2'd0; 
							2'b11: bank_hi[2:1] <= 2'd2;
						endcase
					end
				end

			// Magic Desk 128 
			// Up to 64 banks of 16KiB mapped to ROML
			4: begin
					bank_lo_en <= 1;

					if(!init_n) begin
						bank_lo <= 0;
					end

					if(ioe_wr || ioe_rd) begin
						if(bank_cnt <= 8) bank_lo <= data_in[2:0];
						else if(bank_cnt <= 16) bank_lo <= data_in[3:0];
						else if(bank_cnt <= 32) bank_lo <= data_in[4:0];
						else bank_lo <= data_in[5:0];
					end
				end

			// GMod2-128 (read-only)
			// Up to 32 banks of 16KiB mapped to ROML
			5: begin
					bank_lo_en <= 1;

					if(!init_n) begin
						bank_lo <= 0;
					end
					else if(ioe_wr) begin
						bank_lo <= data_in[4:0];
					end
				end
		endcase
	end
	else begin
		bank_lo_en <= 1;
		bank_hi_en <= 1;

	   // C64 cartridges
		case(cart_id)
			// Generic 8k(exrom=0,game=1), 16k(exrom=0,game=0), ULTIMAX(exrom=1,game=0)
			0: begin
					exrom_overide <= cart_exrom[0];
					game_overide <= cart_game[0];
					bank_lo <= lobanks[0];
					bank_hi <= hibanks[0];
				end

			// Action Replay v4+ - (32k 4x8k banks + 8K RAM)
			// controlled by DE00
			1:	begin
					if(nmi) allow_freeze <= 0;
					if(!init_n || freeze_crt) begin
						cart_disable  <= 0;
						exrom_overide <= 1;
						game_overide  <= 0;
						romL_we <= 0;
						bank_lo <= 0;
						bank_hi <= 0;
						IOF_bank <= 0;
						IOF_wr_ena <= 0;
						IOF_ena <= 1;
						if(~init_n) begin
							exrom_overide <= 0;
							game_overide  <= 1;
						end
					end
					else if(cart_disable) begin
						exrom_overide <= 1;
						game_overide <= 1;
						IOF_ena <= 0;
						IOF_wr_ena <= 0;
						romL_we <= 0;
						allow_freeze <= 1;
					end else begin
						if(ioe_wr) begin
							cart_disable <= data_in[2];
							bank_lo <= data_in[4:3];
							bank_hi <= data_in[4:3];
							IOF_bank <= data_in[4:3];

							if(data_in[6] | allow_freeze) begin
								allow_freeze <= 1;
								game_overide  <= ~data_in[0];
								exrom_overide <=  data_in[1];
								IOF_wr_ena <= data_in[5];
								romL_we <= data_in[5];
								if(data_in[5]) begin
									bank_lo <= 0;
									IOF_bank<= 0;
								end
							end
						end
					end
				end

			// Final Cart III - (64k 4x16k banks)
			// all banks @ $8000-$BFFF - switching by $DFFF
			3:	begin
					if(!init_n) begin
						game_overide <= 0;
						exrom_overide<= 0;
						cart_disable <= 0;
						bank_lo <= 0;
						bank_hi <= 1;
						IOE_ena <= 1;
						IOE_bank<= 0;
						IOF_ena <= 1;
						IOF_bank<= 0;
					end
					else if(!cart_disable) begin
						if(iof_wr && &addr_in[7:0]) begin
							bank_lo <= {data_in[1:0],1'd0};
							bank_hi <= {data_in[1:0],1'd1};
							IOE_bank<= {data_in[1:0],1'd0};
							IOF_bank<= {data_in[1:0],1'd0};
							exrom_overide <= data_in[4];
							game_overide  <= data_in[5];
							saved_d6 <= data_in[6];
							if(~freeze_key & saved_d6 & ~data_in[6]) nmi <= 1;
							if(data_in[6]) allow_freeze <= 1;
							cart_disable <= data_in[7];
						end
					end
					if(freeze_crt) begin
						cart_disable <= 0;
						game_overide <= 0;
						allow_freeze <= 0;
					end
				end

			// Simons Basic - (game=0, exrom=0, 2 banks by 8k)
			// Read to IOE switches 8k config
			// Write to IOE switches 16k config
			4: begin
					if(!init_n) begin
						exrom_overide <= 0;
						game_overide <= 0;
						bank_lo <= 0;
						bank_hi <= 1;
					end
					if(ioe_wr) game_overide <= 0;
					if(ioe_rd) game_overide <= 1;
				end

			// Ocean Type 1 - (game=0, exrom=0, 128k,256k or 512k in 8k banks)
			// BANK is written to lower 6 bits of $DE00 - bit 8 is always set
			// best to mirror banks at $8000 and $A000
			5:	begin
					if(!init_n) begin
						exrom_overide <= 0;
						game_overide  <= 0;
					end
					if(ioe_wr) begin
						bank_lo <= data_in[5:0];
						bank_hi <= data_in[5:0];
					end
					// Autodetect Ocean Type B (512k)
					// Only $8000 is used, while $A000 is RAM
					if(cart_bank_wr) begin
						if(cart_bank_num>=32) begin
							game_overide <= 1;
						end
					end
				end

			// PowerPlay, FunPlay
			7:	begin
					if(~init_n) begin
						exrom_overide <= 0;
						game_overide  <= 1;
					end

					if(ioe_wr) begin
						bank_lo <= {data_in[0],data_in[5:3]};
						if({data_in[7:6],data_in[2:1]} == 'b1011) exrom_overide <= 1;
						if({data_in[7:6],data_in[2:1]} == 'b0000) exrom_overide <= 0;
					end
				end

			// "Super Games"
			8:	begin
					if(~init_n) begin
						exrom_overide <= 0;
						game_overide  <= 0;
						bank_lo <= 0;
						bank_hi <= 1;
					end

					if(~cart_disable & iof_wr) begin
						bank_lo <= {data_in[1:0],1'd0};
						bank_hi <= {data_in[1:0],1'd1};
						game_overide  <= data_in[2];
						exrom_overide <= data_in[2];
						cart_disable  <= data_in[3];
					end
				end

			// Atomic/Action/Nordic Power (32k 4x8k banks + 8K RAM)
			9:	begin
					if(nmi) allow_freeze <= 0;
					if(!init_n || freeze_crt) begin
						cart_disable  <= 0;
						game_overide  <= 0;
						exrom_overide <= 1;
						romL_we       <= 0;
						romH_we       <= 0;
						bank_lo       <= 0;
						bank_hi       <= 0;
						IOF_bank      <= 0;
						IOF_wr_ena    <= 0;
						IOF_ena       <= 0;
						if(!init_n) begin
							game_overide  <= 1;
							exrom_overide <= 0;
						end
					end
					else if(cart_disable) begin
						game_overide  <= 1;
						exrom_overide <= 1;
						IOF_ena       <= 0;
						IOF_wr_ena    <= 0;
						romL_we       <= 0;
						romH_we       <= 0;
						allow_freeze  <= 1;
					end else begin
						if(ioe_wr) begin
							if(data_in[6] | allow_freeze) begin
								allow_freeze <= 1;
								cart_disable <= data_in[2];
								bank_lo      <= data_in[4:3];
								bank_hi      <= data_in[4:3];
								IOF_bank     <= data_in[4:3];
								IOF_ena      <= 1;

								if({data_in[5], data_in[1:0]} == 3'b110) begin
									game_overide  <= 0;
									exrom_overide <= 0;
									romL_we       <= 0;
									romH_we       <= 1;
									bank_hi       <= 0;
									IOF_bank      <= 0;
									IOF_wr_ena    <= 1;
								end
								else begin
									game_overide  <=~data_in[0];
									exrom_overide <= data_in[1];
									IOF_wr_ena    <= data_in[5];
									romL_we       <= data_in[5];
									romH_we       <= 0;
									if(data_in[5]) begin
										bank_lo    <= 0;
										IOF_bank   <= 0;
									end
									else if(data_in[0]) begin
										IOF_ena    <= 0; // ultimax and 16K modes don't mirror ROM to IOF
									end
								end
							end
						end
					end
				end

			// Epyx Fastload - (game=1, exrom=0, 8k bank)
			// any access to romL or $DE00 charges a capacitor
			// Once discharged the exrom drops to ON disabling cart
			10: begin
					if(!init_n) count_ena <= 0;
					if(IOE || romL) count_ena <= 1;

					if(!init_n || IOE || romL) begin
						game_overide  <= 1;
						exrom_overide <= 0;
						count <= 16384;
						IOF_ena <= 1;
						IOF_bank<= 0;
					end
					else
					if(count_ena) begin
						if(count) count <= count - 1'd1;
						else exrom_overide <= 1;
					end
				end

			// FINAL CARTRIDGE 1,2
			// 16k rom - IOE turns off rom / IOF turns rom on
			13: begin
					if(!init_n) begin
						bank_lo <= 0;
						bank_hi <= 1;
						game_overide  <= 0;
						exrom_overide <= 0;

						// Last 2 pages visible at IOE / IOF
						IOE_bank <= 0;
						IOF_bank <= 0;
						IOE_ena  <= 1;
						IOF_ena  <= 1;
					end

					if(freeze_crt) begin
						game_overide <= 0;
						allow_freeze <= 0;
					end

					if(IOE) begin
						game_overide  <= 1;
						exrom_overide <= 1;
						allow_freeze  <= 1;
					end

					if(IOF) begin
						game_overide  <= 0;
						exrom_overide <= 0;
					end
				end

			// C64GS - (game=1, exrom=0, 64 banks by 8k)
			// 8k config
			// Reading from IOE ($DE00 $DEFF) switches to bank 0
			15: begin
					game_overide  <= 1;
					exrom_overide <= 0;
					if(ioe_rd) bank_lo <= 0;
					if(ioe_wr) bank_lo <= addr_in[5:0];
				end

			// Dinamic - (game=1, exrom=0, 16 banks by 8k)
			17: begin
					game_overide  <= 1;
					exrom_overide <= 0;
					if(ioe_rd) bank_lo <= addr_in[3:0];
				end

			// Zaxxon, Super Zaxxon (game=0, exrom=0 - 4Kb + 2x8KB)
			18: begin
					mask_lo <= 'hFFF;
					game_overide  <= 0;
					exrom_overide <= 0;
					if(romL & mem_ce & ~addr_in[12]) bank_hi <= 1;
					if(romL & mem_ce &  addr_in[12]) bank_hi <= 2;
				end

			// Magic Desk - (game=1, exrom=0, up to 128 banks of 8k)
			19: begin
					if(!init_n) begin
						game_overide  <= 1;
						exrom_overide <= 0;
						bank_lo <= 0;
					end

					if(ioe_wr) begin
						if(bank_cnt <= 16) bank_lo <= data_in[3:0];
						else if(bank_cnt <= 32) bank_lo <= data_in[4:0];
						else if(bank_cnt <= 64) bank_lo <= data_in[5:0];
						else bank_lo <= data_in[6:0];
						exrom_overide <= data_in[7];
					end
				end

			// Super Snapshot v5 -(64k/128K rom 8*8k banks/4*16k banks, 32k ram 4*8k banks)
			20: begin
					if(!init_n || freeze_crt) begin
						romL_we <= 1;
						bank_lo <= 0;
						bank_hi <= 1;
						game_overide  <= 0;
						exrom_overide <= 1;
						IOE_bank <= 0;
						IOE_ena  <= 1;
						cart_disable <= 0;
					end
					else
					if(~cart_disable & ioe_wr) begin
						game_overide <=  data_in[0] | data_in[3];
						exrom_overide<= ~data_in[1] | data_in[3];
						bank_lo <= {data_in[5] & bank_cnt[3], data_in[4], data_in[2], 1'b0};
						bank_hi <= {data_in[5] & bank_cnt[3], data_in[4], data_in[2], 1'b1};
						IOE_bank<= {data_in[5] & bank_cnt[3], data_in[4], data_in[2], 1'b0};
						cart_disable <= data_in[3];
						IOE_ena <= ~data_in[3];

						//RAM overlay
						if(~data_in[1]) bank_lo <= {data_in[4], data_in[2]};
						romL_we <= ~data_in[1];
					end
				end

			// Comal80 - (game=0, exrom=0, 4 banks by 16k)
			21: begin
					if(!init_n) begin
						bank_lo <= 0;
						bank_hi <= 1;
						game_overide  <= 0;
						exrom_overide <= 0;
					end
					if(ioe_wr) begin
						case(data_in[7:5])
							'b010:
								begin
									exrom_overide <= 0;
									game_overide  <= 1;
								end
							'b111:
								begin
									exrom_overide <= 1;
									game_overide  <= 1;
								end
							default:
								begin
									exrom_overide <= 0;
									game_overide  <= 0;
								end
						endcase

						bank_lo <= {data_in[1:0], 1'b0};
						bank_hi <= {data_in[1:0], 1'b1};
					end
				end

			// Mikro Assembler - (game=1, exrom=0, 8k)
			28: begin
					game_overide  <= 1;
					exrom_overide <= 0;
					IOE_bank <= 0;
					IOE_ena  <= 1;
					IOF_bank <= 0;
					IOF_ena  <= 1;
				end

			// EASYFLASH - 1mb 128x8k/64x16k, XBank format(33) looks the same
			// upd: original Easyflash(32) boots in ultimax mode.
			// Only one XBank(33) cart has been found: soulless-xbank. It doesn't boot in ultimax mode.
			32,
			33: begin
					if(!init_n) begin
						IOF_bank<= 0;
						IOF_ena <= 1;
						IOF_wr_ena <= 1;
						exrom_overide <= (cart_id==32);
						game_overide  <= 0;
						bank_lo <= lobanks[0];
						bank_hi <= hibanks[0];
					end

					if(ioe_wr) begin
						if(addr_in[1]) begin
							game_overide  <= ~data_in[0] & data_in[2]; //assume jumper in boot position bit2=0 -> game=0
							exrom_overide <= ~data_in[1];
						end
						else begin
							bank_lo <= lobanks[data_in[5:0]];
							bank_hi <= hibanks[data_in[5:0]];
						end
					end
				end

			// Retro Replay - (64k 8x8k banks + 32K RAM)
			36: begin
					IOE_ena    <= allow_freeze;
					IOF_ena    <= allow_freeze & ~reu_map;
					IOE_wr_ena <= allow_freeze & romL_we;
					IOF_wr_ena <= allow_freeze & romL_we & ~reu_map;
					bank_lo    <= ~romL_we ? bank_hi : allow_bank ? bank_hi[1:0] : 2'b00;
					IOE_bank   <= ~romL_we ? bank_hi : allow_bank ? bank_hi[1:0] : 2'b00;
					IOF_bank   <= ~romL_we ? bank_hi : allow_bank ? bank_hi[1:0] : 2'b00;

					if(nmi) allow_freeze <= 0;
					if(!init_n || freeze_crt) begin
						cart_disable  <= 0;
						exrom_overide <= 1;
						game_overide  <= 0;
						romL_we       <= 0;
						bank_lo       <= 0;
						bank_hi       <= 0;
						IOE_ena       <= 0;
						IOF_ena       <= 0;
						IOE_wr_ena    <= 0;
						IOF_wr_ena    <= 0;
						IOE_bank      <= 0;
						IOF_bank      <= 0;
						if(~init_n) begin
							exrom_overide <= 0;
							game_overide  <= 1;
							reu_map       <= 0;
							allow_bank    <= 0;
							clock_port    <= 0;
						end
					end
					else if(cart_disable) begin
						exrom_overide <= 1;
						game_overide  <= 1;
						IOE_wr_ena    <= 0;
						IOF_wr_ena    <= 0;
						IOE_ena       <= 0;
						IOF_ena       <= 0;
						romL_we       <= 0;
						allow_freeze  <= 1;
					end else begin

						if(ioe_wr & !addr_in[7:1]) begin
							bank_hi <= {data_in[7],data_in[4:3]};

							if(~addr_in[0]) begin
								cart_disable <= data_in[2];
							end
							else begin
								if(data_in[6]) reu_map    <= 1;
								if(data_in[1]) allow_bank <= 1;
								clock_port <= data_in[0];
							end

							if((data_in[6] | allow_freeze) & ~addr_in[0]) begin
								allow_freeze  <= 1;
								game_overide  <= ~data_in[0];
								exrom_overide <=  data_in[1];
								romL_we       <=  data_in[5];
							end
						end
					end
				end

			// prophet64
			43: begin
					if(!init_n) begin
						exrom_overide <= 0;
						game_overide  <= 1;
						bank_lo       <= 0;
					end
					else if(iof_wr) begin
						bank_lo       <= data_in[4:0];
						exrom_overide <= data_in[5];
					end
				end

			// Kingsoft Business Basic
			54: begin
					game_overide  <= 0;
					exrom_overide <= 0;
					bank_lo       <= 0;
					bank_hi       <= 1;

					if(ioe_rd) rom_kbb <= 0;
					if(ioe_wr) rom_kbb <= 1;
				end

			// RGCD (game=1, exrom=0, 8 banks by 8k)
			57: begin
					if(!init_n) begin
						game_overide  <= 1;
						exrom_overide <= 0;
						bank_lo <= 0;
					end

					if(~cart_disable & ioe_wr) begin
						bank_lo <= data_in[2:0];
						if(data_in[3]) begin
							cart_disable  <= 1;
							game_overide  <= 1;
							exrom_overide <= 1;
						end
					end
				end

			// GMod2
			60: begin
					if(!init_n) begin
						exrom_overide <= 0;
						game_overide  <= 1;
						bank_lo       <= 0;
					end
					else if(ioe_wr) begin
						bank_lo       <= data_in[5:0];
						exrom_overide <= data_in[6];
					end
				end

		endcase
	end
end

// ************************************************************************************************************
// ****** Address handling - Redirection to SDRAM CRT file
// ************************************************************************************************************

wire cs_ioe = IOE && (mem_write ? IOE_wr_ena : IOE_ena);
wire cs_iof = IOF && (mem_write ? IOF_wr_ena : IOF_ena);

assign mem_ce_out = mem_ce | (cs_ioe & stb_ioe) | (cs_iof & stb_iof);

//RAM banks are mapped to 0x040000 (64K max)
//CRT/EFR banks are mapped to 0x100000 (1MB max)
function [11:0] get_bank;
	input [6:0] bank;
	input       ram;
	input       addr13;
begin
	get_bank = ram ? {9'(CRM_ADDR>>16), bank[2:0]} : (c128_n ? {5'(CRT_ADDR>>20), bank[6:0]} : {5'(CRT_ADDR>>20), bank[5:0], addr13});
end
endfunction

always begin
	IOE_rd = 0;
	IOF_rd = 0;
	IO_data = 8'hFF;
	force_ultimax = 0;
	data_floating = 0;

	//prohibit to write in ultimax mode into underlaying (actually non-existent) RAM
	mem_write_out = ~(romL & ~romL_we & exrom_overide & ~game_overide) & mem_write;
	addr_out = {7'(RAM_ADDR>>18), addr_in};

	if(reset_n) begin
		if(sysRom) addr_out[24:12] = {8'(ROM_ADDR>>17), sysRomBank};

		if(romFL && !mem_write) begin
			addr_out[24:14] = {5'(IFR_ADDR>>20), cart_bank_int & cart_int_rom[6:2], 1'b0};
			data_floating = ~cart_int_rom[0];
		end
		if(romFH && !mem_write) begin
			addr_out[24:14] = {5'(IFR_ADDR>>20), cart_bank_int & cart_int_rom[6:2], 1'b1};
			data_floating = ~cart_int_rom[1];
		end
		if(romH && (romH_we || !mem_write)) begin
			addr_out[24:13] = get_bank(bank_hi, romH_we, addr_in[13]);
			data_floating = ~bank_hi_en;
		end
		if(romL && (romL_we || !mem_write)) begin
			addr_out = {get_bank(bank_lo, romL_we, addr_in[13] & mask_lo[13]), addr_in[12:0] & mask_lo[12:0]};
			data_floating = ~bank_lo_en;
		end

		if(cs_ioe) addr_out[24:13] = get_bank(IOE_bank, IOE_wr_ena, 0); // read/write to DExx
		if(cs_iof) addr_out[24:13] = get_bank(IOF_bank, IOF_wr_ena, 0); // read/write to DFxx

		if(UMAXromH) addr_out[24:12] = {get_bank(bank_hi, 0, 0), 1'b1}; // ULTIMAX CharROM

		if (cart_id == 99) begin
			if(IOE) begin
				addr_out[24:8] = {3'(GEO_ADDR>>22), geo_bank};
			end
		end
		else if (!cart_c128)
			case(cart_id)
				36: if(IOE && !(addr_in[7:0] & (clock_port ? 8'hF0 : 8'hFE)) && !cart_disable) begin
						mem_write_out = 0;
						IOE_rd = 1;
						IO_data = (!addr_in[7:1]) ? {bank_hi[2], reu_map, 1'b0, bank_hi[1:0], 1'b0, allow_bank, 1'b0} : 8'h00;
					end
				54: if(rom_kbb && addr_in[15:13] == 3'b111 && !mem_write) begin
						force_ultimax = 1;
						addr_out[24:13] = get_bank(2, 0, 0);
					end
				default:;
			endcase
	end
end

endmodule
