-- -----------------------------------------------------------------------
-- VDC RGBI to 24 bit RGB color
-- 
-- for the C128 MiSTer FPGA core, by Erik Scheffers
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

-- -----------------------------------------------------------------------

entity rgbicolor is
	port (
		rgbi: in unsigned(3 downto 0);
		r: out unsigned(7 downto 0);
		g: out unsigned(7 downto 0);
		b: out unsigned(7 downto 0)
	);
end rgbicolor;

-- -----------------------------------------------------------------------

architecture Behavioral of rgbicolor is
begin
	process(rgbi)
	begin
		case rgbi is
		when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
		when X"1" => r <= X"55"; g <= X"55"; b <= X"55";
		when X"2" => r <= X"00"; g <= X"00"; b <= X"AA";
		when X"3" => r <= X"55"; g <= X"55"; b <= X"FF";
		when X"4" => r <= X"00"; g <= X"AA"; b <= X"00";
		when X"5" => r <= X"55"; g <= X"FF"; b <= X"55";
		when X"6" => r <= X"00"; g <= X"AA"; b <= X"AA";
		when X"7" => r <= X"55"; g <= X"FF"; b <= X"FF";
		when X"8" => r <= X"AA"; g <= X"00"; b <= X"00";
		when X"9" => r <= X"FF"; g <= X"55"; b <= X"55";
		when X"A" => r <= X"AA"; g <= X"00"; b <= X"AA";
		when X"B" => r <= X"FF"; g <= X"55"; b <= X"FF";
		when X"C" => r <= X"AA"; g <= X"55"; b <= X"00";
		when X"D" => r <= X"FF"; g <= X"FF"; b <= X"55";
		when X"E" => r <= X"AA"; g <= X"AA"; b <= X"AA";
		when X"F" => r <= X"FF"; g <= X"FF"; b <= X"FF";
		end case;
	end process;
end Behavioral;
