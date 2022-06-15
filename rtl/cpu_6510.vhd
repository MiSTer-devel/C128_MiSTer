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
--
-- 6510 wrapper for 65xx core
-- Adds 8 bit I/O port mapped at addresses $0000 to $0001
--
-- -----------------------------------------------------------------------
--
-- Alynna Note: Additional logic added to allow 65816 mode to work.
-- Expected memory map:

-- Address       : Desc
-- 000000-000001 : 8502 I/O
-- 000002-00CFFF : RAM bank 0 / ROM / etc
-- 00D000-00DFFF : I/O
-- 00E000-00FFFF : RAM bank 0 / ROM
-- 010000-03FFFF : RAM banks 1-3
-- 040000-0FFFFF : RAM banks 4-15 (the programmers reference says the MMU could do this)
-- 100000-FDFFFF : ~15 MB Fast RAM (only the CPU sees it)
-- FE0000-FEFFFF : VDC RAM direct access
-- FF0000-FFFFFF : Reserved (16 bit vectors must also go here...)

library IEEE;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;

-- -----------------------------------------------------------------------

entity cpu_6510 is
	port (
		clk     : in  std_logic;
		enable  : in  std_logic;
		reset   : in  std_logic;
		nmi_n   : in  std_logic;
		nmi_ack : out std_logic;
		irq_n   : in  std_logic;
		rdy     : in  std_logic;
`ifdef P85816		
		x816    : in  std_logic;
`endif
		di      : in  unsigned(7 downto 0);
		do      : out unsigned(7 downto 0);
		
		addr    : out unsigned(15 downto 0);
		page    : out unsigned(7 downto 0);
		we      : out std_logic;

		diIO    : in  unsigned(7 downto 0);
		doIO    : out unsigned(7 downto 0)
	);
end cpu_6510;

-- -----------------------------------------------------------------------

architecture rtl of cpu_6510 is
	signal localA : std_logic_vector(23 downto 0);
	signal localDi : std_logic_vector(7 downto 0);
	signal localDo : std_logic_vector(7 downto 0);
	signal localWe : std_logic;

	signal currentIO : std_logic_vector(7 downto 0);
	signal ioDir : std_logic_vector(7 downto 0);
	signal ioData : std_logic_vector(7 downto 0);
	
	signal accessIO : std_logic;
	signal enable8 : std_logic;

	signal localA8 : std_logic_vector(23 downto 0);
  signal localDo8 : std_logic_vector(7 downto 0);
  signal localWe8 : std_logic;
  signal nmi_ack8 : std_logic;
	signal vpa : std_logic;
	signal vda : std_logic;

`ifdef P85816
	signal P85816 : std_logic;
	signal enable16 : std_logic;
  signal localA16 : std_logic_vector(23 downto 0);
  signal localDo16 : std_logic_vector(7 downto 0);
  signal localWe16 : std_logic;
  signal nmi_ack16 : std_logic;
	signal vpa16 : std_logic;
	signal vda16 : std_logic;
`endif
	
begin
-- Begin CPU MUX
	cpu8: work.T65
	port map(
		Mode    => "00",
		Res_n   => not reset,
		Enable  => enable8,
		Clk     => clk,
		Rdy     => rdy,
		Abort_n => '1',
		IRQ_n   => irq_n,
		NMI_n   => nmi_n,
		SO_n    => '1',
		R_W_n   => localWe8,
		A       => localA8,
		DI      => localDi,
		DO      => localDo8,
		NMI_ack => nmi_ack8
	);

`ifdef P85816
	cpu16: work.P65c816
	port map(
    CLK => clk,
		RST_N => not reset,
		CE => enable16,
		RDY_IN => rdy,
    NMI_N => nmi_n,
		IRQ_N => irq_n,
		ABORT_N => '1',
    D_IN => localDi,
    D_OUT => localDo16,
    A_OUT => localA16,
    WE => localWe16,
		NMI_ACK => nmi_ack16,
		VPA => vpa16,
		VDA => vda16
		-- MLB
		-- VPB
	);
localA <= localA8 when P85816='0' else localA16;
localDo <= localDo8 when P85816='0' else localDo16;
localWe <= localWe8 when P85816='0' else localWe16;
nmi_ack <= nmi_ack8 when P85816='0' else nmi_ack16;
enable8 <= '0' when P85816='1' else enable;
enable16 <= '0' when P85816='0' else enable;
vpa <= '1' when P85816='0' else vpa16;
vda <= '1' when P85816='0' else vda16;
`else
localA <= localA8;
localDo <= localDo8;
localWe <= localWe8;
nmi_ack <= nmi_ack8;
enable8 <= enable;
vpa <= '1';
vda <= '1';
`endif
-- End CPU MUX

	-- Altered for 65816 support.  65816 mode only sees IO ports at 000000-000001

	accessIO <= '1' when
`ifdef P85816	
	(P85816 = '0') and 
`endif
	(localA(15 downto 1) = X"000"&"000") 
`ifdef P85816
	else '1' when (localA(23 downto 16) = "00000000") and (localA(15 downto 1) = X"000"&"000")
`endif
	else '0'; 
	
	localDi  <= localDo when localWe = '0' else std_logic_vector(di) when accessIO = '0' else ioDir when localA(0) = '0' else currentIO;

	process(clk)
	begin
		if rising_edge(clk) and (vpa='1' or vda='1' or reset='1') then
			if accessIO = '1' then
				if localWe = '0' and enable = '1' then
					if localA(0) = '0' then
						ioDir <= localDo;
					else
						ioData <= localDo;
					end if;
				end if;
			end if;
			
			currentIO <= (ioData and ioDir) or (std_logic_vector(diIO) and not ioDir);

			if reset = '1' then
				ioDir <= (others => '0');
				ioData <= (others => '1');
				currentIO <= (others => '1');
				
`ifdef P85816				
				P85816 <= x816;
				if x816='0' then
					localA16(23 downto 0) <= (others => 'Z'); 
					localDo16(7 downto 0) <= (others => 'Z'); localWe16 <= 'Z';
				else
					localA8(23 downto 0) <= (others => 'Z'); 
					localDo8(7 downto 0) <= (others => 'Z'); localWe8 <= 'Z';
				end if;
`endif				
			end if;
		end if;
	end process;

	-- Cunnect zee wires
	addr <= unsigned(localA(15 downto 0));
`ifdef P85816	
	page <= unsigned(localA(23 downto 16)) when P85816='1' else X"00";
`else
	page <= X"00";
`endif
	do <= unsigned(localDo);
	we <= not localWe;
	doIO <= unsigned(currentIO);
end architecture;
