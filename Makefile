all: bootloader.bin brainfuck.bin floppy.img

bootloader.bin: bootloader.S
	nasm -f elf64 -o bootloader.o bootloader.S
	ld -Ttext 0x7c00 --oformat=binary bootloader.o -o bootloader.bin

brainfuck.bin: brainfuck.S
	nasm -f elf64 -o brainfuck.o brainfuck.S
	ld -Ttext 0x7e00 --oformat=binary brainfuck.o -o brainfuck.bin

floppy.img: bootloader.bin brainfuck.bin
	dd if=/dev/zero of=floppy.img bs=1024 count=1440
	dd if=bootloader.bin of=floppy.img bs=512 seek=0 count=1 conv=notrunc
	dd if=brainfuck.bin of=floppy.img bs=512 seek=1 conv=notrunc

clean: 
	rm -f *.o *.bin *.img

run:
	qemu-system-x86_64 -drive file=floppy.img,if=floppy,index=0,format=raw
