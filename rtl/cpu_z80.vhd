---------------------------------------------------------------------------------
-- Commodore 128 Z80 glue logic
-- 
-- for the C128 MiSTer FPGA core, by Erik Scheffers
---------------------------------------------------------------------------------

library IEEE;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;

-- -----------------------------------------------------------------------

entity cpu_z80 is
	port (
		clk     : in  std_logic;
		enable  : in  std_logic;
		reset   : in  std_logic;
		irq_n   : in  std_logic;
		io      : out std_logic;
		busrq_n : in  std_logic;
		busak_n : out std_logic;
		m1_n    : out std_logic;

		di      : in  unsigned(7 downto 0);
		do      : out unsigned(7 downto 0);
		addr    : out unsigned(15 downto 0);
		rd		  : out std_logic;
		we      : out std_logic
	);
end cpu_z80;

-- -----------------------------------------------------------------------

architecture rtl of cpu_z80 is

	signal localA : std_logic_vector(15 downto 0);
	signal localDo : std_logic_vector(7 downto 0);
	signal localDi : std_logic_vector(7 downto 0);

	signal IORQ_n : std_logic;
	signal RD_n : std_logic;
	signal WR_n : std_logic;

begin
	cpu: work.T80se
	port map (
		RESET_n => not reset,
		CLK_n => clk,
		CLKEN => enable,
		INT_n => irq_n,
		NMI_n => '1',
		WAIT_n => '1',
		BUSRQ_n => busrq_n,
		M1_n => m1_n,
		IORQ_n => IORQ_n,
		RD_n => RD_n,
		WR_n => WR_n,
		BUSAK_n => busak_n,
		A => localA,
		DI => localDi,
		DO => localDo
	);

	do <= unsigned(localDo);
	localDi <= std_logic_vector(di);
	rd <= not RD_n;
	we <= not WR_n;
	io <= not IORQ_n;
	addr <= unsigned(localA);

end architecture;
