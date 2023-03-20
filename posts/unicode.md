# Unicode
<!-- ---
title: Unicode
date: 2018-02-07 00:29:43
tags: encoding
--- -->
## 整理一下关于编码的知识

写 Windows 客户端难免碰到蛋疼的编码问题。用 Rust ffi 的时候，也涉及到了编码转换的问题。于是就整理了一些关于编码的知识。如有错漏，欢迎指正。

## 字符集

为每一个字符分配一个唯一的数字编号（码点 / code point），当前范围是 0 至 0x10FFFF 。

## 编码方式

将 code point 转换为字节序列的规则。UTF-8，UTF-16, UTF-32 指的都是编码规则。

### UTF-8

UTF-8 指的是编码单元为一个字节的一种变长编码规则，一个字符编码为1至4个字节。具体编码规则参考 wiki：

[https://en.wikipedia.org/wiki/UTF-8](https://en.wikipedia.org/wiki/UTF-8)

一个实现了 UTF-8 encoding 的 Json 解析器教学项目：

[https://github.com/WLBF/json-tutorial](https://github.com/WLBF/json-tutorial)

流行的主要原因：

* 它采用字节为编码单元，没有字节序（endianness）的问题
* 节省空间 ASCII 字符只需要一个字节存储，某些字符相比于 UTF-16 能节省一个字节
* 由于 ASCII 字符的编码方式和原来相同，原有程序很容易兼容

### UTF-16

UTF-16 的编码单元为两个字节，也是变长编码规则，一个字符编码为2或4个字节。或具体编码规则参考 wiki：

[https://en.wikipedia.org/wiki/UTF-16](https://en.wikipedia.org/wiki/UTF-16)

0至0xFFFF的 code point ，按照 UTF-16 编码后数值上是相同的，这些 code point 称为 BMP（basic multilingual plane）。编码0x10000至0x10FFFF的 code point 会使用代理对（surrogate pairs）。UTF-16，代理对， UCS-2 的关系参考 wiki 的说明。可以看出UTF-16 即使存储 ASCII 字符也需要2字节，超出 BMP 的字符都需要编码成4个字节，相比 UTF-8 更浪费空间。由于编码单元是2字节，还会出现字节序的问题。

### UTF-32

UTF-32 是定长编码规则，类似 UTF-16 中处理 BMP 的方式，4个字节的编码单元已经足够表示所有 code point，不需要再做什么转换。同样也有字节序的问题。

## Windows 的编码

在 Windows 系统上存在 code page 这个东西，涉及到一些历史因素。code page 可以认为等同于编码方式。很多 Win32 API 都存在 `A` 和 `W` 两个版本，`A` 版本的 API 系统当前的 code page 来处理文本参数。而 `W` 的版本是基于 Unicode 来处理文本参数，使用 UTF-16 编码处理文本。

例子：

```cpp
#include "stdafx.h"
#include "stdio.h"

int main()
{
    wchar_t dog[] = L"子龙🐶";
    for (auto x : dog)
    {
        printf("%04x\n", x);
    }
    return 0;
}
```

输出结果是：

```text
5b50
9f99
d83d
dc36
0000
```

可以看出 `wchar_t` 数组中存储的文本是以 UTF-16 来编码的。其中值得注意的是 `🐶` 这个字符不在 BMP 之内，采用了代理对编码为 `d83d dc36` ， 还有就是在 FFI 的时候要注意字符串末尾的 `0` 。在 Windows 2000 之前 `W` 的版本的 API 只支持 BMP， 之后才开始支持代理对。

详细参考 MSDN ：

[Code Pages](https://msdn.microsoft.com/en-us/library/windows/desktop/dd317752.aspx)

[Working with Strings](https://msdn.microsoft.com/en-us/library/ff381407.aspx)
