

init: init.asm
	nasm -f bin init.asm

run: init
	qemu-system-x86_64 init

hdd.bin: init
	cat init drive > hdd.bin

debug: hdd.bin
	qemu-system-x86_64 hdd.bin -s -S & gdb -ex 'target remote localhost:1234'\
						-ex 'set architecture i8086' \
						-ex 'layout asm' \
						-ex 'layout regs' \
						-ex 'break *0x7c00 ' \
						-ex 'continue'
