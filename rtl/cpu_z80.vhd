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
		enable  : in  std_logic_vector(1 downto 0);
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
signal localWe : std_logic;
signal localIORQ_n : std_logic;
signal localBusAk_n : std_logic;

signal IORQ_n : std_logic;
signal RD_n : std_logic;
signal WR_n : std_logic;
signal M1_n : std_logic;

signal d1mhz0 : std_logic_vector(1 downto 0);
signal d1mhz1 : std_logic_vector(1 downto 0);

signal io_x : std_logic;
signal m1_x : std_logic;
signal rd_x : std_logic;
signal we_x : std_logic;
signal busak_n_x : std_logic;
signal do_x : unsigned(7 downto 0);
signal addr_x : unsigned(15 downto 0);

signal io_l : std_logic;
signal m1_l : std_logic;
signal rd_l : std_logic;
signal we_l : std_logic;
signal busak_n_l : std_logic;
signal do_l : unsigned(7 downto 0);
signal addr_l : unsigned(15 downto 0);

begin

cpu: work.T80pa
port map (
	RESET_n => not reset,
	CLK => clk,
	CEN_p => enable(0) or enable(1),
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

process(clk)
begin
	if rising_edge(clk) then
		d1mhz0 <= d1mhz0(0) & enable(0);
		d1mhz1 <= d1mhz1(0) & enable(1);
	end if;
end process;

process(d1mhz0, IORQ_n)
begin
	if IORQ_n = '0' then
		localIORQ_n <= '0';
	elsif d1mhz0(1) = '1' then
		localIORQ_n <= '1';
	end if;
end process;

process(d1mhz0, WR_n, localIORQ_n)
begin
	if WR_n = '0' then
		localWe <= '1';
	elsif d1mhz0(1) = '1' or localIORQ_n = '0' or reset = '1' then
		localWe <= '0';
	end if;
end process;

process(clk)
begin
	if rising_edge(clk) then
		if d1mhz1(1) = '1' then
			io_l <= io_x;
			m1_l <= m1_x;
			rd_l <= rd_x;
			we_l <= we_x;
			busak_n_l <= busak_n_x;
			do_l <= do_x;
			addr_l <= addr_x;
		end if;
	end if;
end process;

io_x <= not IORQ_n;
m1_x <= not M1_n;
rd_x <= not RD_n;
we_x <= localWe;
busak_n_x <= localBusAk_n;
addr_x <= unsigned(localA);
do_x <= unsigned(localDo);

io <= io_x when d1mhz1(1) = '1' else io_l;
m1 <= m1_x when d1mhz1(1) = '1' else m1_l;
rd <= rd_x when d1mhz1(1) = '1' else rd_l;
we <= we_x when d1mhz1(1) = '1' else we_l;
busak_n <= busak_n_x when d1mhz1(1) = '1' else busak_n_l;
addr <= addr_x when d1mhz1(1) = '1' else addr_l;
do <= do_x when d1mhz1(1) = '1' else do_l;

localDi <= std_logic_vector(di);

end architecture;
