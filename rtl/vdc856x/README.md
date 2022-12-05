# Commodore 128 VDC
for the C128 MiSTer FPGA core, by Erik Scheffers

## Implemented
 * Memory interface (including copy and fill)
 * Standard text mode
 * Attributes, color
 * Double pixel/40 columns mode
 * Cursor
 * 640x200 "standard" graphics mode
 * Lightpen trigger
 * Smooth scrolling
 * Interlace

## TODO
 * Non-standard high-res video modes like FLI modes (VDC Mode Mania)

## Nice to have/wild ideas

 * VDC Turbo mode, where CPUs can access VDC at full clock speed instead of clock stretching to 1 MHz, and where VDC memory interface is not bound to the column width. A mode like this will definetly break compatibility with some programs, but most standard software including CP/M should be able to work with this.

## Used references
 * C128 programmers reference guide
 * RAM interface timing: https://c-128.freeforums.net/post/5516/thread
 * VICE VDC tests: https://sourceforge.net/p/vice-emu/code/HEAD/tree/testprogs/VDC/
 * VDC Mode Mania by tokra of Akronyme Analogiker https://csdb.dk/release/?id=161195
 * Colour Spectrum by Crest https://csdb.dk/release/?id=205653
