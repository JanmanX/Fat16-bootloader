#!/bin/bash
objdump -DMintel -b binary -mi386 -Maddr16,data16 $1
# ndisasm -b16 bootloader -o 0x7c00
