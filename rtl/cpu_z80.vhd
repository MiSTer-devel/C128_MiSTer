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
		latch   : in  std_logic;
		reset   : in  std_logic;
		irq_n   : in  std_logic;
		io      : out std_logic;
		busrq_n : in  std_logic;
		busak_n : out std_logic;
		m1      : out std_logic;

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
signal localBusAk_n : std_logic;

signal IORQ_n : std_logic;
signal RD_n : std_logic;
signal WR_n : std_logic;
signal M1_n : std_logic;

signal WR_n_l : std_logic;
signal WR_f : std_logic;

begin

cpu: work.T80pa
port map (
	RESET_n => not reset,
	CLK => clk,
	CEN_p => enable,
	CEN_n => '1',
	INT_n => irq_n,
	NMI_n => '1',
	WAIT_n => '1',
	BUSRQ_n => busrq_n,
	M1_n => m1_n,
	IORQ_n => IORQ_n,
	RD_n => RD_n,
	WR_n => WR_n,
	BUSAK_n => localBusAk_n,
	A => localA,
	DI => localDi,
	DO => localDo
);

process(clk) begin
	if rising_edge(clk) then
		WR_n_l <= WR_n;
		WR_f <= WR_f or (WR_n_l and not WR_n);
		if latch = '1' then
			WR_f <= '0';
			we <= WR_f or (WR_n_l and not WR_n);
			io <= not IORQ_n;
			m1 <= not M1_n;
			rd <= not RD_n;
			busak_n <= localBusAk_n;
			addr <= unsigned(localA);
			do <= unsigned(localDo);
		end if;
	end if;
end process;

localDi <= std_logic_vector(di);

end architecture;
