/********************************************************************************
 * Commodore 128 VDC
 * 
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 *
 * - timing not verified
 ********************************************************************************/

module vdc_video (
	input        clk,
	input        reset,
	input        enable,

   input        reg_ht,         // 7E/7F 126/127 Horizontal total (minus 1) [126 for original ROM, 127 for PAL on DCR]
   input        reg_hd,         //    50 80      Horizontal displayed
   input        reg_hp,         //    66 102     Horizontal sync position
   input        reg_vw,         //     4 4       Vertical sync width (plus 1)
   input        reg_hw,         //     9 9       Horizontal sync width
   input        reg_vt,         // 20/27 32/39   Vertical total (minus 1) [32 for NTSC, 39 for PAL]
   input        reg_va,         //    00 0       Vertical total adjust
   input        reg_vd,         //    19 25      Vertical displayed
   input        reg_vp,         // 1D/20 29/32   Vertical sync position (plus 1) [29 for NTSC, 32 for PAL]
   input        reg_im,         //     0 off     Interlace mode
   input        reg_ctv,        //    07 7       Character Total Vertical (minus 1)
   input        reg_cm,         //     1 none    Cursor mode
   input        reg_cs,         //     0 0       Cursor scanline start
   input        reg_ce,         //    07 7       Cursor scanline end (plus 1?)
   input        reg_cp,         //  0000 0000    Cursor position
   input        reg_cth,        //     7 7       Character total horizontal (minus 1)
   input        reg_cdh,        //     8 8       Character displayed horizontal (plus 1 in double width mode)
   input        reg_cdv,        //    08 8       Character displayed vertical (minus 1)
   input        reg_rvs,        //     0 off     Reverse screen
   input        reg_cbrate,     //     1 1/30    Character blink rate
   input        reg_vss,        //    00 0       Vertical smooth scroll
   input        reg_text,       //     0 text    Mode select (text/bitmap)
   input        reg_atr,        //     1 on      Attribute enable
   input        reg_semi,       //     0 off     Semi-graphic mode
   input        reg_dbl,        //     0 off     Pixel double width
   input        reg_hss,        //   0/7 0/7     Smooth horizontal scroll [0 for v0, 7 for v1]
   input        reg_fg,         //     F white   Foreground RGBI
   input        reg_bg,         //     0 black   Background RGBI
   input        reg_ai,         //    00 0       Address increment per row
   input        reg_ul,         //    07 7       Underline scan line
   input        reg_deb,        //    7D 125     Display enable begin
   input        reg_dee,        //    64 100     Display enable end
   
   output       hsync,
   output       vsync,
   output [3:0] rgbi
);

endmodule
