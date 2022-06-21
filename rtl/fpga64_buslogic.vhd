-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Copyright 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------

-- -----------------------------------------------------------------------
-- Dar 08/03/2014
--
-- Based on mixing both fpga64_buslogic_roms and fpga64_buslogic_nommu
-- RAM should be external SRAM
-- Basic, Char and Kernel ROMs are included
-- Original Kernel replaced by JiffyDos
-- -----------------------------------------------------------------------
--
-- Erik Scheffers 2022
--
-- updated for C128

library IEEE;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

entity fpga64_buslogic is
	port (
		clk         : in std_logic;
		reset       : in std_logic;
		dcr         : in std_logic;
		cpslk_mode  : in std_logic;

		cpuHasBus   : in std_logic;
		aec         : in std_logic;
		z80io       : in std_logic;
		z80m1       : in std_logic;

		ramData     : in unsigned(7 downto 0);

		--   C64 mode   C128 mode
		-- 2 CHAREN     1=Disable char rom in VIC
		-- 1 HIRAM      VIC color bank
		-- 0 LORAM      CPU color bank
		bankSwitch  : in unsigned(2 downto 0);

		-- From MMU
		z80_n       : in std_logic;             -- "0" Z80, "1" 8502
		c128_n      : in std_logic;             -- "0" C128, "1" C64
		mmu_rombank : in unsigned(1 downto 0);  
		mmu_iosel   : in std_logic;
		tAddr       : in unsigned(15 downto 0); -- Translated address bus
		cpuBank     : in unsigned(1 downto 0);
		vicBank     : in unsigned(1 downto 0);

		-- From Keyboard
		cpslk_sense : in std_logic;

		-- From cartridge port
		game        : in std_logic;
		exrom       : in std_logic;
		io_rom      : in std_logic;
		io_ext      : in std_logic;
		io_data     : in unsigned(7 downto 0);

		rom_addr    : in std_logic_vector(15 downto 0);
		rom_data    : in std_logic_vector(7 downto 0);
		rom14_wr    : in std_logic;
		rom23_wr    : in std_logic;
		romF1_wr    : in std_logic;

		cpuWe       : in std_logic;
		cpuAddr     : in unsigned(15 downto 0);
		cpuData     : in unsigned(7 downto 0);
		vicAddr     : in unsigned(15 downto 0);
		vicData     : in unsigned(7 downto 0);
		sidData     : in unsigned(7 downto 0);
		mmuData     : in unsigned(7 downto 0);
		vdcData     : in unsigned(7 downto 0);
		colorData   : in unsigned(3 downto 0);
		cia1Data    : in unsigned(7 downto 0);
		cia2Data    : in unsigned(7 downto 0);
		lastVicData : in unsigned(7 downto 0);

		io_enable   : in std_logic;

		systemWe    : out std_logic;
		systemAddr  : out unsigned(17 downto 0);
		dataToCpu   : out unsigned(7 downto 0);
		dataToVic   : out unsigned(7 downto 0);

		cs_vic      : out std_logic;
		cs_sid      : out std_logic;
		cs_mmuH     : out std_logic;
		cs_mmuL     : out std_logic;
		cs_vdc      : out std_logic;
		cs_color    : out std_logic;
		cs_cia1     : out std_logic;
		cs_cia2     : out std_logic;
		cs_ram      : out std_logic;

		-- To catridge port
		cs_ioE      : out std_logic;
		cs_ioF      : out std_logic;
		cs_romL     : out std_logic;
		cs_romH     : out std_logic;
		cs_UMAXromH : out std_logic;

		-- Others
		colorA10    : out std_logic
	);
end fpga64_buslogic;

-- -----------------------------------------------------------------------

architecture rtl of fpga64_buslogic is
	signal charData       : std_logic_vector(7 downto 0);

	signal rom1Data       : std_logic_vector(7 downto 0);
	signal rom23Data      : std_logic_vector(7 downto 0);
	signal rom23Data_std  : std_logic_vector(7 downto 0);
	signal rom23Data_dcr  : std_logic_vector(7 downto 0);
	signal rom4Data       : std_logic_vector(7 downto 0);
	signal rom4Data_std   : std_logic_vector(7 downto 0);
	signal rom4Data_dcr   : std_logic_vector(7 downto 0);
	signal romF1Data      : std_logic_vector(7 downto 0);

	signal dcr_ena        : std_logic := '0';

	signal cs_CharLoc     : std_logic;
	signal cs_rom1Loc     : std_logic;
	signal cs_rom23Loc    : std_logic;
	signal cs_rom4Loc     : std_logic;
	signal cs_romF1Loc    : std_logic;
	signal vicCharLoc     : std_logic;

	signal cs_ramLoc      : std_logic;
	signal cs_vicLoc      : std_logic;
	signal cs_sidLoc      : std_logic;
	signal cs_mmuHLoc     : std_logic;
	signal cs_mmuLLoc     : std_logic;
	signal cs_vdcLoc      : std_logic;
	signal cs_colorLoc    : std_logic;
	signal cs_cia1Loc     : std_logic;
	signal cs_cia2Loc     : std_logic;
	signal cs_ioELoc      : std_logic;
	signal cs_ioFLoc      : std_logic;
	signal cs_romLLoc     : std_logic;
	signal cs_romHLoc     : std_logic;
	signal cs_UMAXromHLoc : std_logic;
	signal cs_UMAXnomapLoc: std_logic;
	signal charset_a12    : std_logic;
	signal rom23_a14      : std_logic;
	signal ultimax        : std_logic;

	signal currentAddr    : unsigned(17 downto 0);
	

begin
	-- character rom

	charset_a12 <= (not c128_n) when cpslk_mode = '0' else cpslk_sense;

	chargen: entity work.dprom
	generic map ("rtl/roms/chargen.mif", 13)
	port map
	(
		wrclock => clk,
		rdclock => clk,

		wren => rom14_wr and rom_addr(15) and not rom_addr(14) and not rom_addr(13),
		data => rom_data,
		wraddress => rom_addr(12 downto 0),

		rdaddress => std_logic_vector(charset_a12 & currentAddr(11 downto 0)),
		q => charData
	);

	-- ROM1 (U32): c64 basic+kernal rom 16K
	-- rom loc -> mem loc  contents
	-- 0000    -> A000     C64 Basic
	-- 2000    -> E000     C64 Kernal
	rom1_std: entity work.dprom
	generic map ("rtl/roms/std_C64.mif", 14)
	port map
	(
		wrclock => clk,
		rdclock => clk,

		wren => rom14_wr and not rom_addr(15) and not rom_addr(14),
		data => rom_data,
		wraddress => rom_addr(13 downto 0),

		rdaddress => std_logic_vector((cpuAddr(13) and cpuAddr(14)) & cpuAddr(12 downto 0)),
		q => rom1Data
	);

	-- ROM2+3: (U33/34) c128 basic rom 32K
	-- rom loc -> mem loc  contents
	-- 0000    -> 4000     C128 Basic Low (rom2)
	-- 4000    -> 8000     C128 Basic High (rom3)

	rom23_dcr: entity work.dprom
	generic map ("rtl/roms/dcr_basic_C128.mif", 15)
	port map
	(
		wrclock => clk,
		rdclock => clk,

		wren => rom23_wr,
		data => rom_data,
		wraddress => rom_addr(14 downto 0),

		rdaddress => std_logic_vector(not cpuAddr(14) & cpuAddr(13 downto 0)),
		q => rom23Data_dcr
	);

	rom23_std: entity work.dprom
	generic map ("rtl/roms/std_basic_C128.mif", 15)
	port map
	(
		wrclock => clk,
		rdclock => clk,

		rdaddress => std_logic_vector(not cpuAddr(14) & cpuAddr(13 downto 0)),
		q => rom23Data_std
	);

	rom23Data <= rom23Data_dcr when dcr_ena = '1' else rom23Data_std;

	-- ROM4: U35 16K
	-- rom loc -> mem loc  contents
	-- 0000    -> C000     editor
	-- 1000    -> 0000     z80 bios     (MMU sets tAddr(12) to 1 in Z80 mode when reading from $0xxx)
	-- 2000    -> E000     c128 kernal
	-- 3000    -> F000     c128 kernal

	rom4_dcr: entity work.dprom
	generic map ("rtl/roms/dcr_kernal_C128.mif", 14)
	port map
	(
		wrclock => clk,
		rdclock => clk,

		wren => rom14_wr and not rom_addr(15) and rom_addr(14),
		data => rom_data,
		wraddress => rom_addr(13 downto 0),

		rdaddress => std_logic_vector(cpuAddr(13) & tAddr(12) & cpuAddr(11 downto 0)),
		q => rom4Data_dcr
	);

	rom4_std: entity work.dprom
	generic map ("rtl/roms/std_kernal_C128.mif", 14)
	port map
	(
		wrclock => clk,
		rdclock => clk,

		rdaddress => std_logic_vector(cpuAddr(13) & tAddr(12) & cpuAddr(11 downto 0)),
		q => rom4Data_std
	);

	rom4Data <= rom4Data_dcr when dcr_ena = '1' else rom4Data_std;

	-- romF1: entity work.dprom
	-- -- generic map ("rtl/roms/function.mif", 14)
	-- port map
	-- (
	-- 	wrclock => clk,
	-- 	rdclock => clk,
	--
	-- 	wren => romF1_wr,
	-- 	data => rom_data,
	-- 	wraddress => rom_addr(13 downto 0),
	--
	-- 	rdaddress => std_logic_vector(cpuAddr(13 downto 0)),
	-- 	q => romF1Data
	-- );
	romF1Data <= (others => '0');

	process(clk)
	begin
		if rising_edge(clk) then
			if reset = '1' then
				dcr_ena <= dcr;
			end if;
		end if;
	end process;

	--
	--begin
	process(ramData, vicData, sidData, mmuData, vdcData, colorData,
		     cia1Data, cia2Data, charData, rom1Data, rom23Data, rom4Data, romF1Data,
			  cs_romHLoc, cs_romLLoc, cs_rom1Loc, cs_rom23Loc, cs_rom4Loc, cs_CharLoc, cs_romF1Loc,
			  cs_ramLoc, cs_vicLoc, cs_sidLoc, cs_colorLoc, cs_mmuLLoc, cs_mmuHLoc, cs_vdcLoc,
			  cs_cia1Loc, cs_cia2Loc, lastVicData,
			  cs_ioELoc, cs_ioFLoc,
			  io_rom, io_ext, io_data)
	begin
		-- If no hardware is addressed the bus is floating.
		-- It will contain the last data read by the VIC. (if a C64 is shielded correctly)
		dataToCpu <= lastVicData;
		if cs_CharLoc = '1' then
			dataToCpu <= unsigned(charData);
		elsif cs_rom1Loc = '1' then
			dataToCpu <= unsigned(rom1Data);
		elsif cs_rom23Loc = '1' then
			dataToCpu <= unsigned(rom23Data);
		elsif cs_rom4Loc = '1' then
			dataToCpu <= unsigned(rom4Data);
		elsif cs_romF1Loc = '1' then
			dataToCpu <= unsigned(romF1Data);
		elsif cs_ramLoc = '1' then
			dataToCpu <= ramData;
		elsif cs_vicLoc = '1' then
			dataToCpu <= vicData;
		elsif cs_sidLoc = '1' then
			dataToCpu <= sidData;
		elsif (cs_mmuLLoc = '1' or cs_mmuHLoc = '1') then
			dataToCpu <= mmuData;
		elsif cs_vdcLoc = '1' then
			dataToCpu <= vdcData;
		elsif cs_colorLoc = '1' then
			dataToCpu(3 downto 0) <= colorData;
		elsif cs_cia1Loc = '1' then
			dataToCpu <= cia1Data;
		elsif cs_cia2Loc = '1' then
			dataToCpu <= cia2Data;
		elsif cs_romLLoc = '1' then
			dataToCpu <= ramData;
		elsif cs_romHLoc = '1' then
			dataToCpu <= ramData;
		elsif cs_ioELoc = '1' and io_rom = '1' then
			dataToCpu <= ramData;
		elsif cs_ioFLoc = '1' and io_rom = '1' then
			dataToCpu <= ramData;
		elsif cs_ioELoc = '1' and io_ext = '1' then
			dataToCpu <= io_data;
		elsif cs_ioFLoc = '1' and io_ext = '1' then
			dataToCpu <= io_data;
		end if;
	end process;

	ultimax <= exrom and (not game);

	process(
		cpuHasBus, cpuAddr, tAddr, ultimax, cpuWe, bankSwitch, exrom, game, aec, vicAddr,
		c128_n, z80_n, z80io, z80m1, mmu_rombank, mmu_iosel, cpuBank, vicBank
	)
	begin
		currentAddr <= (others => '1');
		colorA10 <= '0';
		systemWe <= '0';
		vicCharLoc <= '0';
		cs_CharLoc <= '0';
		cs_rom1Loc <= '0';  -- rom1: c64 basic/kernal
		cs_rom23Loc <= '0'; -- rom23: c128 basic
		cs_rom4Loc <= '0';  -- rom4: c128 editor, z80 bios, c128 kernal
		cs_romF1Loc <= '0'; -- internal function rom
		cs_ramLoc <= '0';
		cs_vicLoc <= '0';
		cs_sidLoc <= '0';
		cs_colorLoc <= '0';
		cs_cia1Loc <= '0';
		cs_cia2Loc <= '0';
		cs_mmuHLoc <= '0';
		cs_mmuLLoc <= '0';
		cs_vdcLoc <= '0';
		cs_ioELoc <= '0';
		cs_ioFLoc <= '0';
		cs_romLLoc <= '0'; -- external rom L
		cs_romHLoc <= '0'; -- external rom H
		cs_UMAXromHLoc <= '0';		-- Ultimax flag for the VIC access - LCA
		cs_UMAXnomapLoc <= '0';

		if (cpuHasBus = '1') then
			currentAddr <= cpuBank & tAddr;

			if c128_n = '0' then
				-- C128

				-- Using untranslated address
				case cpuAddr(15 downto 12) is
				when X"C" | X"E" | X"F" =>
					if cpuAddr(15 downto 4) = X"FF0" and cpuAddr(3 downto 0) < X"5" then
						cs_mmuHLoc <= '1';
					elsif cpuWe = '0' then
						case mmu_rombank is
							when B"00" =>
								cs_rom4Loc <= '1';
							when B"01" =>
								cs_romF1Loc <= '1';
							when B"10" =>
								cs_romHLoc <= '1';
							when B"11" =>
								cs_ramLoc <= '1';
						end case;
					else
						cs_ramLoc <= '1';
					end if;
				when X"D" =>
					if ((z80_n = '1' and mmu_iosel = '0') or (z80_n = '0' and z80io = '1')) then
						case cpuAddr(11 downto 8) is
							when X"0" | X"1" | X"2" | X"3" =>
								cs_vicLoc <= '1';
							when X"4" =>
								cs_sidLoc <= not z80m1;
							when X"5" => 
								if mmu_iosel = '0' then
									cs_mmuLLoc <= '1';
								end if;
							when X"6" =>
								cs_vdcLoc <= not z80m1;
							when X"8" | X"9" | X"A" | X"B" =>
								cs_colorLoc <= '1';
							when X"C" =>
								cs_cia1Loc <= not z80m1;
							when X"D" =>
								cs_cia2Loc <= not z80m1;
							when X"E" =>
								cs_ioELoc <= not z80m1;
							when X"F" =>
								cs_ioFLoc <= not z80m1;
							when others =>
								null;
						end case;
					elsif cpuWe = '0' then
						case mmu_rombank is
							when B"00" =>
								if z80_n = '1' then
									cs_charLoc <= '1';
								else
									cs_ramLoc <= '1';
								end if;
							when B"01" =>
								cs_romF1Loc <= '1';
							when B"10" =>
								cs_romHLoc <= '1';
							when B"11" =>
								cs_ramLoc <= '1';
						end case;
					else
						cs_ramLoc <= '1';
					end if;
				when X"4" | X"5" | X"6" | X"7" | X"8" | X"9" | X"A" | X"B" =>
					if cpuWe = '0' then
						case mmu_rombank is
							when B"00" =>
								cs_rom23Loc <= '1';
							when B"01" =>
								cs_romF1Loc <= '1';
							when B"10" =>
								cs_romLLoc <= '1';
							when B"11" =>
								cs_ramLoc <= '1';
						end case;
					else
						cs_ramLoc <= '1';
					end if;
				when X"1" => 
					if cpuAddr(11 downto 10) = B"00" and z80_n = '0' and mmu_iosel = '0' then
						cs_colorLoc <= '1';
					else
						cs_ramLoc <= '1';
					end if;
				when X"0" =>
					if z80_n = '0' and z80io = '0' and mmu_rombank = B"00" and cpuWe = '0' then
						cs_rom4Loc <= '1';
					else
						cs_ramLoc <= '1';
					end if;

				when others =>
					cs_ramLoc <= '1';
				end case;

				systemWe <= cpuWe;
			else
				-- C64 mode

				case cpuAddr(15 downto 12) is
				when X"E" | X"F" =>
					if ultimax = '1' and cpuWe = '0' then
						-- ULTIMAX MODE - drop out the kernal - LCA
						cs_romHLoc <= '1';
					elsif ultimax = '1' then
						cs_UMAXnomapLoc <= '1';
					elsif cpuWe = '0' and bankSwitch(1) = '1' then
						-- Read kernal
						cs_rom1Loc <= '1';
					else
						-- 64Kbyte RAM layout
						cs_ramLoc <= '1';
					end if;
				when X"D" =>
					if ultimax = '0' and bankSwitch(1) = '0' and bankSwitch(0) = '0' then
						-- 64Kbyte RAM layout
						cs_ramLoc <= '1';
					elsif ultimax = '1' or bankSwitch(2) = '1' then
						case cpuAddr(11 downto 8) is
							when X"0" | X"1" | X"2" | X"3" =>
								cs_vicLoc <= '1';
							when X"4" =>
								cs_sidLoc <= not z80m1;
							when X"6" =>
								cs_vdcLoc <= not z80m1;
							when X"8" | X"9" | X"A" | X"B" =>
								cs_colorLoc <= '1';
							when X"C" =>
								cs_cia1Loc <= not z80m1;
							when X"D" =>
								cs_cia2Loc <= not z80m1;
							when X"E" =>
								cs_ioELoc <= not z80m1;
							when X"F" =>
								cs_ioFLoc <= not z80m1;
							when others =>
								null;
						end case;
					else
						-- I/O space turned off. Read from charrom or write to RAM.
						if cpuWe = '0' then
							cs_CharLoc <= '1';
						else
							cs_ramLoc <= '1';
						end if;
					end if;
				when X"A" | X"B" =>
					if ultimax = '1' then
						cs_UMAXnomapLoc <= '1';
					elsif exrom = '0' and game = '0' and bankSwitch(1) = '1' then
						-- this case should write to both C64 RAM and Cart RAM (if RAM is connected)
						cs_romHLoc <= '1';
					elsif ultimax = '0' and cpuWe = '0' and bankSwitch(1) = '1' and bankSwitch(0) = '1' then
						-- Access basic rom
						-- May need turning off if kernal banked out LCA
						cs_rom1Loc <= '1';
					else
						cs_ramLoc <= '1';
					end if;
				when X"8" | X"9" =>
					if ultimax = '1' then
						-- pass cpuWe to cartridge. Cartridge must block writes if no RAM connected.
						cs_romLLoc <= '1';
					elsif exrom = '0' and bankSwitch(1) = '1' and bankSwitch(0) = '1' then
						-- this case should write to both C64 RAM and Cart RAM (if RAM is connected)
						cs_romLLoc <= '1';
					else
						cs_ramLoc <= '1';
					end if;
				when X"0" =>
					cs_ramLoc <= '1';
				when others =>
					-- If not in Ultimax mode access ram
					if ultimax = '0' then
						cs_ramLoc <= '1';
					else
						cs_UMAXnomapLoc <= '1';
					end if;
				end case;

				systemWe <= cpuWe;
			end if;

		else
			-- The VIC-II has the bus, but only when aec is asserted
			if aec = '1' then
				currentAddr <= vicBank & vicAddr;
			else
				currentAddr <= cpuBank & tAddr;
			end if;

			if ultimax = '0' and vicAddr(13 downto 12)="01" and ((c128_n = '0' and bankSwitch(2) = '0') or (c128_n = '1' and vicAddr(14) = '0')) then
				vicCharLoc <= '1';
			elsif ultimax = '1' and vicAddr(13 downto 12)="11" then
				-- ultimax mode changes vic addressing - LCA
				cs_UMAXromHLoc <= '1';
			else
				cs_ramLoc <= '1';
			end if;
		end if;

		if (c128_n = '0') then
			if (cpuHasBus = '1' or aec = '0') then
				colorA10 <= not bankSwitch(0);
			else
				colorA10 <= not bankSwitch(1);
			end if;
		end if;
	end process;

	cs_ram <= cs_ramLoc or cs_romLLoc or cs_romHLoc or cs_UMAXromHLoc or cs_UMAXnomapLoc or cs_CharLoc or cs_rom1Loc or cs_rom23Loc or cs_rom4Loc or cs_romF1Loc;
	cs_vic <= cs_vicLoc and io_enable;
	cs_sid <= cs_sidLoc and io_enable;
	cs_mmuH <= cs_mmuHLoc and io_enable;
	cs_mmuL <= cs_mmuLLoc and io_enable;
	cs_vdc <= cs_vdcLoc and io_enable;
	cs_color <= cs_colorLoc and io_enable;
	cs_cia1 <= cs_cia1Loc and io_enable;
	cs_cia2 <= cs_cia2Loc and io_enable;
	cs_ioE <= cs_ioELoc and io_enable;
	cs_ioF <= cs_ioFLoc and io_enable;
	cs_romL <= cs_romLLoc;
	cs_romH <= cs_romHLoc;
	cs_UMAXromH <= cs_UMAXromHLoc;

	dataToVic  <= unsigned(charData) when vicCharLoc = '1' else ramData;
	systemAddr <= currentAddr;
end architecture;
