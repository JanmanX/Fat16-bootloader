#!/bin/bash
objdump -DMintel -b binary -mi386 -Maddr16,data16 $1
