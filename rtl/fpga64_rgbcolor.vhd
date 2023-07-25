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
-- C64 palette index to 24 bit RGB color
-- 
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

-- -----------------------------------------------------------------------

entity fpga64_rgbcolor is
	port (
		index: in unsigned(3 downto 0);
		invertV: in std_logic;
		r: out unsigned(7 downto 0);
		g: out unsigned(7 downto 0);
		b: out unsigned(7 downto 0)
	);
end fpga64_rgbcolor;

-- -----------------------------------------------------------------------

architecture Behavioral of fpga64_rgbcolor is
begin
	process(index, invertV)
	begin
		if invertV = '0' then
			case index is
			when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
			when X"1" => r <= X"FF"; g <= X"FF"; b <= X"FF";
			when X"2" => r <= X"81"; g <= X"33"; b <= X"38";
			when X"3" => r <= X"75"; g <= X"ce"; b <= X"c8";
			when X"4" => r <= X"8e"; g <= X"3c"; b <= X"97";
			when X"5" => r <= X"56"; g <= X"ac"; b <= X"4d";
			when X"6" => r <= X"2e"; g <= X"2c"; b <= X"9b";
			when X"7" => r <= X"ed"; g <= X"f1"; b <= X"71";
			when X"8" => r <= X"8e"; g <= X"50"; b <= X"29";
			when X"9" => r <= X"55"; g <= X"38"; b <= X"00";
			when X"A" => r <= X"c4"; g <= X"6c"; b <= X"71";
			when X"B" => r <= X"4a"; g <= X"4a"; b <= X"4a";
			when X"C" => r <= X"7b"; g <= X"7b"; b <= X"7b";
			when X"D" => r <= X"a9"; g <= X"ff"; b <= X"9f";
			when X"E" => r <= X"70"; g <= X"6d"; b <= X"eb";
			when X"F" => r <= X"b2"; g <= X"b2"; b <= X"b2";
			end case;
		else
			case index is
			when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
			when X"1" => r <= X"FF"; g <= X"FF"; b <= X"FF";
			when X"2" => r <= X"15"; g <= X"6A"; b <= X"38";
			when X"3" => r <= X"F0"; g <= X"8F"; b <= X"C8";
			when X"4" => r <= X"30"; g <= X"6C"; b <= X"97";
			when X"5" => r <= X"B9"; g <= X"7A"; b <= X"4D";
			when X"6" => r <= X"45"; g <= X"21"; b <= X"9B";
			when X"7" => r <= X"D5"; g <= X"FD"; b <= X"71";
			when X"8" => r <= X"2E"; g <= X"81"; b <= X"29";
			when X"9" => r <= X"20"; g <= X"53"; b <= X"00";
			when X"A" => r <= X"4A"; g <= X"AA"; b <= X"71";
			when X"B" => r <= X"4A"; g <= X"4A"; b <= X"4A";
			when X"C" => r <= X"7B"; g <= X"7B"; b <= X"7B";
			when X"D" => r <= X"FF"; g <= X"CD"; b <= X"9F";
			when X"E" => r <= X"89"; g <= X"61"; b <= X"EB";
			when X"F" => r <= X"B2"; g <= X"B2"; b <= X"B2";
			end case;
		end if;
	end process;
end Behavioral;
