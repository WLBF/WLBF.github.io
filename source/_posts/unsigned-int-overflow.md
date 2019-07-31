---
title: Unsigned Int Overflow
date: 2019-07-30 23:54:05
tags: debug
---

写出了一个经典的 bug:

```c
#include <stdio.h>

int main() {

    size_t i;
    for (i = 10; i >= 0; i--) {
        printf("whatever\n");
    }

    return 0;
}
```

一开始看不出来，debug 发现编译器给了个死循环，才想起来是 `size_t` 溢出了。

```zsh
(gdb) disass main
Dump of assembler code for function main:
   0x00000000004004fd <+0>:    push   %rbp
   0x00000000004004fe <+1>:    mov    %rsp,%rbp
   0x0000000000400501 <+4>:    sub    $0x10,%rsp
   0x0000000000400505 <+8>:    movq   $0xa,-0x8(%rbp)
   0x000000000040050d <+16>:   mov    $0x4005a4,%edi
   0x0000000000400512 <+21>:   callq  0x4003f0 <puts@plt>
   0x0000000000400517 <+26>:   subq   $0x1,-0x8(%rbp)
   0x000000000040051c <+31>:   jmp    0x40050d <main+16>
End of assembler dump.
```
