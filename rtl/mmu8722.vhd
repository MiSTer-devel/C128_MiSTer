---------------------------------------------------------------------------------
-- Commodore 128 MMU
-- 
-- for the C128 MiSTer FPGA core, by Erik Scheffers
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity mmu8722 is
	port(
		-- config
		sys256k: in std_logic;  -- "0" 128k system RAM, "1" 256k system RAM
		osmode: in std_logic;   -- (debug) reset state for c128_n: "0" C128, "1" C64
		cpumode: in std_logic;  -- (debug) reset state for z80_n: "0" Z80, "1" 8502

		-- bus
		clk: in std_logic;
		reset: in std_logic;

		cs_io: in std_logic;  -- select IO registers at $D50x
		cs_lr: in std_logic;  -- select Load registers at $FF0x

		we: in std_logic;

		addr: in unsigned(15 downto 0);
		di: in unsigned(7 downto 0);
		do: out unsigned(7 downto 0);

		-- input pin
		d4080: in std_logic;  -- "1" key up (40 col), "0" key down (80 col)

		-- 6529 style bidir pins
		exromi: in std_logic;
		exromo: out std_logic;
		gamei: in std_logic;
		gameo: out std_logic;
		fsdiri: in std_logic;
		fsdiro: out std_logic;

		-- system config
		c128_n: out std_logic;       		  -- "0" C128, "1" C64
		z80_n: out std_logic;       	 	  -- "0" Z80, "1" 8502
		rombank: out unsigned(1 downto 0); -- "00" system rom  "01" internal rom "10" external rom "11" ram
		iosel: out std_logic;              -- "0" select IO  "1" select rom/ram according to rombank

		-- translated address bus
		tAddr: out unsigned(15 downto 0);
		cpuBank: out unsigned(1 downto 0);
		vicBank: out unsigned(1 downto 0)
	);
end mmu8722;

architecture rtl of mmu8722 is

	subtype configReg is unsigned(7 downto 0);
	type configStore is array(3 downto 0) of configReg;

	signal reg_cr : configReg;
	signal reg_pcr : configStore;
	signal reg_cpu : std_logic;
	signal reg_fsdir : std_logic := '1';
	signal reg_exrom : std_logic := '1';
	signal reg_game : std_logic := '1';
	signal reg_os : std_logic;
	signal reg_vicbank : unsigned(1 downto 0);
	signal reg_commonH : std_logic;
	signal reg_commonL : std_logic;
	signal reg_commonSz : unsigned(1 downto 0);

	signal reg_p0hb : unsigned(3 downto 0);
	signal reg_p0h : unsigned(3 downto 0);
	signal reg_p0l : unsigned(7 downto 0);
	signal reg_p1hb : unsigned(3 downto 0);
	signal reg_p1h : unsigned(3 downto 0);
	signal reg_p1l : unsigned(7 downto 0) := X"01";

	signal fsdir : std_logic;
	signal exrom : std_logic;
	signal game : std_logic;

	signal systemMask: unsigned(1 downto 0);

begin

-- -----------------------------------------------------------------------
-- Write registers
-- -----------------------------------------------------------------------
	writeRegisters: process(clk)
	begin
		if rising_edge(clk) then
			-- write to registers
			if (reset = '1') then
				reg_pcr(0) <= (others => '0');
				reg_pcr(1) <= (others => '0');
				reg_pcr(2) <= (others => '0');
				reg_pcr(3) <= (others => '0');
				reg_cr <= (others => '0');
				reg_cpu <= cpumode;
				reg_fsdir <= cpumode or osmode;
				reg_exrom <= cpumode or osmode;
				reg_game <= cpumode or osmode;
				reg_os <= osmode;
				reg_vicbank <= (others => '0');
				reg_commonH <= '0';
				reg_commonL <= '0';
				reg_commonSz <= (others => '0');
				reg_p0hb <= (others => '0');
				reg_p0h <= (others => '0');
				reg_p0l <= (others => '0');
				reg_p1hb <= (others => '0');
				reg_p1h <= (others => '0');
				reg_p1l <= X"01";
			elsif (we = '1') then
				if (cs_lr = '1') then
					case addr(2 downto 0) is
					when "000" => reg_cr <= di;
					when "001" => reg_cr <= reg_pcr(0);
					when "010" => reg_cr <= reg_pcr(1);
					when "011" => reg_cr <= reg_pcr(2);
					when "100" => reg_cr <= reg_pcr(3);
					when others => null;
					end case;
				elsif (cs_io = '1') then
					case addr(7 downto 0) is
					when X"00" => reg_cr <= di;
					when X"01" => reg_pcr(0) <= di;
					when X"02" => reg_pcr(1) <= di;
					when X"03" => reg_pcr(2) <= di;
					when X"04" => reg_pcr(3) <= di;
					when X"05" => reg_cpu <= di(0);
									  reg_fsdir <= di(3);
									  reg_game <= di(4);
									  reg_exrom <= di(5);
									  reg_os <= di(6);
					when X"06" => reg_commonSz <= di(1 downto 0);
									  reg_commonL <= di(2);
									  reg_commonH <= di(3);
									  reg_vicbank <= di(7 downto 6);
					when X"07" => reg_p0l <= di;
									  reg_p0h <= reg_p0hb;
					when X"08" => reg_p0hb <= di(3 downto 0);
					when X"09" => reg_p1l <= di;
									  reg_p1h <= reg_p1hb;
					when X"0A" => reg_p1hb <= di(3 downto 0);
					when others => null;
					end case;
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Output
-- -----------------------------------------------------------------------
	-- TODO is d4080 bidirectional too?
	game <= gamei and reg_game;
	gameo <= game;
	exrom <= exromi and reg_exrom;
	exromo <= exrom;
	fsdir <= fsdiri and reg_fsdir;
	fsdiro <= fsdir;

	systemMask <= sys256k & "1";

	translate_addr: process(clk)
	variable bank: unsigned(1 downto 0);
	variable cpuMask: unsigned(1 downto 0);
	variable crBank: unsigned(3 downto 0);
	variable page: unsigned(15 downto 8);
	variable tPage: unsigned(15 downto 8);
	variable commonPage: unsigned(7 downto 0);
	variable commonMem: std_logic;
	variable commonPageMask: unsigned(7 downto 0);
	begin
		if rising_edge(clk) then
			page := addr(15 downto 8);

			c128_n <= reg_os;
			z80_n <= reg_cpu;

			if reg_os = '0' then
				-- C128/Z80 mode
				vicBank <= reg_vicbank and systemMask;

				case reg_commonSz is
				when "00" => commonPageMask := "11111100"; -- 00..03 / FC..FF = 1k
				when "01" => commonPageMask := "11110000"; -- 00..0F / F0..FF = 4k
				when "10" => commonPageMask := "11100000"; -- 00..1F / E0..FF = 8k
				when "11" => commonPageMask := "11000000"; -- 00..3F / C0..FF =16k
				end case;

				commonPage := page and commonPageMask;
				if (reg_commonH = '1' and commonPage = commonPageMask) or (reg_commonL = '1' and commonPage = "00000000") then
					cpuMask := "00";
					crBank := "0000";
				else
					cpuMask := systemMask;
					crBank := "00" & reg_cr(7 downto 6) and systemMask;
				end if;

				bank := "00";
				if crBank = B"00" and addr(15 downto 12) = X"0" and reg_cpu = '0' and we = '0' then
					-- When reading from $00xxx in Z80 mode, always read from $0Dxxx. Buslogic will enable ROM4
					tPage := X"D" & addr(11 downto 8);
				elsif page = X"01" then
					bank := reg_p1h(1 downto 0) and cpuMask;
					tPage := reg_p1l;
				elsif page = X"00" then
					bank := reg_p0h(1 downto 0) and cpuMask;
					tPage := reg_p0l;
				elsif crBank = reg_p1h and page = reg_p1l then
					bank := reg_p1h(1 downto 0) and cpuMask;
					tPage := X"01";
				elsif crBank = reg_p0h and page = reg_p0l then
					bank := reg_p0h(1 downto 0) and cpuMask;
					tPage := X"00";
				else
					bank := crBank(1 downto 0);
					tPage := page;
				end if;

				cpuBank <= bank;
				case addr(15 downto 14) is
				when "11" => rombank <= reg_cr(5 downto 4);
				when "10" => rombank <= reg_cr(3 downto 2);
				when "01" => rombank <= reg_cr(1) & reg_cr(1);
				when "00" => rombank <= bank;
				end case;
				iosel <= reg_cr(0);

				tAddr <= tPage & addr(7 downto 0);
			else
				-- C64 mode
				vicBank <= "00";
				cpuBank <= "00";
				rombank <= "00";
				iosel <= '0';

				tAddr <= addr;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Read registers
-- -----------------------------------------------------------------------
	readRegisters: process(clk)
	begin
		if rising_edge(clk) then
			if we = '0' and (cs_io = '1' or cs_lr = '1') then
				case addr(7 downto 0) is
				when X"00" => do <= (reg_cr(7 downto 6) and systemMask) & reg_cr(5 downto 0);
				when X"01" => do <= reg_pcr(0);
				when X"02" => do <= reg_pcr(1);
				when X"03" => do <= reg_pcr(2);
				when X"04" => do <= reg_pcr(3);
				when X"05" => do <= d4080 & reg_os & exrom & game & fsdir & "11" & reg_cpu;
				when X"06" => do <= reg_vicbank & "11" & reg_commonH & reg_commonL & reg_commonSz;
				when X"07" => do <= reg_p0l;
				when X"08" => do <= "1111" & reg_p0h;
				when X"09" => do <= reg_p1l;
				when X"0A" => do <= "1111" & reg_p1h;
				when X"0B" => do <= "0" & sys256k & (not sys256k) & "00000";
				when others => do <= (others => '1');
				end case;
			end if;
		end if;
	end process;

end architecture;
