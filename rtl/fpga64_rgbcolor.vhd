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
		shift: in std_logic;
		r: out unsigned(7 downto 0);
		g: out unsigned(7 downto 0);
		b: out unsigned(7 downto 0)
	);
end fpga64_rgbcolor;

-- -----------------------------------------------------------------------

architecture Behavioral of fpga64_rgbcolor is
begin
	process(index)
	variable ro: unsigned(7 downto 0);
	variable go: unsigned(7 downto 0);
	variable bo: unsigned(7 downto 0);
	begin
		case index is
		when X"0" => ro := X"00"; go := X"00"; bo := X"00";
		when X"1" => ro := X"FF"; go := X"FF"; bo := X"FF";
		when X"2" => ro := X"81"; go := X"33"; bo := X"38";
		when X"3" => ro := X"75"; go := X"ce"; bo := X"c8";
		when X"4" => ro := X"8e"; go := X"3c"; bo := X"97";
		when X"5" => ro := X"56"; go := X"ac"; bo := X"4d";
		when X"6" => ro := X"2e"; go := X"2c"; bo := X"9b";
		when X"7" => ro := X"ed"; go := X"f1"; bo := X"71";
		when X"8" => ro := X"8e"; go := X"50"; bo := X"29";
		when X"9" => ro := X"55"; go := X"38"; bo := X"00";
		when X"A" => ro := X"c4"; go := X"6c"; bo := X"71";
		when X"B" => ro := X"4a"; go := X"4a"; bo := X"4a";
		when X"C" => ro := X"7b"; go := X"7b"; bo := X"7b";
		when X"D" => ro := X"a9"; go := X"ff"; bo := X"9f";
		when X"E" => ro := X"70"; go := X"6d"; bo := X"eb";
		when X"F" => ro := X"b2"; go := X"b2"; bo := X"b2";
		end case;
		if shift = '0' then
			r <= ro; g <= go; b <= bo;
		else
			r <= go; g <= ro; b <= bo;
		end if;
	end process;
end Behavioral;
