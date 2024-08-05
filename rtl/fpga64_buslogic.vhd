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
-- Erik Scheffers 2022
--
-- extended for C128
-- moved ROM images to SRAM
-- -----------------------------------------------------------------------

library IEEE;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

entity fpga64_buslogic is
	port (
		clk         : in std_logic;
		reset       : in std_logic;
		pure64      : in std_logic;
		cpslk_mode  : in std_logic;

		cpuHasBus   : in std_logic;
		vicHasBus   : in std_logic;
		z80io       : in std_logic;
		z80m1       : in std_logic;

		ramData     : in unsigned(7 downto 0);
		ramDataFloat: in std_logic;

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

		systemWe    : out std_logic;
		systemAddr  : out unsigned(17 downto 0);
		dataToCpu   : out unsigned(7 downto 0);

		cs_vic      : out std_logic;
		cs_sid      : out std_logic;
		cs_mmuH     : out std_logic;
		cs_mmuL     : out std_logic;
		cs_vdc      : out std_logic;
		cs_color    : out std_logic;
		cs_cia1     : out std_logic;
		cs_cia2     : out std_logic;
		cs_ram      : out std_logic;
		cs_io7      : out std_logic;

		-- To cartridge port
		cs_ioE      : out std_logic;
		cs_ioF      : out std_logic;
		cs_romL     : out std_logic;
		cs_romH     : out std_logic;
		cs_romFL    : out std_logic;
		cs_romFH    : out std_logic;
		cs_UMAXromH : out std_logic;

		-- Others
		colorA10    : out std_logic;

		-- System ROMs
		cs_sysRom   : out std_logic;
		sysRomBank  : out unsigned(4 downto 0)
	);
end fpga64_buslogic;

-- -----------------------------------------------------------------------

architecture rtl of fpga64_buslogic is
	signal cs_sysRomLoc   : std_logic;
	signal cs_ramLoc      : std_logic;
	signal cs_vicLoc      : std_logic;
	signal cs_sidLoc      : std_logic;
	signal cs_mmuHLoc     : std_logic;
	signal cs_mmuLLoc     : std_logic;
	signal cs_vdcLoc      : std_logic;
	signal cs_colorLoc    : std_logic;
	signal cs_cia1Loc     : std_logic;
	signal cs_cia2Loc     : std_logic;
	signal cs_io7Loc      : std_logic;
	signal cs_ioELoc      : std_logic;
	signal cs_ioFLoc      : std_logic;
	signal cs_romLLoc     : std_logic;
	signal cs_romHLoc     : std_logic;
	signal cs_romFLLoc    : std_logic;
	signal cs_romFHLoc    : std_logic;
	signal cs_UMAXromHLoc : std_logic;
	signal cs_UMAXnomapLoc: std_logic;
	signal rom1Bank       : unsigned(4 downto 0);
	signal rom23Bank      : unsigned(4 downto 0);
	signal rom4Bank       : unsigned(4 downto 0);
	signal romCBank       : unsigned(4 downto 0);
	signal ultimax        : std_logic;

	signal currentAddr    : unsigned(17 downto 0);

begin
	rom1Bank  <= "000" & (cpuAddr(14) and cpuAddr(13)) & cpuAddr(12);
	rom4Bank  <= "001" & cpuAddr(13) & tAddr(12);
	rom23Bank <= "01"  & not cpuAddr(14) & cpuAddr(13) & cpuAddr(12);
	romCBank  <= "1000" & not ((not cpslk_mode and c128_n) or (cpslk_mode and cpslk_sense));

	process(ramData, ramDataFloat, vicData, sidData, mmuData, vdcData, colorData,
		     cia1Data, cia2Data, cs_sysRomLoc, cs_romFLLoc, cs_romFHLoc, cs_romHLoc, cs_romLLoc,
			  cs_ramLoc, cs_vicLoc, cs_sidLoc, cs_colorLoc, cs_mmuLLoc, cs_mmuHLoc, cs_vdcLoc,
			  cs_cia1Loc, cs_cia2Loc, lastVicData,
			  cs_ioELoc, cs_ioFLoc,
			  io_rom, io_ext, io_data)
	begin
		-- If no hardware is addressed the bus is floating.
		-- It will contain the last data read by the VIC. (if a C64 is shielded correctly)
		dataToCpu <= lastVicData;
		if cs_sysRomLoc = '1' then
			dataToCpu <= ramData;
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
		elsif cs_romLLoc = '1' and ramDataFloat = '0' then
			dataToCpu <= ramData;
		elsif cs_romHLoc = '1' and ramDataFloat = '0' then
			dataToCpu <= ramData;
		elsif cs_romFLLoc = '1' and ramDataFloat = '0' then
			dataToCpu <= ramData;
		elsif cs_romFHLoc = '1' and ramDataFloat = '0' then
			dataToCpu <= ramData;
		elsif cs_ioELoc = '1' and io_rom = '1' and ramDataFloat = '0' then
			dataToCpu <= ramData;
		elsif cs_ioFLoc = '1' and io_rom = '1' and ramDataFloat = '0' then
			dataToCpu <= ramData;
		elsif cs_ioELoc = '1' and io_ext = '1' then
			dataToCpu <= io_data;
		elsif cs_ioFLoc = '1' and io_ext = '1' then
			dataToCpu <= io_data;
		end if;
	end process;

	ultimax <= exrom and (not game);

	process(
		cpuHasBus, vicHasBus, cpuAddr, tAddr, ultimax, cpuWe, bankSwitch, exrom, game, vicAddr,
		pure64, c128_n, z80_n, z80io, z80m1, mmu_rombank, mmu_iosel, cpuBank, vicBank,
      rom1Bank, rom23Bank, rom4Bank, romCBank
	)
	begin
		currentAddr <= (others => '1');
		colorA10 <= '0';
		systemWe <= '0';
		cs_sysRomLoc <= '0';
		sysRomBank <= (others => '0');
		cs_ramLoc <= '0';
		cs_vicLoc <= '0';
		cs_sidLoc <= '0';
		cs_colorLoc <= '0';
		cs_cia1Loc <= '0';
		cs_cia2Loc <= '0';
		cs_mmuHLoc <= '0';
		cs_mmuLLoc <= '0';
		cs_vdcLoc <= '0';
		cs_io7Loc <= '0';
		cs_ioELoc <= '0';
		cs_ioFLoc <= '0';
		cs_romLLoc <= '0'; -- external rom L
		cs_romHLoc <= '0'; -- external rom H
		cs_romFLLoc <= '0'; -- internal function rom L
		cs_romFHLoc <= '0'; -- internal function rom H
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
					elsif cpuWe = '0' and z80io = '0' then
						case mmu_rombank is
							when B"00" =>
								cs_sysRomLoc <= '1';
								sysRomBank <= rom4Bank;
							when B"01" =>
							   cs_romFHLoc <= '1';
							when B"10" =>
								cs_romHLoc <= '1';
							when B"11" =>
								cs_ramLoc <= '1';
						end case;
					else
						cs_ramLoc <= '1';
					end if;
				when X"D" =>
					if (z80_n = '1' and mmu_iosel = '0') or z80io = '1' then
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
							when X"7" =>
								cs_io7Loc <= not z80m1;
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
									cs_sysRomLoc <= '1';
									sysRomBank <= romCBank;
								else
									cs_ramLoc <= '1';
								end if;
							when B"01" =>
								cs_romFHLoc <= '1';
							when B"10" =>
								cs_romHLoc <= '1';
							when B"11" =>
								cs_ramLoc <= '1';
						end case;
					else
						cs_ramLoc <= '1';
						if cpuAddr(11 downto 8) = X"5" and mmu_iosel = '0' then
							cs_mmuLLoc <= '1';
						end if;
					end if;
				when X"4" | X"5" | X"6" | X"7" | X"8" | X"9" | X"A" | X"B" =>
					if cpuWe = '0' and z80io = '0' then
						case mmu_rombank is
							when B"00" =>
								cs_sysRomLoc <= '1';
								sysRomBank <= rom23Bank;
							when B"01" =>
								cs_romFLLoc <= '1';
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
						cs_sysRomLoc <= '1';
						sysRomBank <= rom4Bank;
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
						cs_sysRomLoc <= '1';
						sysRomBank <= rom1Bank;
					else
						-- 64Kbyte RAM layout
						cs_ramLoc <= '1';
					end if;
				when X"D" =>
					if ultimax = '0' and bankSwitch(1) = '0' and bankSwitch(0) = '0' and z80io = '0' then
						-- 64Kbyte RAM layout
						cs_ramLoc <= '1';
					elsif ultimax = '1' or bankSwitch(2) = '1' or (mmu_iosel = '0' and z80io = '1') then
						case cpuAddr(11 downto 8) is
							when X"0" | X"1" | X"2" | X"3" =>
								cs_vicLoc <= '1';
							when X"4" =>
								cs_sidLoc <= pure64 or not z80m1;
							when X"5" =>
								cs_sidLoc <= pure64;
							when X"6" =>
								cs_vdcLoc <= not pure64 and not z80m1;
								cs_sidLoc <= pure64;
							when X"7" =>
								cs_io7Loc <= pure64 or not z80m1;
								cs_sidLoc <= pure64;
							when X"8" | X"9" | X"A" | X"B" =>
								cs_colorLoc <= '1';
							when X"C" =>
								cs_cia1Loc <= pure64 or not z80m1;
							when X"D" =>
								cs_cia2Loc <= pure64 or not z80m1;
							when X"E" =>
								cs_ioELoc <= pure64 or not z80m1;
							when X"F" =>
								cs_ioFLoc <= pure64 or not z80m1;
							when others =>
								null;
						end case;
					else
						-- I/O space turned off. Read from charrom or write to RAM.
						if cpuWe = '0' then
							cs_sysRomLoc <= '1';
							sysRomBank <= romCBank;
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
						cs_sysRomLoc <= '1';
						sysRomBank <= rom1Bank;
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
				when X"1" =>
					if cpuAddr(11 downto 10) = B"00" and z80_n = '0' and mmu_iosel = '0' then
						cs_colorLoc <= '1';
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
			-- The VIC-II has the bus, but only when vicHasBus is asserted
			if vicHasBus = '1' then
				currentAddr <= vicBank & vicAddr;
			else
				currentAddr <= cpuBank & tAddr;
			end if;

			if ultimax = '0' and vicAddr(13 downto 12)="01" and ((c128_n = '0' and bankSwitch(2) = '0') or (c128_n = '1' and vicAddr(14) = '0')) then
				cs_sysRomLoc <= '1';
				sysRomBank <= romCBank;
			elsif ultimax = '1' and vicAddr(13 downto 12)="11" then
				-- ultimax mode changes vic addressing - LCA
				cs_UMAXromHLoc <= '1';
			else
				cs_ramLoc <= '1';
			end if;
		end if;

		if (c128_n = '0') then
			if (cpuHasBus = '1') then
				colorA10 <= not bankSwitch(0);
			else
				colorA10 <= not bankSwitch(1);
			end if;
		end if;
	end process;

	cs_ram <= cs_ramLoc or cs_romLLoc or cs_romHLoc or cs_romFLLoc or cs_romFHLoc or cs_UMAXromHLoc or cs_UMAXnomapLoc or cs_sysRomLoc;
	cs_vic <= cs_vicLoc;
	cs_sid <= cs_sidLoc;
	cs_mmuH <= cs_mmuHLoc;
	cs_mmuL <= cs_mmuLLoc;
	cs_vdc <= cs_vdcLoc;
	cs_io7 <= cs_io7Loc;
	cs_color <= cs_colorLoc;
	cs_cia1 <= cs_cia1Loc;
	cs_cia2 <= cs_cia2Loc;
	cs_ioE <= cs_ioELoc;
	cs_ioF <= cs_ioFLoc;
	cs_romL <= cs_romLLoc;
	cs_romH <= cs_romHLoc;
	cs_romFL <= cs_romFLLoc;
	cs_romFH <= cs_romFHLoc;
	cs_UMAXromH <= cs_UMAXromHLoc;
	cs_sysRom <= cs_sysRomLoc;

	systemAddr <= currentAddr;
end architecture;
