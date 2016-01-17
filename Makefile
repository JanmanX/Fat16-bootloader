DISK_IMAGE=os.img
QEMU=qemu-system-x86_64
AS=nasm
AFLAGS=-f bin
SOURCES=$(wildcard *.asm)
OBJECTS=$(SOURCES:.asm=.)



#  $@ Contains the target file name.
#  $< Contains the first dependency file name.
%: %.asm
	$(AS) $(AFLAGS) $< -o $@

run: $(DISK_IMAGE)
	$(QEMU) $(DISK_IMAGE)

$(DISK_IMAGE): bootloader os_loader
	cat bootloader os_loader > $(DISK_IMAGE)

debug: $(DISK_IMAGE)
	$(QEMU) $(DISK_IMAGE) -s -S & gdb -ex 'target remote localhost:1234'\
						-ex 'set architecture i8086' \
						-ex 'layout asm' \
						-ex 'layout regs' \
						-ex 'break *0x7c00 ' \
						-ex 'break *0x7e00 ' \
						-ex 'continue'
