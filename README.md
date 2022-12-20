# we4k
we4k is a chess engine designed to fit into 4096 bytes.

## Building
we4k requires nasm and the latest zig compiler. Only Linux and cpus with AVX2 and BMI2 are supported.
```
cd src/asm
nasm -f elf64 combined.asm
cd ../..
zig build install -Drelease-small -Dcpu=skylake-vzeroupper
```

Instructions for actually fitting the binary into 4096 bytes may be coming soon.

## Questions
### Why is it called we4k?
```
Score of we4k-a1d01ff vs 4ku-7b322bd: 10 - 87 - 3  [0.115] 100
...      we4k-a1d01ff playing White: 6 - 41 - 3  [0.150] 50
...      we4k-a1d01ff playing Black: 4 - 46 - 0  [0.080] 50
...      White vs Black: 52 - 45 - 3  [0.535] 100
Elo difference: -354.5 +/- 112.5, LOS: 0.0 %, DrawRatio: 3.0 %
Finished match
```

### Where was there claimed to be only one zig function?
After compilation, only one zig function remains after inlining and dead code elimination.
