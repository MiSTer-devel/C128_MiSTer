# C128 (unofficial) for [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

*In development, not complete*

Based on [C64_MiSTer](https://github.com/MiSTer-devel/C64_MiSTer) by sorgelig.

Based on FPGA64 by Peter Wendrich with heavy later modifications by different people.

## C128 features implemented

- MMU fully implemented and tested using [VICE test progs](https://sourceforge.net/p/vice-emu/code/HEAD/tree/testprogs/c128/)
- C128 specific keys
- VDC standard modes (text & bitmap) implemented
- Booting in C64, C128 or CP/M mode
- Automatic detection of .CRT files: C64 cartridges boot in C64 mode, C128 cartridges boot in C128 mode. C128 .CRT files must contain a [C128 CARTRIDGE](https://vice-emu.sourceforge.io/vice_17.html#SEC392) header to be detected.
- Loading of .PRG files to the correct memory location in C128 mode.

### C128 features not (yet/fully) implemented

- VDC scrolling, interlace, 40 column mode, non-standard modes
- Internal function ROM
- Fast serial IEC
- MFM .d81 images for CP/M (currently only .d64 or non-MFM .d81 disk images will work)
- 1571 drive/.d71 images

### Other TODOs and known issues

- Automatic detection of C64/C128 .PRG files to boot in the appropriate mode.
- Re-enable 3x and 4x turbo modes for 8502
- Turbo mode for Z80
- Currently not possible to change 1541 ROM

## Usage

### Internal memory 

In the OSD->Hardware menu, internal memory size can be selected as 128K or 256K. The latter activates RAM in banks 2 and 3. C128 basic does not detect this memory however, so it will
still show 122365 bytes free.

### ROM set

The ROM set option in the OSD->Hardware menu lets you switch between standard C128 and C128DCR roms.

### Char switch

The Char switch option in the OSD->Hardware menu lets you select how the two character ROM banks are switched.

English versions of the C128 switch character set depending on C128 or C64 mode, whereas international versions of the C128 have an "ASCII/DIN" key that replaces the "CAPS LOCK" key to 
manually switch character sets. 

### Loadable ROM

External ROMs can be loaded to replace the standard ROMs in OSD->Hardware.

**ROM 1/4**: Expects a 16kB, 32kB or 40kb file. First 16 kB contains C64 basic and kernal (a.k.a ROM1), next 16 kB contains the C128 kernal
(a.k.a ROM4), and the last 8 kB is loaded as the character rom. This makes it possible to load international versions of the C128 OS as a single file.

It's possible to only change the C64 ROM by loading a 16 kB ROM image, or the contents of both ROM1 and 4 without updating the character rom by loading a 32 kB image.

*Note*: some C64 ROM files created for the C64 MiSTer core are bigger than 16kB and include the disk ROM as well, for example the Dolphin DOS ROM.
These ROM files will *not* work with this core as they will overwrite the C128 kernal parts. To use these ROMs the C64 and drive ROM parts must be loaded separately.

**ROM 2/3**: Expects a 32kB file containing the complete C128 basic ROM. C128 kernal and C128 basic ROM versions must match to function correctly.

**Function rom**: Loads the internal function ROM. Not implemented yet.

**Drive rom**: Loads the ROM for the disk drive.

### VDC/80 column mode

Video output can be selected using the keyboard. Pressing <kbd>Print screen</kbd> or <kbd>AltGr</kbd>+<kbd>F7</kbd> emulates the <kbd>40/80 display</kbd> toggle switch on the C128 keyboard.
This will also switch which video output is shown on the VGA/HDMI output of the MiSTer.

In OSD->Audio&Video the VDC version and memory size can be selected.

### Keyboard
* <kbd>End</kbd> - <kbd>Run stop</kbd>
* <kbd>F2</kbd>, <kbd>F4</kbd>, <kbd>F6</kbd>, <kbd>F8</kbd>, <kbd>Left</kbd>/<kbd>Up</kbd> keys automatically activate <kbd>Shift</kbd> key.
* <kbd>F9</kbd> - <kbd>&#129145;</kbd> key.
* <kbd>F10</kbd> - <kbd>=</kbd> key.
* <kbd>F11</kbd> - <kbd>Restore</kbd> key. Also special key in AR/FC carts.
* Meta keys (Win/Apple) - <kbd>C=</kbd> key.
* <kbd>PgUp</kbd> - Tape play/pause
* <kbd>PgDn</kbd> - <kbd>Line feed</kbd>
* <kbd>Print Screen</kbd> - <kbd>Display 40/80</kbd>
* <kbd>Pause/Break</kbd> - <kbd>No Scroll</kbd> (* see note below)
* Numpad <kbd>*</kbd> - <kbd>Help</kbd>

The <kbd>AltGr</kbd> key (right <kbd>Alt</kbd>) is used to access alternative function keys. Combined with <kbd>AltGr</kbd> the function keys are the C128 top-row special keys. To access these functions, press and hold <kbd>AltGr</kbd> while pressing any of the function keys:
* <kbd>AltGr</kbd>+<kbd>F1</kbd> - <kbd>Esc</kbd>
* <kbd>AltGr</kbd>+<kbd>F2</kbd> - <kbd>Alt</kbd>
* <kbd>AltGr</kbd>+<kbd>F3</kbd> - <kbd>Tab</kbd>
* <kbd>AltGr</kbd>+<kbd>F4</kbd> - <kbd>Caps Lock</kbd>
* <kbd>AltGr</kbd>+<kbd>F5</kbd> - <kbd>Help</kbd>
* <kbd>AltGr</kbd>+<kbd>F6</kbd> - <kbd>Line feed</kbd>
* <kbd>AltGr</kbd>+<kbd>F7</kbd> - <kbd>40/80 display</kbd>
* <kbd>AltGr</kbd>+<kbd>F8</kbd> - <kbd>No scroll</kbd>

It is possible to access the C128 top-row cursor keys, and the numpad keys on a PC keyboard without numpad using <kbd>AltGr</kbd> combined with the similar keys:
* <kbd>AltGr</kbd>+<kbd>return</kbd> - Numpad <kbd>enter</kbd>
* <kbd>AltGr</kbd>+<kbd>1</kbd> through <kbd>0</kbd> - Numpad <kbd>1</kbd> through <kbd>0</kbd>
* <kbd>AltGr</kbd>+<kbd>-</kbd> - Numpad <kbd>-</kbd>
* <kbd>AltGr</kbd>+<kbd>+</kbd> - Numpad <kbd>+</kbd>
* <kbd>AltGr</kbd>+<kbd>.</kbd> - Numpad <kbd>.</kbd>
* <kbd>AltGr</kbd>+Cursor keys - Top row cursor keys

<kbd>Shift lock</kbd> can be activated by pressing <kbd>AltGr</kbd>+<kbd>Shift</kbd>. This is a toggle, to release <kbd>Shift lock</kbd>, press the <kbd>AltGr</kbd>+<kbd>Shift</kbd> combination again.

![keyboard-mapping](keymap.gif)

Keys marked in blue are the keys sent when combined with <kbd>AltGr</kbd>.

*): The <kbd>Pause/Break</kbd> key acts like the <kbd>No scroll</kbd> key, however the <kbd>Pause/Break</kbd> PC key is special as it does not send a signal when it is released. To solve this, when the <kbd>Pause/Break</kbd> key is pressed, the <kbd>No scroll</kbd> key signal to the C128 is pulsed for short period. To hold <kbd>No scroll</kbd> on the C128 for longer, either use <kbd>AltGr</kbd>+<kbd>F8</kbd>, or quickly double press <kbd>Pause/break</kbd> and press any key to release <kbd>No scroll</kbd>.

## C128 cartridges

To load a cartridge - "External function ROM" in C128 terms - it must be in .CRT format. To convert a binary ROM image into a .CRT, the 
[cartconv](https://vice-emu.sourceforge.io/vice_15.html) tool from Vice can be used, usually like this:

`cartconv.exe -t c128 -l 0x8000 -i cart.bin -o cart.crt`

The `-t c128` option is needed to create the correct header indicating this is a C128 cartridge. Otherwise the cartridge will be detected
as a C64 cartridge and the core will start up in C64 mode like a real C128 would do if a C64 cartridge is inserted. 

The `-l 0x8000` option is needed to indicate the image should be located at address $8000. Some external ROMs might need to be located at $C000, 
in that case `-l 0xC000` should be used.

# C64 features

The following is the original C64_MiSTer README. Some features still apply, others don't:

## Features
- C64 and C64GS modes.
- C1541 read/write/format support in raw GCR mode (*.D64, *.G64)
- C1581 read/write support (*.D81)
- Parallel C1541 port for faster (~20x) loading time using DolphinDOS.
- External IEC through USER_IO port.
- Amost all cartridge formats (*.CRT)
- Direct file injection (*.PRG)
- Dual SID with several degree of mixing 6581/8580 from stereo to mono.
- Similar to 6581 and 8580 SID filters.
- REU 16MB and GeoRAM 4MB memory expanders.
- OPL2 sound expander.
- Pause option when OSD is opened.
- 4 joysticks mode.
- RS232 with VIC-1011 and UP9600 modes either internal or through USER_IO.
- Loadable Kernal/C1541 ROMs.
- Special reduced border mode for 16:9 display.
- C128/Smart Turbo mode up to 4x.
- Real-time clock

## Installation
Copy the *.rbf to the root of the SD card. Copy disks/carts to C64 folder.

## Usage

### Using without keyboard
If your joystick/gamepad has more than 4 buttons then you can have some limited usage of keyboard.
Joystick buttons **Mod1** and **Mod2** adds 12 frequently used keys to skip the intros and start the game.
Considering default button maps RLDU,Fire1,Fire2,Fire3,Paddle Btn, following keys are possible to enter:
* With holding **Mod1**: Cursor RLDU, Enter, Space, Esc, Alt+ESC(LOAD"*" then RUN)
* With holding **Mod2**: 1,2,3,4,5,0,Y,N
* With holding **Mod1+Mod2**: F1,F2,F3,F4,F5,F6,F7,F8

With maps above and using Dolphin DOS you can issue **F7** to list the files on disk, then move cursor to required file, then issue **Alt+ESC** to load it and run.

### ~~Loadable ROM~~
*(**not** applicable to C128_MiSTer)*

~~Alternative ROM can loaded from OSD: Hardware->Load System ROM.
Format is simple concatenation of BASIC + Kernal.rom + C1541.rom~~

~~To create the ROM in DOS or Windows, gather your files in one place and use the following command from the DOS prompt. 
The easiest place to acquire the ROM files is from the VICE distribution. BASIC and KERNAL are in the C64 directory,
and dos1541 is in the Drives directory.~~

~~`COPY BASIC + KERNAL + dos1541 MYOWN.ROM /B`~~

~~To use JiffyDOS or another alternative kernel, replace the filenames with the name of your ROM or BIN file.  (Note, you muse use the 1541-II ROM. The ROM for the original 1541 only covers half the drive ROM and does not work with emulators.)~~

~~`COPY /B BASIC.bin +JiffyDOS_C64.bin +JiffyDOS_1541-II.bin MYOWN.ROM`~~

~~To confirm you have the correct image, the BOOT.ROM created must be exactly 32768 or 49152(in case of 32KB C1541 ROM) bytes long.~~

~~There are 2 loadable ROM sets are provided: **DolphinDOS v2.0** and **SpeedDOS v2.7**. Both ROMs support parallel Disk Port. DolphinDOS is fastest one.~~

~~For **C1581** you can use separate ROM with size up to 32768 bytes.~~

### Autoload the cartridge
In OSD->Hardware page you can choose Boot Cartridge, so everytime core loaded, this cartridge will be loaded too.

### Parallel port for disks.
Are you tired from long loading times and fast loaders aren't really fast when comparing to other systems? 

Here is the solution:
In OSD->System page choose **Expansion: Fast Disks**. Then load [DolphinDOS_2.0.rom](releases/DolphinDOS_2.0.rom). You will get about **20x times faster** loading from disks!

### Turbo modes
*(**not** applicable to C128_MiSTer, C128 mode is always active)*

~~**C128 mode:** this is C128 compatible turbo mode available in C64 mode on Commodore 128 and can be controlled from software, so games written with this turbo mode support will take advantage of this.~~

~~**Smart mode:** In this mode any access to disk will disable turbo mode for short time enough to finish disk operations, thus you will have turbo mode without loosing disk operations.~~

### RS232

Primary function of RS232 is emulated dial-up connection to old-fashioned BBS. **CCGMS Ultimate** is recommended (Don't use CCGMS 2021 - it's buggy version). It supports both standard 2400 VIC-1011 and more advanced UP9600 modes.

**Note:** DolphinDOS and SpeedDOS kernals have no RS232 routines so most RS232 software don't work with these kernals!

### GeoRAM
*(untested in C128_MiSTer, probably only works in C64 mode)*

Supported up to 4MB of memory. GeoRAM is connected if no other cart is loaded. It's automatically disabled when cart is loaded, then enabled when cart unloaded.

### REU
*(untested in C128_MiSTer, probably only works in C64 mode)*

Supported standard 512KB, expanded 2MB with wrapping inside 512KB blocks (for compatibility) and linear 16MB size with full 16MB counter wrap.
Support for REU files.

GeoRAM and REU don't conflict each other and can be both enabled.

### USER_IO pins

| USER_IO | USB 3.0 name | Signal name |
|:-------:|:-------------|:------------|
|   0     |    D+        | RS232 RX    |
|   1     |    D-        | RS232 TX    |
|   2     |    TX-       | IEC /CLK    |
|   3     |    GND_d     | IEC /RESET  |
|   4     |    RX+       | IEC /DATA   |
|   5     |    RX-       | IEC /ATN    |

All signals are 3.3V LVTTL and must be properly converted to required levels!

### Real-time clock

RTC is PCF8583 connected to tape port.
To get real time in GEOS, copy CP-CLOCK64-1.3 from supplied [disk](https://github.com/mister-devel/C64_MiSTer/blob/master/releases/CP-ClockF83_1.3.D64) to GEOS system disk.

### Raw GCR mode

C1541 implementation works in raw GCR mode (D64 format is converted to GCR and then back when saved), so some non-standard tracks are supported if G64 file format is used. Support formatting and some copiers using raw track copy. Speed zones aren't supported (yet), but system follows the speed setting, so variable speed within a track should work.
Protected disk in most cases won't work yet and still require further tuning of access times to comply with different protections.

