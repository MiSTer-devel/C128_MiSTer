/********************************************************************************
 * Commodore 128 VDC
 * 
 * for the C128 MiSTer FPGA core, by Erik Scheffers
 *
 * - timing not verified
 ********************************************************************************/

module vdc_video (
	input         clk,
	input         reset,
   input         init,
	input         enable,
 
   input   [7:0] reg_ht,         // R0      7E/7F 126/127 Horizontal total (minus 1) [126 for original ROM, 127 for PAL on DCR]
   input   [7:0] reg_hd,         // R1         50 80      Horizontal displayed
   input   [7:0] reg_hp,         // R2         66 102     Horizontal sync position 
   input   [3:0] reg_vw,         // R3[7:4]     4 4       Vertical sync width
   input   [3:0] reg_hw,         // R3[3:0]     9 9       Horizontal sync width (plus 1)
   input   [7:0] reg_vt,         // R4      20/27 32/39   Vertical total (minus 1) [32 for NTSC, 39 for PAL]
   input   [4:0] reg_va,         // R5         00 0       Vertical total adjust
   input   [7:0] reg_vd,         // R6         19 25      Vertical displayed
   input   [7:0] reg_vp,         // R7      1D/20 29/32   Vertical sync position (plus 1) [29 for NTSC, 32 for PAL]
   input   [1:0] reg_im,         // R8          0 off     Interlace mode **TODO**
   input   [4:0] reg_ctv,        // R9         07 7       Character Total Vertical (minus 1)
   input   [1:0] reg_cm,         // R10[6:5]    1 none    Cursor mode
   input   [4:0] reg_cs,         // R10[4:0]    0 0       Cursor scanline start
   input   [4:0] reg_ce,         // R11        07 7       Cursor scanline end (plus 1?)
   input  [15:0] reg_ds,         // R12/R13  0000 0000    Display start
   input  [15:0] reg_cp,         // R14/R15  0000 0000    Cursor position
   input   [3:0] reg_cth,        // R22[7:4]    7 7       Character total horizontal (minus 1)
   input   [3:0] reg_cdh,        // R22[3:0]    8 8       Character displayed horizontal (plus 1 in double width mode)
   input   [4:0] reg_cdv,        // R23        08 8       Character displayed vertical (minus 1)
   input         reg_rvs,        // R24[6]      0 off     Reverse screen
   input         reg_cbrate,     // R24[5]      1 1/30    Character blink rate
   input   [4:0] reg_vss,        // R24[4:0]   00 0       Vertical smooth scroll
   input         reg_text,       // R25[7]      0 text    Mode select (text/bitmap)
   input         reg_atr,        // R25[6]      1 on      Attribute enable
   input         reg_semi,       // R25[5]      0 off     Semi-graphic mode
   input         reg_dbl,        // R25[4]      0 off     Pixel double width
   input   [3:0] reg_hss,        // R25[3:0]  0/7 0/7     Smooth horizontal scroll [0 for v0, 7 for v1]
   input   [3:0] reg_fg,         // R26[7:4]    F white   Foreground RGBI
   input   [3:0] reg_bg,         // R26[3:0]    0 black   Background RGBI
   input   [7:0] reg_ai,         // R27        00 0       Address increment per row
   input   [4:0] reg_ul,         // R29        07 7       Underline scan line
   input   [7:0] reg_deb,        // R34        7D 125     Display enable begin
   input   [7:0] reg_dee,        // R35        64 100     Display enable end
 
   // output [7:0] reg_lpv,        // R16                   Light pen V position
   // output [7:0] reg_lph,        // R17                   Light pen H position

   // output [15:0] addr,
   // output        addrEn,
   // input         data,       

   output  wire  hsync,
   output  wire  vsync,
   output        hblank,
   output  wire  vblank,
   output  [3:0] rgbi
);


reg [3:0] hsCount;
reg [4:0] vsCount;
reg [4:0] vbCount;

assign hsync = |hsCount;
assign vsync = |vsCount;
assign vblank = |vbCount;

wire [8:0] vbstart = 9'(((reg_ctv+1) * reg_vp) - 4);
wire [4:0] vswidth = 5'(|reg_vw ? reg_vw : 16);
wire [4:0] vbwidth = 5'(vswidth + 8);

// Dot, Pixel and Scanline counters
always @(posedge clk) begin
   reg [3:0] dot, line;
   reg [8:0] scanline;
   reg [7:0] col, row;
   reg [7:0] hCnt, vCnt;
   reg [4:0] adjust;

	if (reset || init) begin
      dot <= 0;
      line <= 0;
      scanline <= 0;
      col <= 0;
      row <= 0;
      hCnt <= 0;
      vCnt <= 0;
      adjust <= 0;
      hsCount <= 0;
      vsCount <= 0;
      vbCount <= 0;
      // addr <= reg_ds;
      // addrEn <= 0;
      // visible <= 0;
   end
   else if (enable) begin
      // addrEn <= 0;
      dot <= dot + 4'd1;

      if (dot == reg_ctv) begin
         // new column
         dot <= 0;
         col <= col + 8'd1;

         if (col == reg_ht) begin
            // new line
            col <= 0;
            hCnt <= 0;
            line <= line + 4'd1;
            scanline <= scanline + 9'd1;

            if (|adjust) begin
               // vertical adjust
               if (adjust == 1) begin
                  // new frame
                  row <= 0;
                  vCnt <= 0;
                  scanline <= 0;
               end
               adjust <= adjust - 5'd1;
            end 
            else if (line == reg_cth) begin
               // new row
               line <= 0;
               row <= row + 8'd1;

               // display starts at row 1
               if (row == 1) vCnt <= reg_vd;
               else if (|vCnt) vCnt <= vCnt - 8'd1;

               // vertical sync start
               if (row == reg_vp) vsCount <= vswidth;

               // frame end
               if (row == reg_vt) begin
                  if (|reg_va) begin
                     // insert extra lines for vertical adjust
                     adjust <= reg_va;
                  end
                  else begin
                     // new frame
                     row <= 0;
                     vCnt <= 0;
                     scanline <= 0;
                  end
               end
            end

            // vsync counter
            if (|vsCount) vsCount <= vsCount - 5'd1;

            // vblank
            if (scanline == vbstart) vbCount <= vbwidth;
            else if (|vbCount) vbCount <= vbCount - 5'd1;
         end

         if (|vCnt) begin
            // display starts at column 8
            if (col == 8) hCnt <= reg_hd;
            else if (|hCnt) hCnt <= hCnt - 8'd1;
         end

         // horizontal sync
         if (col == reg_hp) hsCount <= reg_hw;
         else if (|hsCount) hsCount <= hsCount - 4'd1;

         // horizontal blanking
         if (col == reg_dee) hblank <= 1;
         if (col == reg_deb) hblank <= 0;
      end

      if (hblank || vblank)
         rgbi <= 0;
      else if (|hCnt && |vCnt)
         rgbi <= 4'(col+row);
      else
         rgbi <= reg_bg;
   end
end

endmodule
