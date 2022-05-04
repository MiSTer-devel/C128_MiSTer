---------------------------------------------------------------------------------
-- Commodore 128 MMU
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity mmu8722 is
	port(
		-- config
		sys256k: in std_logic;  -- "0" 128k system RAM, "1" 256k system RAM
		osmode: in std_logic;   -- (debug) reset state for ossel: "0" C128, "1" C64
		cpumode: in std_logic;  -- (debug) reset state for cpusel: "0" Z80, "1" 8502

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
		c4080: in std_logic;  -- "1" key up (40 col), "0" key down (80 col)

		-- 6529 style bidir pins
		exromi: in std_logic;
		exromo: out std_logic;
		gamei: in std_logic;
		gameo: out std_logic;
		fsdiri: in std_logic;
		fsdiro: out std_logic;

		-- system config
		ossel: out std_logic;           -- "0" C128, "1" C64
		cpusel: out std_logic;          -- "0" Z80, "1" 8502

		-- outgoing address bus
		ta: out unsigned(15 downto 8);
		rambank: out unsigned(1 downto 0);
		vicbank: out unsigned(1 downto 0);

		-- memory config
		memC000: out unsigned(1 downto 0);  -- $C000-$FFFF "00" Kernal ROM, "01" Int ROM, "10" Ext. ROM, "11" RAM
		mem8000: out unsigned(1 downto 0);  -- $8000-$BFFF "00" Basic ROM Hi, "01" Int ROM, "10" Ext. ROM, "11" RAM
		mem4000: out std_logic;             -- $4000-$7FFF "0" Basic ROM Lo, "1" RAM
		memD000: out std_logic              -- $D000-$DFFF "0" I/O, "1" RAM/ROM based on mmu_memC000
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

	signal addrH : unsigned(15 downto 8);
	signal z80rom : std_logic;
	signal bankmask : unsigned(1 downto 0);
	signal common_mask: unsigned(7 downto 0) := "11111100";

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
				reg_fsdir <= '1';
				reg_exrom <= '1';
				reg_game <= '1';
				reg_os <= osmode;
				reg_vicbank <= (others => '0');
				reg_commonH <= '0';
				reg_commonL <= '0';
				reg_commonSz <= (others => '0');
				common_mask <= "11111100";
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
					              reg_os <= di(6);
					when X"06" => reg_commonSz <= di(1 downto 0);
					              reg_commonL <= di(2);
					              reg_commonH <= di(3);
					              reg_vicbank <= di(7 downto 6);
									  case reg_commonSz is
									  when "00" => common_mask <= "11111100";
									  when "01" => common_mask <= "11110000";
									  when "10" => common_mask <= "11100000";
									  when "11" => common_mask <= "11000000";
									  end case;
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
-- BiDir I/O pins
-- -----------------------------------------------------------------------
	game_io: process(gamei, reg_game)
	begin
		game <= gamei and reg_game;
	end process;

	exrom_io: process(exromi, reg_exrom)
	begin
		exrom <= exromi and reg_exrom;
	end process;

	fsdir_io: process(fsdiri, reg_fsdir)
	begin
		fsdir <= fsdiri and reg_fsdir;
	end process;

-- -----------------------------------------------------------------------
-- Output signals
-- -----------------------------------------------------------------------
	ossel <= reg_os;
	cpusel <= reg_cpu;

	gameo <= game;
	exromo <= exrom;
	fsdiro <= fsdir;

	addrH <= addr(15 downto 8);
	bankmask <= sys256k & "1";
	z80rom <= not (reg_cpu or we or addr(15) or addr(14) or addr(13) or addr(12) or reg_cr(4) or reg_cr(5));

	output_addr: process(
		reg_os, reg_cr, reg_vicbank, reg_p0h, reg_p0l, reg_p1h, reg_p1l,
		reg_commonH, reg_commonL, common_mask,
		addrH, bankmask, z80rom
	)
	variable crBank: unsigned(3 downto 0);
	variable ta_buf: unsigned(7 downto 0);
	variable ta_common: unsigned(7 downto 0);
	begin
		if reg_os = '0' then
			-- C128 mode

			memC000 <= reg_cr(5 downto 4);
			mem8000 <= reg_cr(3 downto 2);
			mem4000 <= reg_cr(1);
			memD000 <= reg_cr(0);

			vicbank <= reg_vicbank and bankmask;

			crBank := "00" & reg_cr(7 downto 6) and bankmask;

			if z80rom = '1' then
				-- When reading from $0xxx in Z80 mode with upper roms enabled, actually read from $Dxxx
				rambank <= "00";
				ta_buf := X"D" & addrH(11 downto 8);
			elsif crBank = reg_p0h and addrH = reg_p0l then
				rambank <= "00";
				ta_buf := X"00";
			elsif addrH = X"00" then
				rambank <= reg_p0h(1 downto 0) and bankmask;
				ta_buf := reg_p0l;
			elsif crBank = reg_p1h and addrH = reg_p1l then
				rambank <= "00";
				ta_buf := X"01";
			elsif addrH = X"01" then
				rambank <= reg_p1h(1 downto 0) and bankmask;
				ta_buf := reg_p1l;
			else
				rambank <= crBank(1 downto 0);
				ta_buf := addrH;
			end if;

			ta_common := ta_buf and common_mask;
			if (reg_commonH = '1' and ta_common = common_mask) or (reg_commonL = '1' and ta_common = "00000000") then
				rambank <= "00";
			end if;
			ta <= ta_buf;
		else
			-- C64 mode
			memC000 <= "00";
			mem8000 <= "00";
			mem4000 <= '0';
			memD000 <= '0';
			vicbank <= "00";
			rambank <= "00";
			ta <= addrH;
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
				when X"00" => do <= (reg_cr(7 downto 6) and bankmask) & reg_cr(5 downto 0);
				when X"01" => do <= reg_pcr(0);
				when X"02" => do <= reg_pcr(1);
				when X"03" => do <= reg_pcr(2);
				when X"04" => do <= reg_pcr(3);
				when X"05" => do <= c4080 & reg_os & exrom & game & fsdir & "11" & reg_cpu;
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
