DISK_IMAGE=bin/disk.img
QEMU=qemu-system-x86_64
AS=nasm
AFLAGS=-f bin -g
SOURCES=$(wildcard src/*.asm)
OBJECTS=$(SOURCES:.asm=.)

.PHONY: clean mount umount

#  $@ Contains the target file name.
#  $< Contains the first dependency file name.
%: %.asm
	$(AS) $(AFLAGS) $< -o $@


# Macro...
disk: $(DISK_IMAGE)

run: $(DISK_IMAGE)
	$(QEMU) $(DISK_IMAGE)


create_disk:
	-rm -fv $(DISK_IMAGE)
	dd if=/dev/zero of=$(DISK_IMAGE) bs=16MB count=125 conv=fsync


# WRITE BIOS PARAMETER BLOCK BEFORE MOUNTING IT, AS IT CHANGES
# FAT 16 INFORMATION
$(DISK_IMAGE): src/bootloader src/stage2
	mkfs.fat -F 16 $(DISK_IMAGE)
	dd if=src/bootloader of=$(DISK_IMAGE) conv=notrunc,fsync
	-sudo umount ./tmp
	sudo mount $(DISK_IMAGE) ./tmp
	sudo cp src/stage2 ./tmp/STAGE2.BIN
	sudo umount ./tmp/


debug: $(DISK_IMAGE)
	$(QEMU) $(DISK_IMAGE) -s -S & gdb -ex 'target remote localhost:1234'\
						-ex 'set architecture i8086' \
						-ex 'layout asm' \
						-ex 'layout regs' \
						-ex 'break *0x7c00 ' \
						-ex 'break *0x8000 ' \
						-ex 'continue'

vm: $(DISK_IMAGE)
	VBoxManage internalcommands createrawvmdk -rawdisk $(DISK_IMAGE) -filename bin/os.vmdk


mount: $(DISK_IMAGE)
	-sudo mount $(DISK_IMAGE) ./tmp

umount: $(DISK_IMAGE)
	-sudo umount ./tmp


clean:
	echo $(OBJECTS)
	-rm -rfv src/bootloader src/stage2 bin/os.vmdk src/long_mode
	-sudo umount ./tmp
	-rm -rfv ./tmp
	mkdir ./tmp

full_clean: create_disk clean
