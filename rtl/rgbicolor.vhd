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
		palette: in std_logic_vector(3 downto 0);
		rgbi: in unsigned(3 downto 0);
		r: out unsigned(7 downto 0);
		g: out unsigned(7 downto 0);
		b: out unsigned(7 downto 0)
	);
end rgbicolor;

-- -----------------------------------------------------------------------

architecture Behavioral of rgbicolor is
begin
	process(palette, rgbi)
	begin
		if palette(3 downto 2) = B"00" then
			-- source: https://int10h.org/blog/2022/06/ibm-5153-color-true-cga-palette/
			case rgbi is
			when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
			when X"1" => r <= X"4E"; g <= X"4E"; b <= X"4E";
			when X"2" => r <= X"00"; g <= X"00"; b <= X"C4";
			when X"3" => r <= X"4E"; g <= X"4E"; b <= X"DC";
			when X"4" => r <= X"00"; g <= X"C4"; b <= X"00";
			when X"5" => r <= X"4E"; g <= X"DC"; b <= X"4E";
			when X"6" => r <= X"00"; g <= X"C4"; b <= X"C4";
			when X"7" => r <= X"4E"; g <= X"F3"; b <= X"F3";
			when X"8" => r <= X"C4"; g <= X"00"; b <= X"00";
			when X"9" => r <= X"DC"; g <= X"4E"; b <= X"4E";
			when X"A" => r <= X"C4"; g <= X"00"; b <= X"C4";
			when X"B" => r <= X"F3"; g <= X"4E"; b <= X"F3";
			when X"C" => r <= X"C4"; g <= X"7E"; b <= X"00";
			when X"D" => r <= X"F3"; g <= X"F3"; b <= X"4E";
			when X"E" => r <= X"C4"; g <= X"C4"; b <= X"C4";
			when X"F" => r <= X"FF"; g <= X"FF"; b <= X"FF";
			end case;
		elsif palette(3 downto 2) = B"01" then
			r <= rgbi(3) & rgbi(0) & rgbi(3) & rgbi(0) & rgbi(3) & rgbi(0) & rgbi(3) & rgbi(0);
			g <= rgbi(2) & rgbi(0) & rgbi(2) & rgbi(0) & rgbi(2) & rgbi(0) & rgbi(2) & rgbi(0);
			b <= rgbi(1) & rgbi(0) & rgbi(1) & rgbi(0) & rgbi(1) & rgbi(0) & rgbi(1) & rgbi(0);
		elsif rgbi(3 downto 1) = B"000" then 
			r <= X"00"; g <= X"00"; b <= X"00";
		elsif palette(2) = '0' and rgbi(0) = '0' then 
			case palette(1 downto 0) is
			when B"00" => r <= X"C4"; g <= X"C4"; b <= X"C4";
			when B"01" => r <= X"00"; g <= X"C4"; b <= X"00";
			when B"10" => r <= X"C4"; g <= X"9C"; b <= X"00";
			when B"11" => r <= X"C4"; g <= X"00"; b <= X"00";
			end case;
		else
			case palette(1 downto 0) is
			when B"00" => r <= X"FF"; g <= X"FF"; b <= X"FF";
			when B"01" => r <= X"00"; g <= X"FF"; b <= X"00";
			when B"10" => r <= X"FF"; g <= X"CC"; b <= X"00";
			when B"11" => r <= X"FF"; g <= X"00"; b <= X"00";
			end case;
		end if;
	end process;
end Behavioral;
