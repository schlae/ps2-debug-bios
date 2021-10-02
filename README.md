# PS/2 Model 77 (Bermuda Planar) Hacky Diagnostics ROM

Burn this into a 27C010 or 29F010 and swap it into the ROM socket on your machine. Use at your own risk.

The ROM attempts to write to the Micro Channel system control register at 0x94. Then it reads it back and beeps it out through the PC speaker in binary, where a '1' is a high pitched tone and a '0' is a low pitched tone, MSB first. First it writes a 0x00 and reads it back, then it writes a 0xff and reads it back.

Some of the register bits are reserved and always read back as '1'.

I might turn this into something more, but for now, this is just a hacky test ROM for your amusement.
