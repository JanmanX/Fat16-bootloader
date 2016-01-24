DISK_IMAGE=os.img
QEMU=qemu-system-x86_64
AS=nasm
AFLAGS=-f bin -g
SOURCES=$(wildcard *.asm)
OBJECTS=$(SOURCES:.asm=.)



#  $@ Contains the target file name.
#  $< Contains the first dependency file name.
%: %.asm
	$(AS) $(AFLAGS) $< -o $@

run: $(DISK_IMAGE)
	$(QEMU) $(DISK_IMAGE)

$(DISK_IMAGE): clean bootloader os_loader
	cat bootloader os_loader > $(DISK_IMAGE)

debug: $(DISK_IMAGE)
	$(QEMU) $(DISK_IMAGE) -s -S & gdb -ex 'target remote localhost:1234'\
						-ex 'set architecture i8086' \
						-ex 'layout asm' \
						-ex 'layout regs' \
						-ex 'break *0x7c00 ' \
						-ex 'break *0x7e04 ' \
						-ex 'continue'
vm: $(DISK_IMAGE)
	VBoxManage internalcommands createrawvmdk -rawdisk $(DISK_IMAGE) -filename os.vmdk

clean:
	-rm -rfv $(DISK_IMAGE)
	-rm -rfv bootloader os_loader os.vmdk long_mode
