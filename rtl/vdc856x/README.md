# Commodore 128 VDC
for the C128 MiSTer FPGA core, by Erik Scheffers

## Implemented
 * Memory interface (including copy and fill)
 * Standard text mode
 * Attributes, color
 * Double pixel/40 columns mode
 * Cursor
 * 640x200 "standard" graphics mode
 * Most Non-standard graphics modes, e.g. FLI
 * Lightpen trigger
 * Smooth scrolling
 * Interlace

## TODO / Known issues
 * Some high-res interlace bitmap modes (VMM sections 1, 2, 5, 6)
   * sections 1, 2: fetch of attribute and bitmap not aligned
   * sections 5, 6: scaler unstable, fields not correct probably due to odd lines per row
 * VSS exceeding CTV should result in solid line(s?) at field start (soci-05/06)
 * Cursor start/end lines incorrect in interlace mode
 
## References / Test programs
 * C128 programmers reference guide
 * RAM interface timing: https://c-128.freeforums.net/post/5516/thread
 * VICE VDC tests: https://sourceforge.net/p/vice-emu/code/HEAD/tree/testprogs/VDC/
 * Risen from Oblivion VDC V2, https://csdb.dk/release/?id=44983
 * Colour Spectrum by Crest https://csdb.dk/release/?id=205653
 * VDC Mode Mania by tokra of Akronyme Analogiker https://csdb.dk/release/?id=161195
