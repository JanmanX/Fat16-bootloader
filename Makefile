DISK_IMAGE=disk.img
USB=/dev/sdd
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




# WRITE BIOS PARAMETER BLOCK BEFORE MOUNTING IT, AS IT CHANGES
# FAT 16 INFORMATION
$(DISK_IMAGE): bootloader stage2
	dd if=/dev/zero of=$(DISK_IMAGE) bs=16MB count=125 conv=fsync
	mkfs.fat -F 16 $(DISK_IMAGE)
	dd if=bootloader of=$(DISK_IMAGE) conv=notrunc,fsync
	-mkdir ./tmp
	-sudo umount ./tmp
	sudo mount $(DISK_IMAGE) ./tmp
	sudo cp stage2 ./tmp/STAGE2.BIN
	sudo umount ./tmp/

debug: $(DISK_IMAGE)
	$(QEMU) $(DISK_IMAGE) -s -S & gdb -ex 'target remote localhost:1234'\
						-ex 'set architecture i8086' \
						-ex 'layout asm' \
						-ex 'layout regs' \
						-ex 'break *0x7c00 ' \
						-ex 'break *0x7e04 ' \
						-ex 'continue'

debug_kernel: $(DISK_IMAGE)
	$(QEMU) $(DISK_IMAGE) -s -S & gdb -ex 'target remote localhost:1234'\
						-ex 'layout asm' \
						-ex 'layout regs' \
						-ex 'break *0x7e04 ' \
						-ex 'continue'

vm: $(DISK_IMAGE)
	VBoxManage internalcommands createrawvmdk -rawdisk $(DISK_IMAGE) -filename os.vmdk


mount: $(DISK_IMAGE)
	-sudo mount $(DISK_IMAGE) ./tmp

umount: $(DISK_IMAGE)
	-sudo umount ./tmp

clean:
	-rm -rfv bootloader stage2 os.vmdk long_mode
	-sudo umount ./tmp
	-rm -rfv ./tmp
	-rm -rfv $(DISK_IMAGE)
