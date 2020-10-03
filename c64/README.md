# Commodore 64 emulator in OpenComputers

This folder is the commodore-emulation part of OC-C64.

## 6502 CPU (`6502.lua`)
The file containing the actual emulator, with a high-level Kernal API (the Kernal's subroutines are directly coded in Lua instead of in 6502 assembly)

## "Kernal" (`init/`)
It's not really the Kernal, as it only does init procedure and (will eventually) gives the hand to the BASIC ROM.

Requirements: [cc65](https://github.com/cc65/cc65)
To build:
```
cd init
make
```
It will update a `init.bin` file which contains the raw 6502 executable without any header.
