derive_pll_clocks
derive_clock_uncertainty

set_false_path -to   {emu|fpga64|vdc|*}

set_false_path -from {emu|fpga64|reset}
set_false_path -from {emu|fpga64|reset_t80}

set_false_path -from {emu|fpga64|Keyboard|*}
set_false_path -to   {emu|fpga64|Keyboard|*}
