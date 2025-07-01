# BFComp
Simple brainfuck compiler written in x86-64 AT&T assembly for Linux.

## Manual build
```
$ gcc comp.S -o bfcomp -ffreestanding -nostdlib
```

## Using
```
$ ./bfcomp file [stack size]
```

`out.S` file will be generated. You compile it with GCC or CLang or (G)AS.
