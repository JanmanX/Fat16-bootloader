#!/bin/bash

# Print all output
set -x
mkdir $HOME/src

export PREFIX="$HOME/opt/cross"
export TARGET=x86_64-elf
export PATH="$PREFIX/bin:$PATH"


# BINUTILS
cd $HOME/src
wget ftp://ftp.gnu.org/gnu/binutils/binutils-2.26.tar.bz2
tar xf binutils-2.26.tar.bz2

mkdir build-binutils
cd build-binutils
../binutils-2.26/configure --target=$TARGET --prefix="$PREFIX" --with-sysroot --disable-nls --disable-werror
make -j8
make install

# GCC
cd $HOME/src
wget ftp://ftp.gnu.org/gnu/gcc/gcc-5.3.0/gcc-5.3.0.tar.bz2
tar xf gcc-5.3.0.tar.bz2

# The $PREFIX/bin dir _must_ be in the PATH. We did that above.
which -- $TARGET-as || echo $TARGET-as is not in the PATH

cd gcc-5.3.0
contrib/download_prerequisites
cd ..

mkdir build-gcc
cd build-gcc
../gcc-5.3.0/configure --target=$TARGET --prefix="$PREFIX" --disable-nls --enable-languages=c,c++ --without-headers
make all-gcc -j8
make all-target-libgcc -j8
make install-gcc
make install-target-libgcc


# Messsage for user
echo 'Add to path: PATH="$HOME/opt/cross/bin:$PATH"'
