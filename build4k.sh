#!/bin/sh
T=`mktemp`
cd src/asm
nasm -f elf64 combined.asm
cd ../..
zig build install -Drelease-small -Dcpu=skylake-vzeroupper
git clone https://github.com/aunali1/super-strip
cd super-strip
make
cd ..
super-strip/sstrip -z zig-out/bin/we4k
curl -O https://gitlab.com/PoroCYon/vondehi/-/raw/master/autovndh.py
chmod +x autovndh.py
./autovndh.py --xz --nostub zig-out/bin/we4k $T
cat bdzz.sh $T > $1
chmod +x $1