# Commodore 128 VDC
for the C128 MiSTer FPGA core, by Erik Scheffers

## Implemented
 * Memory interface (including copy and fill)
 * Standard text mode
 * Attributes, color
 * Cursor
 * 640x200 "standard" graphics mode
 * Lightpen trigger

## TODO
 * Vertical scrolling
 * Horizontal scrolling
 * Interlace
 * 40 columns mode
 * Non-standard character widths
 * Non-standard modes (e.g. split modes, 8x1 etc)

## Nice to have/wild ideas

 * VDC Turbo mode, where CPUs can access VDC at full clock speed instead of clock stretching to 1 MHz, and where VDC memory interface is not bound to the column width. A mode like this will definetly break compatibility with some programs, but most standard software including CP/M should be able to work with this.

## Used references
 * C128 programmers reference guide
 * RAM interface timing: https://c-128.freeforums.net/post/5516/thread
 * VICE VDC tests: https://sourceforge.net/p/vice-emu/code/HEAD/tree/testprogs/VDC/
