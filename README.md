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
Score of we4k-86762f9 vs 4ku-9eea311: 3 - 95 - 2  [0.040] 100
...      we4k-86762f9 playing White: 0 - 50 - 0  [0.000] 50
...      we4k-86762f9 playing Black: 3 - 45 - 2  [0.080] 50
...      White vs Black: 45 - 53 - 2  [0.460] 100
Elo difference: -552.1 +/- 257.1, LOS: 0.0 %, DrawRatio: 2.0 %
Finished match
```

### Where was there claimed to be only one zig function?
After compilation, only one zig function remains after inlining and dead code elimination.
