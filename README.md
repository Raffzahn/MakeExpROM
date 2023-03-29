# MakeExpROM
Utility to Build an IBM PC Option ROM

---

## Purpose

This tiny routine is meant to simplify creation of [Option (Expansion) ROM](https://en.wikipedia.org/wiki/Option_ROM) images for the original IBM-PC and compatible systems. For more deails and history see below.

## Workings

- A (binary) input file is read 
- Filled up to the next 2 KiB size (0800h/1000h/1800h/...) (*1)
- Fill wil lbe done using FFh (*2)
- ROM signature (AA 55) checked
- If not present it'll be written over the first two bytes
- ROM length in 512 byte pages is calculated and put into byte 3
- A checksum byte is calculated and placed into the last byte
- Everything iswritten out again

Maximum ROM size is 32 KiB. Any larger input will terminate without writing any output.


## Usage

Filehandling is done using redirection, so all needed is to assingn a rom image:

`MkExpROM <myrom.bin >myrom.rom` 

Multiple ROMs can be combined using output append:

`MkExpROM <myrom2.bin >>myrom.rom` 

Of course this can as well be done at any later point using `TYPE`

`type <myrom2.bin >>myrom.rom`


## Compilation

The source is written in MASM syntax and can be compiled using MASM 5 and up. Compatibility has been tested with Tested on Masm 5, 6 and 6.11. The programis written to run as EXE program. For linking usage of /CP:1 is mandatory to shrink default memory assignment as all buffer memory is allocated dynamic at runtime.

For MASM 5 use 
````
masm %1.asm
link /CP:1 %1,,%1;

````

For MASM 6 and later
````
bin\ml /c %1.asm 
binr\link /CP:1 %1,,%1;
````

## IBM PC Option ROM History and Workings

The original [1981 IBM PC](https://en.wikipedia.org/wiki/IBM_Personal_Computer) came with a [ROM configuration](https://minuszerodegrees.net/5150/misc/5150%20-%20Memory%20Map%20of%20the%20640%20KB%20to%201%20MB%20Area.jpg) of

- one 8 KiB ROM for its _BIOS_, mapped at `FE000h`,
- four 8 KiB ROMs for it's 32 KiB _BASIC_, mapped at `F6000h` and
- one empty socket for an 8 KiB _User ROM_, located at `F4000h`

The original 1981 PC had no provision to detect additional software in ROM, not even for the _User ROM_. It wasn't unti the 1983 [PC-XT](https://en.wikipedia.org/wiki/IBM_Personal_Computer_XT) that introduced a scan for Option ROMs as it needed a way to activate its (still optional) Fixed Disk controller. The same functionality was later added to the still produced IBM-PC with its 10/27/82 Revision.

To activte such additional ROM code the BIOS scanned, after basic system initialisation, the address range between the end of the default graphics RAM at `C8000h` and right until the free option ROM socket at`F4000h` (*3) for
- a two byte signature  f _AAh 55h_ at a 2 KiB border
- took the following byte as a length in 512 byte pages
- added up all bytes in those pages modulo 256
- if this checksum resulted in 00h
  - DS are loaded with the ROM segment
  - ES is loaded with BDA
  - a far jump to the 4th byte (seg:3) is taken

## Remarks

- The Programm was written in an afternoon to solve the checksum issue. It's not the most beautiful.
- In fact, One string is even included twice, but I'm simply too lazy to optimize that. 
- Redirection was used to save all effort in command line parsing or file opening/closing.
- Command line options may need to be added if a 512 byte size is desired (can't think of any reason roght now)

## Files (so far)

- [MkExpROM.asm](MkExpROM.asm) -> Source file
- README.md -> This file


---

\*1 - Other sizes do not really make any sense as the BIOS routines do scan in a 2 KiB intervall

\*2 - FFh is used as it's the default (empy) value for classic (E)PROM. That way one can use tha fill area to add some code patch if needed. May be less relevant in times of all software emulation :)

\*3 - Which means the Option ROM socket can only hold a single ROM image.
