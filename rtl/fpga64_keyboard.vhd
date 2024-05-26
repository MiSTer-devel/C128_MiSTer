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
-- 'Joystick emulation on keypad' additions by
-- Mark McDougall (msmcdoug@iinet.net.au)
-- -----------------------------------------------------------------------
-- C128 keyboard extensions by Erik Scheffers
-- -----------------------------------------------------------------------
--
-- VIC20/C64 Keyboard matrix
--
-- Hardware huh?
--	In original machine if a key is pressed a contact is made.
--	Bidirectional reading is possible on real hardware, which is difficult
--	to emulate. (set backwardsReadingEnabled to '1' if you want this enabled).
--	Then we have the joysticks, one of which is normally connected
--	to a OUTPUT pin.
--
-- Emulation:
--	All pins are high except when one is driven low and there is a
--	connection. This is consistent with joysticks that force a line
--	low too. CIA will put '1's when set to input to help this emulation.
--
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.ALL;

entity fpga64_keyboard is
	port (
		clk         : in std_logic;
		reset       : in std_logic;
		pure64      : in std_logic;
		c128_n      : in std_logic;

		go64        : in std_logic;
		ps2_key     : in std_logic_vector(10 downto 0);
		joyA        : in unsigned(6 downto 0);
		joyB        : in unsigned(6 downto 0);

		alt_crsr    : in std_logic;  -- when set, uses top-row cursor keys as default and FN switches to the original cursor keys
		shift_mod   : in std_logic_vector(1 downto 0);
		azerty      : in std_logic;  -- when set, modify layout for AZERTY keyboard in DIN mode

		pai         : in unsigned(7 downto 0);
		pbi         : in unsigned(7 downto 0);
		pao         : out unsigned(7 downto 0);
		pbo         : out unsigned(7 downto 0);
		ki          : in unsigned(2 downto 0);

		restore_key : out std_logic;
		mod_key     : out std_logic;
		tape_play   : out std_logic;

		sftlk_sense : out std_logic;
		cpslk_sense : out std_logic;
		d4080_sense : out std_logic;
		noscr_sense : out std_logic;

		-- Config
		-- backwardsReadingEnabled = 1 allows reversal of PIA registers to still work.
		-- not needed for kernel/normal operation only for some specific programs.
		-- set to 0 to save some hardware.
		backwardsReadingEnabled : in std_logic
	);
end fpga64_keyboard;

architecture rtl of fpga64_keyboard is
	constant C_NOSCROLL_DELAY : integer := 6_000_000;  -- 32_000_000 is 1 second

	signal pressed: std_logic := '0';

	signal key_del: std_logic := '0';
	signal key_return: std_logic := '0';
	signal key_left: std_logic := '0';
	signal key_right: std_logic := '0';
	signal key_F1: std_logic := '0';
	signal key_F2: std_logic := '0';
	signal key_F3: std_logic := '0';
	signal key_F4: std_logic := '0';
	signal key_F5: std_logic := '0';
	signal key_F6: std_logic := '0';
	signal key_F7: std_logic := '0';
	signal key_F8: std_logic := '0';
	signal key_up: std_logic := '0';
	signal key_down: std_logic := '0';

	signal key_3: std_logic := '0';
	signal key_W: std_logic := '0';
	signal key_A: std_logic := '0';
	signal key_4: std_logic := '0';
	signal key_Z: std_logic := '0';
	signal key_S: std_logic := '0';
	signal key_E: std_logic := '0';
	signal key_shiftl: std_logic := '0';

	signal key_5: std_logic := '0';
	signal key_R: std_logic := '0';
	signal key_D: std_logic := '0';
	signal key_6: std_logic := '0';
	signal key_C: std_logic := '0';
	signal key_F: std_logic := '0';
	signal key_T: std_logic := '0';
	signal key_X: std_logic := '0';

	signal key_7: std_logic := '0';
	signal key_Y: std_logic := '0';
	signal key_G: std_logic := '0';
	signal key_8: std_logic := '0';
	signal key_B: std_logic := '0';
	signal key_H: std_logic := '0';
	signal key_U: std_logic := '0';
	signal key_V: std_logic := '0';

	signal key_9: std_logic := '0';
	signal key_I: std_logic := '0';
	signal key_J: std_logic := '0';
	signal key_0: std_logic := '0';
	signal key_M: std_logic := '0';
	signal key_K: std_logic := '0';
	signal key_O: std_logic := '0';
	signal key_N: std_logic := '0';

	signal key_plus: std_logic := '0';
	signal key_P: std_logic := '0';
	signal key_L: std_logic := '0';
	signal key_minus: std_logic := '0';
	signal key_dot: std_logic := '0';
	signal key_colon: std_logic := '0';
	signal key_at: std_logic := '0';
	signal key_comma: std_logic := '0';

	signal key_pound: std_logic := '0';
	signal key_star: std_logic := '0';
	signal key_semicolon: std_logic := '0';
	signal key_home: std_logic := '0';
	signal key_shiftr: std_logic := '0';
	signal key_equal: std_logic := '0';
	signal key_arrowup: std_logic := '0';
	signal key_slash: std_logic := '0';

	signal key_1: std_logic := '0';
	signal key_arrowleft: std_logic := '0';
	signal key_ctrl: std_logic := '0';
	signal key_2: std_logic := '0';
	signal key_space: std_logic := '0';
	signal key_commodore: std_logic := '0';
	signal key_Q: std_logic := '0';
	signal key_runstop: std_logic := '0';

	signal key_fn : std_logic;
	signal key_shift: std_logic := '0';
	signal key_inst: std_logic := '0';

	signal key_tab: std_logic := '0';
	signal key_alt: std_logic := '0';
	signal key_capslock: std_logic := '0';

	signal key_num0: std_logic := '0';
	signal key_num1: std_logic := '0';
	signal key_num2: std_logic := '0';
	signal key_num3: std_logic := '0';
	signal key_num4: std_logic := '0';
	signal key_num5: std_logic := '0';
	signal key_num6: std_logic := '0';
	signal key_num7: std_logic := '0';
	signal key_num8: std_logic := '0';
	signal key_num9: std_logic := '0';
	signal key_numplus: std_logic := '0';
	signal key_numminus: std_logic := '0';
	signal key_d4080: std_logic := '0';
	signal key_esc: std_logic := '0';
	signal key_numdot: std_logic := '0';
	signal key_enter: std_logic := '0';
	signal key_noscroll: std_logic := '0';
	signal key_help: std_logic := '0';
	signal key_linefd: std_logic := '0';

	-- for joystick emulation on PS2
	signal old_state : std_logic;

	signal delay_cnt : integer range 0 to 300000;
	signal delay_end : std_logic;
	signal ps2_stb   : std_logic;
	signal key_8s    : std_logic := '0';

	-- switch states
	signal noscroll_delay : integer range 0 to C_NOSCROLL_DELAY;
	signal noscroll_lock : std_logic := '0';

	signal shift_lock : std_logic;
	signal shift_lock_0 : std_logic := '0';
	signal shift_lock_state : std_logic := '0';
	signal capslock : std_logic;
	signal capslock_0 : std_logic := '0';
	signal capslock_state : std_logic := '1';
	signal disp4080 : std_logic;
	signal disp4080_0 : std_logic := '0';
	signal disp4080_state : std_logic := '1';

	signal last_key : std_logic_vector(10 downto 0);

	signal key_fn_crsr : std_logic;
	signal shift_num_mod : std_logic;

begin
	delay_end <= '1' when delay_cnt = 0 else '0';
	shift_num_mod <= c128_n or capslock_state or not azerty;

	capslock <= key_capslock or (key_F4 and key_fn);
	capslock_toggle: process(clk)
	begin
		if rising_edge(clk) then
			if pure64 = '1' then
				capslock_0 <= '0';
				capslock_state <= '1';
			else
				capslock_0 <= capslock;
				if (capslock = '1' and capslock_0 = '0') then
					capslock_state <= not capslock_state;
				end if;
			end if;
		end if;
	end process;

	disp4080 <= key_d4080 or (key_F7 and key_fn);
	disp4080_toggle: process(clk)
	begin
		if rising_edge(clk) then
			if pure64 = '1' then
				disp4080_0 <= '0';
				disp4080_state <= '1';
			else
				disp4080_0 <= disp4080;
				if (disp4080 = '1' and disp4080_0 = '0') then
					disp4080_state <= not disp4080_state;
				end if;
			end if;
		end if;
	end process;

	shift_lock <= (key_fn and (key_shiftl or key_shiftr)) or (pure64 and key_capslock);
	shift_lock_toggle: process(clk)
	begin
		if rising_edge(clk) then
			shift_lock_0 <= shift_lock;
			if (shift_lock = '1' and shift_lock_0 = '0') then
				shift_lock_state <= not shift_lock_state;
			end if;
		end if;
	end process;

	key_shift <= key_shiftl or key_shiftr or shift_lock_state;
	key_fn_crsr <= key_fn xor alt_crsr;

	pressed <= ps2_key(9);
	matrix: process(clk)
	begin
		if rising_edge(clk) then
			last_key <= ps2_key;
			ps2_stb <= ps2_key(10);

			if delay_cnt /= 0 then
				delay_cnt <= delay_cnt - 1;
			end if;

			if reset = '1' then
				noscroll_lock <= '0';
				noscroll_delay <= 0;
			elsif noscroll_delay /= 0 then
				noscroll_delay <= noscroll_delay - 1;
			else
				if key_noscroll = '1' then
					key_noscroll <= '0';
				end if;
				if noscroll_lock = '1' and pressed = '1' and ps2_key /= last_key then
					noscroll_lock <= '0';
				end if;
			end if;

			-- reading A, scan pattern on B
			pao(0) <= pai(0) and joyB(0) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not (key_del or key_inst)) and
				(pbi(1) or not (key_return and not key_fn)) and
				(pbi(2) or not ((key_left or key_right) and not key_fn_crsr)) and
				(pbi(3) or not ((key_F7 or key_F8) and not key_fn)) and
				(pbi(4) or not ((key_F1 or key_F2) and not key_fn)) and
				(pbi(5) or not ((key_F3 or key_F4) and not key_fn)) and
				(pbi(6) or not ((key_F5 or key_F6) and not key_fn)) and
				(pbi(7) or not ((key_up or key_down) and not key_fn_crsr))));
			pao(1) <= pai(1) and joyB(1) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not (key_3 and not key_fn)) and
				(pbi(1) or not key_W) and
				(pbi(2) or not key_A) and
				(pbi(3) or not key_4) and
				(pbi(4) or not key_Z) and
				(pbi(5) or not key_S) and
				(pbi(6) or not key_E) and
				(pbi(7) or not (
					((key_inst
						or ((key_left or key_up) and not key_fn_crsr)
						or ((key_F2 or key_F4 or key_F6 or key_F8) and not key_fn)
					) and shift_mod(1))
					or ((key_shiftl or shift_lock_state) and not key_8s)
				))));
			pao(2) <= pai(2) and joyB(2) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not (key_5 and not key_fn)) and
				(pbi(1) or not key_R) and
				(pbi(2) or not key_D) and
				(pbi(3) or not key_6) and
				(pbi(4) or not key_C) and
				(pbi(5) or not key_F) and
				(pbi(6) or not key_T) and
				(pbi(7) or not key_X)));
			pao(3) <= pai(3) and joyB(3) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not (key_7 and not key_fn)) and
				(pbi(1) or not key_Y) and
				(pbi(2) or not key_G) and
				(pbi(3) or not (key_8 and not key_fn)) and
				(pbi(4) or not key_B) and
				(pbi(5) or not key_H) and
				(pbi(6) or not key_U) and
				(pbi(7) or not key_V)));
			pao(4) <= pai(4) and joyB(4) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not (key_9 and not key_fn)) and
				(pbi(1) or not key_I) and
				(pbi(2) or not key_J) and
				(pbi(3) or not (key_0 and not key_fn)) and
				(pbi(4) or not key_M) and
				(pbi(5) or not key_K) and
				(pbi(6) or not key_O) and
				(pbi(7) or not key_N)));
			pao(5) <= pai(5) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not (key_plus and not key_fn)) and
				(pbi(1) or not key_P) and
				(pbi(2) or not key_L) and
				(pbi(3) or not (key_minus and not key_fn)) and
				(pbi(4) or not (key_dot and not key_fn)) and
				(pbi(5) or not key_colon) and
				(pbi(6) or not key_at) and
				(pbi(7) or not key_comma)));
			pao(6) <= pai(6) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_pound) and
				(pbi(1) or not (key_star or (key_8s and delay_end))) and
				(pbi(2) or not key_semicolon) and
				(pbi(3) or not key_home) and
				(pbi(4) or not (
					((key_inst
						or ((key_left or key_up) and not key_fn_crsr)
						or ((key_F2 or key_F4 or key_F6 or key_F8) and not key_fn)
					) and shift_mod(0))
					or (key_shiftr and not key_8s)
				)) and
				(pbi(5) or not key_equal) and
				(pbi(6) or not key_arrowup) and
				(pbi(7) or not key_slash)));
			pao(7) <= pai(7) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not (key_1 and not key_fn)) and
				(pbi(1) or not key_arrowleft) and
				(pbi(2) or not (key_ctrl or not joyA(6) or not joyB(6))) and
				(pbi(3) or not (key_2 and not key_fn)) and
				(pbi(4) or not ((key_space and not key_fn) or not joyA(5) or not joyB(5))) and
				(pbi(5) or not (key_commodore or go64)) and
				(pbi(6) or not key_Q) and
				(pbi(7) or not key_runstop)));

			-- reading B, scan pattern on A
			pbo(0) <= pbi(0) and joyA(0) and
				(pai(0) or not (key_del or key_inst)) and
				(pai(1) or not (key_3 and not key_fn)) and
				(pai(2) or not (key_5 and not key_fn)) and
				(pai(3) or not (key_7 and not key_fn)) and
				(pai(4) or not (key_9 and not key_fn)) and
				(pai(5) or not (key_plus and not key_fn)) and
				(pai(6) or not key_pound) and
				(pai(7) or not (key_1 and not key_fn)) and
				(ki(0) or not (key_help or (key_F5 and key_fn))) and
				(ki(1) or not (key_esc or (key_F1 and key_fn))) and
				(ki(2) or not (key_alt or (key_F2 and key_fn)));
			pbo(1) <= pbi(1) and joyA(1) and
				(pai(0) or not (key_return and not key_fn)) and
				(pai(1) or not key_W) and
				(pai(2) or not key_R) and
				(pai(3) or not key_Y) and
				(pai(4) or not key_I) and
				(pai(5) or not key_P) and
				(pai(6) or not (key_star or (key_8s and delay_end))) and
				(pai(7) or not key_arrowleft) and
				(ki(0) or not (key_num8 or (key_8 and key_fn))) and
				(ki(1) or not (key_numplus or (key_plus and key_fn))) and
				(ki(2) or not (key_num0 or (key_0 and key_fn)));
			pbo(2) <= pbi(2) and joyA(2) and
				(pai(0) or not ((key_left or key_right) and not key_fn_crsr)) and
				(pai(1) or not key_A) and
				(pai(2) or not key_D) and
				(pai(3) or not key_G) and
				(pai(4) or not key_J) and
				(pai(5) or not key_L) and
				(pai(6) or not key_semicolon) and
				(pai(7) or not (key_ctrl or not joyA(6) or not joyB(6))) and
				(ki(0) or not (key_num5 or (key_5 and key_fn))) and
				(ki(1) or not (key_numminus or (key_minus and key_fn))) and
				(ki(2) or not (key_numdot or (key_dot and key_fn)));
			pbo(3) <= pbi(3) and joyA(3) and
				(pai(0) or not ((key_F7 or key_F8) and not key_fn)) and
				(pai(1) or not (key_4 and not key_fn)) and
				(pai(2) or not (key_6 and not key_fn)) and
				(pai(3) or not (key_8 and not key_fn)) and
				(pai(4) or not (key_0 and not key_fn)) and
				(pai(5) or not (key_minus and not key_fn)) and
				(pai(6) or not key_home) and
				(pai(7) or not (key_2 and not key_fn)) and
				(ki(0) or not (key_tab or (key_F3 and key_fn))) and
				(ki(1) or not (key_linefd or (key_F6 and key_fn))) and
				(ki(2) or not (key_up and key_fn_crsr));
			pbo(4) <= pbi(4) and joyA(4) and
				(pai(0) or not ((key_F1 or key_F2) and not key_fn)) and
				(pai(1) or not key_Z) and
				(pai(2) or not key_C) and
				(pai(3) or not key_B) and
				(pai(4) or not key_M) and
				(pai(5) or not (key_dot and not key_fn)) and
				(pai(6) or not (
					((
						key_inst
						or ((key_left or key_up) and not key_fn_crsr)
						or ((key_F2 or key_F4 or key_F6 or key_F8) and not key_fn)
					) and shift_mod(0))
					or (key_shiftr and not key_8s)
				)) and
				(pai(7) or not ((key_space and not key_fn) or not joyA(5) or not joyB(5))) and
				(ki(0) or not (key_num2 or (key_2 and key_fn))) and
				(ki(1) or not (key_enter or (key_return and key_fn))) and
				(ki(2) or not (key_down and key_fn_crsr));
			pbo(5) <= pbi(5) and
				(pai(0) or not ((key_F3 or key_F4) and not key_fn)) and
				(pai(1) or not key_S) and
				(pai(2) or not key_F) and
				(pai(3) or not key_H) and
				(pai(4) or not key_K) and
				(pai(5) or not key_colon) and
				(pai(6) or not key_equal) and
				(pai(7) or not (key_commodore or go64)) and
				(ki(0) or not (key_num4 or (key_4 and key_fn))) and
				(ki(1) or not (key_num6 or (key_6 and key_fn))) and
				(ki(2) or not (key_left and key_fn_crsr));
			pbo(6) <= pbi(6) and
				(pai(0) or not ((key_F5 or key_F6) and not key_fn)) and
				(pai(1) or not key_E) and
				(pai(2) or not key_T) and
				(pai(3) or not key_U) and
				(pai(4) or not key_O) and
				(pai(5) or not key_at) and
				(pai(6) or not key_arrowup) and
				(pai(7) or not key_Q) and
				(ki(0) or not (key_num7 or (key_7 and key_fn))) and
				(ki(1) or not (key_num9 or (key_9 and key_fn))) and
				(ki(2) or not (key_right and key_fn_crsr));
			pbo(7) <= pbi(7) and
				(pai(0) or not ((key_up or key_down) and not key_fn_crsr)) and
				(pai(1) or not (
					((
						key_inst
						or ((key_left or key_up) and not key_fn_crsr)
						or ((key_F2 or key_F4 or key_F6 or key_F8) and not key_fn)
					) and shift_mod(1))
					or ((key_shiftl or shift_lock_state) and not key_8s)
				)) and
				(pai(2) or not key_X) and
				(pai(3) or not key_V) and
				(pai(4) or not key_N) and
				(pai(5) or not key_comma) and
				(pai(6) or not key_slash) and
				(pai(7) or not key_runstop) and
				(ki(0) or not (key_num1 or (key_1 and key_fn))) and
				(ki(1) or not (key_num3 or (key_3 and key_fn))) and
				(ki(2) or not (key_noscroll or noscroll_lock or (key_F8 and key_fn)));

			if ps2_key(10) /= ps2_stb then
				case ps2_key(8 downto 0) is
					when "0" & X"01" => key_arrowup <= pressed; -- F9
					when "0" & X"03" => key_F5 <= pressed;
					when "0" & X"04" => key_F3 <= pressed;
					when "0" & X"05" => key_F1 <= pressed;
					when "0" & X"06" => key_F2 <= pressed;
					when "0" & X"09" => key_equal <= pressed; -- F10
					when "0" & X"0A" => key_F8 <= pressed;
					when "0" & X"0B" => key_F6 <= pressed;
					when "0" & X"0C" => key_F4 <= pressed;
					when "0" & X"0D" => if pure64 = '0' then key_tab <= pressed; else key_commodore <= pressed; end if;
					when "0" & X"0E" => key_arrowleft <= pressed;
					when "0" & X"11" => if pure64 = '0' then key_alt <= pressed; end if; -- Alt (left)
					when "0" & X"12" => key_shiftl <= pressed;
					when "0" & X"14" => key_ctrl <= pressed; -- Ctrl (left)
					when "0" & X"15" => key_Q <= pressed;
					when "0" & X"16" => key_1 <= pressed;
					when "0" & X"1A" => key_Z <= pressed;
					when "0" & X"1B" => key_S <= pressed;
					when "0" & X"1C" => key_A <= pressed;
					when "0" & X"1D" => key_W <= pressed;
					when "0" & X"1E" => key_2 <= pressed;
					when "0" & X"21" => key_C <= pressed;
					when "0" & X"22" => key_X <= pressed;
					when "0" & X"23" => key_D <= pressed;
					when "0" & X"24" => key_E <= pressed;
					when "0" & X"25" => key_4 <= pressed;
					when "0" & X"26" => key_3 <= pressed;
					when "0" & X"29" => key_space <= pressed;
					when "0" & X"2A" => key_V <= pressed;
					when "0" & X"2B" => key_F <= pressed;
					when "0" & X"2C" => key_T <= pressed;
					when "0" & X"2D" => key_R <= pressed;
					when "0" & X"2E" => key_5 <= pressed;
					when "0" & X"31" => key_N <= pressed;
					when "0" & X"32" => key_B <= pressed;
					when "0" & X"33" => key_H <= pressed;
					when "0" & X"34" => key_G <= pressed;
					when "0" & X"35" => key_Y <= pressed;
					when "0" & X"36" => key_7 <= pressed and      key_shift and shift_num_mod;
											  key_6 <= pressed and not (key_shift and shift_num_mod);
					when "0" & X"3A" => key_M <= pressed;
					when "0" & X"3B" => key_J <= pressed;
					when "0" & X"3C" => key_U <= pressed;
					when "0" & X"3D" => key_6 <= pressed and      key_shift and shift_num_mod;
									        key_7 <= pressed and not (key_shift and shift_num_mod);
					when "0" & X"3E" => key_8s <= pressed and     key_shift and shift_num_mod;
									        key_8 <= pressed and not (key_shift and shift_num_mod);
									        delay_cnt <= 300000;
					when "0" & X"41" => key_comma <= pressed;
					when "0" & X"42" => key_K <= pressed;
					when "0" & X"43" => key_I <= pressed;
					when "0" & X"44" => key_O <= pressed;
					when "0" & X"45" => key_9 <= pressed and      key_shift and shift_num_mod;
											  key_0 <= pressed and not (key_shift and shift_num_mod);
					when "0" & X"46" => key_8 <= pressed and      key_shift and shift_num_mod;
									  		  key_9 <= pressed and not (key_shift and shift_num_mod);
					when "0" & X"49" => key_dot <= pressed;
					when "0" & X"4A" => key_slash <= pressed;
					when "0" & X"4B" => key_L <= pressed;
					when "0" & X"4C" => key_colon <= pressed;
					when "0" & X"4D" => key_P <= pressed;
					when "0" & X"4E" => key_minus <= pressed;
					when "0" & X"52" => key_semicolon <= pressed;
					when "0" & X"54" => key_at <= pressed;
					when "0" & X"55" => key_plus <= pressed;
					when "0" & X"58" => key_capslock <= pressed;
					when "0" & X"59" => key_shiftr <= pressed;
					when "0" & X"5A" => key_return <= pressed;
					when "0" & X"5B" => key_star <= pressed;
					when "0" & X"5D" => key_pound <= pressed;
					when "0" & X"66" => key_del <= pressed;
					when "0" & X"69" => if pure64 = '0' then key_num1     <= pressed; else key_1       <= pressed; end if;
					when "0" & X"6B" => if pure64 = '0' then key_num4     <= pressed; else key_4       <= pressed; end if;
					when "0" & X"6C" => if pure64 = '0' then key_num7     <= pressed; else key_7       <= pressed; end if;
					when "0" & X"70" => if pure64 = '0' then key_num0     <= pressed; else key_0       <= pressed; end if;
					when "0" & X"71" => if pure64 = '0' then key_numdot   <= pressed; else key_dot     <= pressed; end if;
					when "0" & X"72" => if pure64 = '0' then key_num2     <= pressed; else key_2       <= pressed; end if;
					when "0" & X"73" => if pure64 = '0' then key_num5     <= pressed; else key_5       <= pressed; end if;
					when "0" & X"74" => if pure64 = '0' then key_num6     <= pressed; else key_6       <= pressed; end if;
					when "0" & X"75" => if pure64 = '0' then key_num8     <= pressed; else key_8       <= pressed; end if;
					when "0" & X"76" => if pure64 = '0' then key_esc      <= pressed; else key_runstop <= pressed; end if;
					when "0" & X"78" => restore_key <= pressed;
					when "0" & X"79" => if pure64 = '0' then key_numplus  <= pressed; else key_plus    <= pressed; end if;
					when "0" & X"7A" => if pure64 = '0' then key_num3     <= pressed; else key_3       <= pressed; end if;
					when "0" & X"7B" => if pure64 = '0' then key_numminus <= pressed; else key_minus   <= pressed; end if;
					when "0" & X"7C" => if pure64 = '0' then key_help     <= pressed; else key_star    <= pressed; end if;
					when "0" & X"7D" => if pure64 = '0' then key_num9     <= pressed; else key_9       <= pressed; end if;
					when "0" & X"83" => key_F7 <= pressed;

					when "1" & X"11" => key_fn <= pressed;  -- AltGr (right)
					when "1" & X"14" => key_ctrl <= pressed; -- Ctrl (right)
					when "1" & X"1F" => key_commodore <= pressed; -- Super (left)
					when "1" & X"27" => key_commodore <= pressed; -- Super (right)
					when "1" & X"4A" => if pure64 = '0' then null                   ; else key_slash   <= pressed; end if;
					when "1" & X"5A" => if pure64 = '0' then key_enter    <= pressed; else key_return  <= pressed; end if;
					when "1" & X"69" => key_runstop <= pressed;
					when "1" & X"6B" => key_left <= pressed;
					when "1" & X"6C" => key_home <= pressed;
					when "1" & X"70" => key_inst <= pressed;
					when "1" & X"71" => key_del <= pressed;
					when "1" & X"72" => key_down <= pressed;
					when "1" & X"74" => key_right <= pressed;
					when "1" & X"75" => key_up <= pressed;
					when "1" & X"77" => if pure64 = '0' and pressed = '1' and ps2_key /= last_key then
						if noscroll_lock = '1' then
							noscroll_lock <= '0';
							key_noscroll <= '0';
						elsif noscroll_delay /= 0 then
							if key_noscroll = '1' then
								noscroll_lock <= '1';
							end if;
						else
							key_noscroll <= '1';
						end if;
						noscroll_delay <= C_NOSCROLL_DELAY;
					end if;
					when "1" & X"7A" => if pure64 = '0' then key_linefd <= pressed; else key_arrowup <= pressed; end if;
					when "1" & X"7C" => key_d4080 <= pressed;
					when "1" & X"7D" => tape_play <= pressed;
					when others => null;
				end case;
			end if;

			if reset = '1' then
					key_F1        <= '0';
					key_F2        <= '0';
					key_F3        <= '0';
					key_F4        <= '0';
					key_F5        <= '0';
					key_F6        <= '0';
					key_F7        <= '0';
					key_F8        <= '0';
					key_shiftr    <= '0';
					key_shiftl    <= '0';
					key_ctrl      <= '0';
					key_commodore <= '0';
					key_runstop   <= '0';
					restore_key   <= '0';
					tape_play     <= '0';
					key_arrowup   <= '0';
					key_equal     <= '0';
					key_arrowleft <= '0';
					key_space     <= '0';
					key_comma     <= '0';
					key_dot       <= '0';
					key_slash     <= '0';
					key_colon     <= '0';
					key_minus     <= '0';
					key_semicolon <= '0';
					key_at        <= '0';
					key_plus      <= '0';
					key_Return    <= '0';
					key_star      <= '0';
					key_pound     <= '0';
					key_del       <= '0';
					key_left      <= '0';
					key_home      <= '0';
					key_inst      <= '0';
					key_down      <= '0';
					key_right     <= '0';
					key_up        <= '0';
					key_1         <= '0';
					key_2         <= '0';
					key_3         <= '0';
					key_4         <= '0';
					key_5         <= '0';
					key_6         <= '0';
					key_7         <= '0';
					key_8         <= '0';
					key_8s        <= '0';
					key_9         <= '0';
					key_0         <= '0';
					key_Q         <= '0';
					key_Z         <= '0';
					key_S         <= '0';
					key_A         <= '0';
					key_W         <= '0';
					key_C         <= '0';
					key_X         <= '0';
					key_D         <= '0';
					key_E         <= '0';
					key_V         <= '0';
					key_F         <= '0';
					key_T         <= '0';
					key_R         <= '0';
					key_N         <= '0';
					key_B         <= '0';
					key_H         <= '0';
					key_G         <= '0';
					key_Y         <= '0';
					key_M         <= '0';
					key_J         <= '0';
					key_U         <= '0';
					key_K         <= '0';
					key_I         <= '0';
					key_O         <= '0';
					key_L         <= '0';
					key_P         <= '0';
					key_tab       <= '0';
					key_alt       <= '0';
					key_fn        <= '0';
					key_capslock  <= '0';
					key_num0      <= '0';
					key_num1      <= '0';
					key_num2      <= '0';
					key_num3      <= '0';
					key_num4      <= '0';
					key_num5      <= '0';
					key_num6      <= '0';
					key_num7      <= '0';
					key_num8      <= '0';
					key_num9      <= '0';
					key_numplus   <= '0';
					key_numminus  <= '0';
					key_d4080     <= '0';
					key_esc       <= '0';
					key_numdot    <= '0';
					key_enter     <= '0';
					key_noscroll  <= '0';
					key_help      <= '0';
					key_linefd    <= '0';
			end if;

			mod_key <= key_fn;
			sftlk_sense <= shift_lock_state;
			cpslk_sense <= capslock_state;
			d4080_sense <= disp4080_state;
			noscr_sense <= noscroll_lock;
		end if;
	end process;
end architecture;
