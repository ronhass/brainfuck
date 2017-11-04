# brainfuck
An emulator for the brainfuck programming language, which runs in x86/x86_64 real mode.

The emulator contains a "bootloader", which initializes the environment and loads the emulator code.

To compile the emulator into a bootable floppy disk, run "make all". To boot from this disk with QEMU, run "make run". A screenshot with "hello world" program:

![hello world](https://github.com/ronhass/brainfuck/blob/master/screenshot.png?raw=true)
