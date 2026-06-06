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
		palette: in unsigned(2 downto 0);
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
	process(index, invertV, palette)
	begin
		if invertV = '0' then
			case palette is
			when "000" =>
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
			when "001" =>
				case index is
				when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
				when X"1" => r <= X"f7"; g <= X"f7"; b <= X"f7";
				when X"2" => r <= X"8d"; g <= X"2f"; b <= X"34";
				when X"3" => r <= X"6a"; g <= X"d4"; b <= X"cd";
				when X"4" => r <= X"98"; g <= X"35"; b <= X"a4";
				when X"5" => r <= X"4c"; g <= X"b4"; b <= X"42";
				when X"6" => r <= X"2c"; g <= X"29"; b <= X"b1";
				when X"7" => r <= X"ef"; g <= X"ef"; b <= X"5d";
				when X"8" => r <= X"98"; g <= X"4e"; b <= X"20";
				when X"9" => r <= X"5b"; g <= X"38"; b <= X"00";
				when X"A" => r <= X"d1"; g <= X"67"; b <= X"6d";
				when X"B" => r <= X"4a"; g <= X"4a"; b <= X"4a";
				when X"C" => r <= X"7b"; g <= X"7b"; b <= X"7b";
				when X"D" => r <= X"9f"; g <= X"ef"; b <= X"93";
				when X"E" => r <= X"6d"; g <= X"6a"; b <= X"ef";
				when X"F" => r <= X"b2"; g <= X"b2"; b <= X"b2";
				end case;
			when "010" =>
				case index is
				when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
				when X"1" => r <= X"ff"; g <= X"ff"; b <= X"ff";
				when X"2" => r <= X"68"; g <= X"37"; b <= X"2b";
				when X"3" => r <= X"70"; g <= X"a4"; b <= X"b2";
				when X"4" => r <= X"6f"; g <= X"3d"; b <= X"86";
				when X"5" => r <= X"58"; g <= X"8d"; b <= X"43";
				when X"6" => r <= X"35"; g <= X"28"; b <= X"79";
				when X"7" => r <= X"b8"; g <= X"c7"; b <= X"6f";
				when X"8" => r <= X"6f"; g <= X"4f"; b <= X"25";
				when X"9" => r <= X"43"; g <= X"39"; b <= X"00";
				when X"A" => r <= X"9a"; g <= X"67"; b <= X"59";
				when X"B" => r <= X"44"; g <= X"44"; b <= X"44";
				when X"C" => r <= X"6c"; g <= X"6c"; b <= X"6c";
				when X"D" => r <= X"9a"; g <= X"d2"; b <= X"84";
				when X"E" => r <= X"6c"; g <= X"5e"; b <= X"b5";
				when X"F" => r <= X"95"; g <= X"95"; b <= X"95";
				end case;
			when "011" =>
				case index is
				when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
				when X"1" => r <= X"d5"; g <= X"d5"; b <= X"d5";
				when X"2" => r <= X"72"; g <= X"35"; b <= X"2c";
				when X"3" => r <= X"65"; g <= X"9f"; b <= X"a6";
				when X"4" => r <= X"73"; g <= X"3a"; b <= X"91";
				when X"5" => r <= X"56"; g <= X"8d"; b <= X"35";
				when X"6" => r <= X"2e"; g <= X"23"; b <= X"7d";
				when X"7" => r <= X"ae"; g <= X"b7"; b <= X"5e";
				when X"8" => r <= X"77"; g <= X"4f"; b <= X"1e";
				when X"9" => r <= X"4b"; g <= X"3c"; b <= X"00";
				when X"A" => r <= X"9c"; g <= X"63"; b <= X"5a";
				when X"B" => r <= X"47"; g <= X"47"; b <= X"47";
				when X"C" => r <= X"6b"; g <= X"6b"; b <= X"6b";
				when X"D" => r <= X"8f"; g <= X"c2"; b <= X"71";
				when X"E" => r <= X"67"; g <= X"5d"; b <= X"b6";
				when X"F" => r <= X"8f"; g <= X"8f"; b <= X"8f";
				end case;
			when "100" =>
				case index is
				when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
				when X"1" => r <= X"ff"; g <= X"ff"; b <= X"ff";
				when X"2" => r <= X"7b"; g <= X"1f"; b <= X"32";
				when X"3" => r <= X"86"; g <= X"df"; b <= X"cd";
				when X"4" => r <= X"b3"; g <= X"58"; b <= X"c2";
				when X"5" => r <= X"49"; g <= X"a6"; b <= X"4b";
				when X"6" => r <= X"38"; g <= X"29"; b <= X"ad";
				when X"7" => r <= X"c7"; g <= X"d5"; b <= X"55";
				when X"8" => r <= X"b1"; g <= X"74"; b <= X"3a";
				when X"9" => r <= X"53"; g <= X"3d"; b <= X"00";
				when X"A" => r <= X"be"; g <= X"62"; b <= X"75";
				when X"B" => r <= X"3d"; g <= X"3d"; b <= X"3d";
				when X"C" => r <= X"80"; g <= X"80"; b <= X"80";
				when X"D" => r <= X"8c"; g <= X"e8"; b <= X"8e";
				when X"E" => r <= X"7b"; g <= X"6c"; b <= X"f0";
				when X"F" => r <= X"c2"; g <= X"c2"; b <= X"c2";
				end case;
			when "101" =>
				case index is
				when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
				when X"1" => r <= X"ff"; g <= X"ff"; b <= X"ff";
				when X"2" => r <= X"8d"; g <= X"30"; b <= X"43";
				when X"3" => r <= X"66"; g <= X"c0"; b <= X"ad";
				when X"4" => r <= X"90"; g <= X"35"; b <= X"9f";
				when X"5" => r <= X"49"; g <= X"a6"; b <= X"4b";
				when X"6" => r <= X"38"; g <= X"29"; b <= X"ad";
				when X"7" => r <= X"c7"; g <= X"d5"; b <= X"55";
				when X"8" => r <= X"8e"; g <= X"51"; b <= X"17";
				when X"9" => r <= X"53"; g <= X"3d"; b <= X"00";
				when X"A" => r <= X"be"; g <= X"62"; b <= X"75";
				when X"B" => r <= X"4e"; g <= X"4e"; b <= X"4e";
				when X"C" => r <= X"76"; g <= X"76"; b <= X"76";
				when X"D" => r <= X"8c"; g <= X"e8"; b <= X"8e";
				when X"E" => r <= X"71"; g <= X"62"; b <= X"e6";
				when X"F" => r <= X"a3"; g <= X"a3"; b <= X"a3";
				end case;
			when "110" =>
				case index is
				when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
				when X"1" => r <= X"ff"; g <= X"ff"; b <= X"ff";
				when X"2" => r <= X"8b"; g <= X"34"; b <= X"36";
				when X"3" => r <= X"65"; g <= X"be"; b <= X"b9";
				when X"4" => r <= X"8d"; g <= X"36"; b <= X"a2";
				when X"5" => r <= X"4a"; g <= X"a6"; b <= X"46";
				when X"6" => r <= X"2d"; g <= X"30"; b <= X"a8";
				when X"7" => r <= X"d2"; g <= X"cf"; b <= X"57";
				when X"8" => r <= X"8e"; g <= X"50"; b <= X"1b";
				when X"9" => r <= X"54"; g <= X"3d"; b <= X"00";
				when X"A" => r <= X"bc"; g <= X"65"; b <= X"68";
				when X"B" => r <= X"4e"; g <= X"4e"; b <= X"4e";
				when X"C" => r <= X"76"; g <= X"76"; b <= X"76";
				when X"D" => r <= X"8d"; g <= X"e9"; b <= X"89";
				when X"E" => r <= X"66"; g <= X"69"; b <= X"e1";
				when X"F" => r <= X"a3"; g <= X"a3"; b <= X"a3";
				end case;
			when "111" =>
				case index is
				when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
				when X"1" => r <= X"ff"; g <= X"ff"; b <= X"ff";
				when X"2" => r <= X"8b"; g <= X"3e"; b <= X"42";
				when X"3" => r <= X"7c"; g <= X"d3"; b <= X"cd";
				when X"4" => r <= X"97"; g <= X"46"; b <= X"a0";
				when X"5" => r <= X"5c"; g <= X"b2"; b <= X"54";
				when X"6" => r <= X"3c"; g <= X"39"; b <= X"a9";
				when X"7" => r <= X"e3"; g <= X"e7"; b <= X"6e";
				when X"8" => r <= X"94"; g <= X"57"; b <= X"31";
				when X"9" => r <= X"59"; g <= X"3c"; b <= X"07";
				when X"A" => r <= X"cd"; g <= X"77"; b <= X"7c";
				when X"B" => r <= X"50"; g <= X"50"; b <= X"50";
				when X"C" => r <= X"83"; g <= X"83"; b <= X"83";
				when X"D" => r <= X"af"; g <= X"f8"; b <= X"a6";
				when X"E" => r <= X"7f"; g <= X"7d"; b <= X"f4";
				when X"F" => r <= X"ba"; g <= X"ba"; b <= X"ba";
				end case;
			end case;
		else
			case palette is
			when "000" =>
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
			when "001" =>
				case index is
				when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
				when X"1" => r <= X"F7"; g <= X"F7"; b <= X"F7";
				when X"2" => r <= X"0A"; g <= X"72"; b <= X"34";
				when X"3" => r <= X"FD"; g <= X"89"; b <= X"CD";
				when X"4" => r <= X"27"; g <= X"6F"; b <= X"A4";
				when X"5" => r <= X"C4"; g <= X"77"; b <= X"42";
				when X"6" => r <= X"47"; g <= X"1B"; b <= X"B1";
				when X"7" => r <= X"CE"; g <= X"FF"; b <= X"5D";
				when X"8" => r <= X"26"; g <= X"88"; b <= X"20";
				when X"9" => r <= X"1D"; g <= X"57"; b <= X"00";
				when X"A" => r <= X"3E"; g <= X"B2"; b <= X"6D";
				when X"B" => r <= X"4A"; g <= X"4A"; b <= X"4A";
				when X"C" => r <= X"7B"; g <= X"7B"; b <= X"7B";
				when X"D" => r <= X"FA"; g <= X"C1"; b <= X"93";
				when X"E" => r <= X"87"; g <= X"5D"; b <= X"EF";
				when X"F" => r <= X"B2"; g <= X"B2"; b <= X"B2";
				end case;
			when "010" =>
				case index is
				when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
				when X"1" => r <= X"FF"; g <= X"FF"; b <= X"FF";
				when X"2" => r <= X"21"; g <= X"5B"; b <= X"2B";
				when X"3" => r <= X"BC"; g <= X"7D"; b <= X"B2";
				when X"4" => r <= X"3A"; g <= X"58"; b <= X"86";
				when X"5" => r <= X"91"; g <= X"70"; b <= X"43";
				when X"6" => r <= X"35"; g <= X"28"; b <= X"79";
				when X"7" => r <= X"B9"; g <= X"C7"; b <= X"6F";
				when X"8" => r <= X"39"; g <= X"6B"; b <= X"25";
				when X"9" => r <= X"28"; g <= X"47"; b <= X"00";
				when X"A" => r <= X"4F"; g <= X"8D"; b <= X"59";
				when X"B" => r <= X"44"; g <= X"44"; b <= X"44";
				when X"C" => r <= X"6C"; g <= X"6C"; b <= X"6C";
				when X"D" => r <= X"D7"; g <= X"B3"; b <= X"84";
				when X"E" => r <= X"6C"; g <= X"5E"; b <= X"B5";
				when X"F" => r <= X"95"; g <= X"95"; b <= X"95";
				end case;
			when "011" =>
				case index is
				when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
				when X"1" => r <= X"D5"; g <= X"D5"; b <= X"D5";
				when X"2" => r <= X"1A"; g <= X"62"; b <= X"2C";
				when X"3" => r <= X"B8"; g <= X"75"; b <= X"A6";
				when X"4" => r <= X"37"; g <= X"59"; b <= X"91";
				when X"5" => r <= X"8F"; g <= X"70"; b <= X"35";
				when X"6" => r <= X"33"; g <= X"20"; b <= X"7D";
				when X"7" => r <= X"A6"; g <= X"BB"; b <= X"5E";
				when X"8" => r <= X"34"; g <= X"71"; b <= X"1E";
				when X"9" => r <= X"28"; g <= X"4E"; b <= X"00";
				when X"A" => r <= X"4A"; g <= X"8D"; b <= X"5A";
				when X"B" => r <= X"47"; g <= X"47"; b <= X"47";
				when X"C" => r <= X"6B"; g <= X"6B"; b <= X"6B";
				when X"D" => r <= X"C4"; g <= X"A7"; b <= X"71";
				when X"E" => r <= X"6D"; g <= X"5A"; b <= X"B6";
				when X"F" => r <= X"8F"; g <= X"8F"; b <= X"8F";
				end case;
			when "100" =>
				case index is
				when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
				when X"1" => r <= X"FF"; g <= X"FF"; b <= X"FF";
				when X"2" => r <= X"00"; g <= X"5E"; b <= X"32";
				when X"3" => r <= X"FF"; g <= X"A2"; b <= X"CD";
				when X"4" => r <= X"4C"; g <= X"8D"; b <= X"C2";
				when X"5" => r <= X"B7"; g <= X"6E"; b <= X"4B";
				when X"6" => r <= X"41"; g <= X"24"; b <= X"AD";
				when X"7" => r <= X"BD"; g <= X"DA"; b <= X"55";
				when X"8" => r <= X"4E"; g <= X"A6"; b <= X"3A";
				when X"9" => r <= X"26"; g <= X"54"; b <= X"00";
				when X"A" => r <= X"41"; g <= X"A1"; b <= X"75";
				when X"B" => r <= X"3D"; g <= X"3D"; b <= X"3D";
				when X"C" => r <= X"80"; g <= X"80"; b <= X"80";
				when X"D" => r <= X"F8"; g <= X"B1"; b <= X"8E";
				when X"E" => r <= X"84"; g <= X"67"; b <= X"F0";
				when X"F" => r <= X"C2"; g <= X"C2"; b <= X"C2";
				end case;
			when "101" =>
				case index is
				when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
				when X"1" => r <= X"FF"; g <= X"FF"; b <= X"FF";
				when X"2" => r <= X"0F"; g <= X"70"; b <= X"43";
				when X"3" => r <= X"E0"; g <= X"82"; b <= X"AD";
				when X"4" => r <= X"29"; g <= X"6A"; b <= X"9F";
				when X"5" => r <= X"B7"; g <= X"6E"; b <= X"4B";
				when X"6" => r <= X"41"; g <= X"24"; b <= X"AD";
				when X"7" => r <= X"BD"; g <= X"DA"; b <= X"55";
				when X"8" => r <= X"2B"; g <= X"83"; b <= X"17";
				when X"9" => r <= X"26"; g <= X"54"; b <= X"00";
				when X"A" => r <= X"41"; g <= X"A1"; b <= X"75";
				when X"B" => r <= X"4E"; g <= X"4E"; b <= X"4E";
				when X"C" => r <= X"76"; g <= X"76"; b <= X"76";
				when X"D" => r <= X"F8"; g <= X"B1"; b <= X"8E";
				when X"E" => r <= X"7A"; g <= X"5D"; b <= X"E6";
				when X"F" => r <= X"A3"; g <= X"A3"; b <= X"A3";
				end case;
			when "110" =>
				case index is
				when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
				when X"1" => r <= X"FF"; g <= X"FF"; b <= X"FF";
				when X"2" => r <= X"11"; g <= X"72"; b <= X"36";
				when X"3" => r <= X"E1"; g <= X"7F"; b <= X"B9";
				when X"4" => r <= X"2C"; g <= X"68"; b <= X"A2";
				when X"5" => r <= X"B5"; g <= X"6F"; b <= X"46";
				when X"6" => r <= X"4D"; g <= X"20"; b <= X"A8";
				when X"7" => r <= X"B2"; g <= X"DF"; b <= X"57";
				when X"8" => r <= X"2B"; g <= X"82"; b <= X"1B";
				when X"9" => r <= X"26"; g <= X"55"; b <= X"00";
				when X"A" => r <= X"43"; g <= X"A3"; b <= X"68";
				when X"B" => r <= X"4E"; g <= X"4E"; b <= X"4E";
				when X"C" => r <= X"76"; g <= X"76"; b <= X"76";
				when X"D" => r <= X"F8"; g <= X"B2"; b <= X"89";
				when X"E" => r <= X"86"; g <= X"59"; b <= X"E1";
				when X"F" => r <= X"A3"; g <= X"A3"; b <= X"A3";
				end case;
			when "111" =>
				case index is
				when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
				when X"1" => r <= X"FF"; g <= X"FF"; b <= X"FF";
				when X"2" => r <= X"20"; g <= X"75"; b <= X"42";
				when X"3" => r <= X"F5"; g <= X"96"; b <= X"CD";
				when X"4" => r <= X"3A"; g <= X"75"; b <= X"A0";
				when X"5" => r <= X"BF"; g <= X"80"; b <= X"54";
				when X"6" => r <= X"51"; g <= X"2E"; b <= X"A9";
				when X"7" => r <= X"CD"; g <= X"F2"; b <= X"6E";
				when X"8" => r <= X"36"; g <= X"87"; b <= X"31";
				when X"9" => r <= X"24"; g <= X"57"; b <= X"07";
				when X"A" => r <= X"56"; g <= X"B4"; b <= X"7C";
				when X"B" => r <= X"50"; g <= X"50"; b <= X"50";
				when X"C" => r <= X"83"; g <= X"83"; b <= X"83";
				when X"D" => r <= X"FF"; g <= X"CD"; b <= X"A6";
				when X"E" => r <= X"97"; g <= X"71"; b <= X"F4";
				when X"F" => r <= X"BA"; g <= X"BA"; b <= X"BA";
				end case;
			end case;
		end if;
	end process;
end Behavioral;
