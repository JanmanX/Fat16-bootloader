#!/bin/bash

device=$1

if [ $# -eq 0 ]
  then
    device=/dev/sdd
fi


echo $device
make os.img

dd if=/dev/zero of=$device bs=1M count=1 conv=fsync
dd if=os.img of=$device conv=fsync

sync
