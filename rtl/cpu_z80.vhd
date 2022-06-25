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

type phaseDef is (PH0, PH1, PH2, PH3);

signal localA : std_logic_vector(15 downto 0);
signal localDo : std_logic_vector(7 downto 0);
signal localDi : std_logic_vector(7 downto 0);

signal CEN_p : std_logic;
signal IORQ_n : std_logic;
signal RD_n : std_logic;
signal WR_n : std_logic;
signal M1_n : std_logic;

signal io_p : std_logic;
signal we_p : std_logic;

signal we_l1 : std_logic;
signal we_l3 : std_logic;

signal phase : phaseDef := phaseDef'low;

begin

cpu: work.T80pa
port map (
	RESET_n => not reset,
	CLK => clk,
	CEN_p => CEN_p,
	CEN_n => '1',
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

CEN_p <= '1' when (enable = '1' and phase = PH0) or phase = PH2 else '0';

io_p <= not IORQ_n;
we_p <= not WR_n;

process(clk)
begin
	if rising_edge(clk) then
		if reset = '1' then
			phase <= phaseDef'low;
		elsif enable = '1' or phase /= PH0 then
			phase <= phaseDef'succ(phase);
		end if;

		case phase is
		when PH0 =>
			we_l3 <= we_l1 or we_p;
		when PH2 => 
			we_l1 <= we_p and not io_p;
		when others => null;
		end case;
	end if;
end process;

m1 <= not M1_n;
io <= io_p;
rd <= not RD_n;
we <= (we_l1 or we_p) when phase = PH0 else we_l3;
addr <= unsigned(localA);
do <= unsigned(localDo);
localDi <= std_logic_vector(di);

end architecture;
