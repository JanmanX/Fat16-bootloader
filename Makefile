DISK_IMAGE=bin/disk.img
QEMU=qemu-system-x86_64
QEMU_FLAGS=-m 16G
BOCHS=bochs
AS=nasm
AFLAGS=-f bin -g
SOURCES=$(wildcard src/*.asm)
OBJECTS=$(SOURCES:.asm=.)
VM=vm
DEBUG_DIR=./debug


.PHONY: clean mount umount

#  $@ Contains the target file name.
#  $< Contains the first dependency file name.
%: %.asm
	$(AS) $(AFLAGS) $< -o $@


# Macro...
disk: $(DISK_IMAGE)

run: $(DISK_IMAGE)
	$(QEMU) $(QEMU_FLAGS) $(DISK_IMAGE)


create_disk:
	-rm -fv $(DISK_IMAGE)
	dd if=/dev/zero of=$(DISK_IMAGE) bs=16MB count=125 conv=fsync


# WRITE BIOS PARAMETER BLOCK BEFORE MOUNTING IT, AS IT CHANGES
# FAT 16 INFORMATION
$(DISK_IMAGE): clean src/bootloader src/stage2
	mkfs.fat -F 16 $(DISK_IMAGE)
	dd if=src/bootloader of=$(DISK_IMAGE) conv=notrunc,fsync
	-sudo umount ./tmp
	sudo mount $(DISK_IMAGE) ./tmp
	-sudo rm ./tmp/STAGE2.BIN
	sudo cp src/stage2 ./tmp/STAGE2.BIN
	sudo umount ./tmp/


debug_real_mode: $(DISK_IMAGE)
	$(QEMU) $(DISK_IMAGE) -s -S & gdb -x $(DEBUG_DIR)/gdb/real_mode.txt


debug_long_mode: $(DISK_IMAGE)
	$(QEMU) $(DISK_IMAGE) -s -S & gdb -x $(DEBUG_DIR)/gdb/long_mode.txt



bochs: $(DISK_IMAGE)
	$(BOCHS) -f $(DEBUG_DIR)/bochs/bochs.conf -q


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
