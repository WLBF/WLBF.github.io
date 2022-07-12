---
title: Log Rotate
date: 2022-07-11 17:25:36
tags: [os, fs]
---

不论是应用程序还是操作系统，在运行过程中都会不断产生日志，大量的日志会逐渐耗尽所有磁盘空间。因此需要对产生的日志进行翻转或删除。这篇文章接下来会介绍一些类 unix 文件系统概念，然后分析 linux 上传统日志翻转工具 logrotate 的实现原理。我用 rust 写了一个类似工具： https://github.com/WLBF/filerotate

## 文件系统

文件系统的作用是以定结构组织持久化存储数据，同时在系统重新启动之后依然保持数据的完整性。文件系统一般需要解决以下几个问题：

* 以树状结构存储文件夹和文件，记录每个文件以及目录和磁盘块之间的对应关系。同时维护磁盘块的使用情况，包括哪些磁盘块已经被使用，哪些是空余的。
* 在系统关机甚至直接断电的情况下，保证磁盘上数据结构的一致性。不会出现元数据错误，例如某个文件正在使用的磁盘块被标记成空余。
* 不同进程可能同时访问同一个文件，文件系统需要协调并发访问，并保证不会出现竞争导致文件元数据结构错误。
* 磁盘的访问速度远慢于内存，文件系统需要在内存中构建一个磁盘块缓存池来提升文件的访问性能。

这篇文章接下来主要会介绍文件系统的组织结构，以及部分结构的详细原理。


## 存储结构

下图展示了文件系统的层次结构，省略了部分 journaling 相关的结构。首先是 inode 层提供了文件这一抽象，通过 inode num 访问 inode 的信息可以读取属于该文件的 block。directory 层的实现是一种特殊的 inode，这种 inode 的内容是一系列 directory 条目，每个条目包括文件的名称和文件的 inode num。pathname 层提供了层级式的文件路径抽象，能够递归地访问文件。file descriptor 层是系统资源的抽象（管道、设备、文件等等）。用户态程序一般通过 file descriptor 来访问文件。接下来会详细介绍每一层抽象的实现原理。

<div align="center">
    <img src="https://i.imgur.com/uxjwWNY.png">
</div>

## 磁盘

传统磁盘被看做是一种块设备，即使整个存储空间被均匀地分割成多个 block，每个 block 都有一个唯一的 block num，一般从 0 开始线性增长。程序通过 block num 寻址访问 block。block size 一般为 512 bytes，较新的磁盘 block size 则为 4096 bytes。

<div align="center">
    <img src="https://i.imgur.com/tDKzzoh.png">
</div>

文件系统会将磁盘的不同 block num 范围划分为不同的段，不同的段集中存储同类型的数据。例如 Inodes 段用于存储所有 Inodes 的信息，bitmap 段用于记录磁盘块的使用情况，包括哪些 block 已经被使用，哪些 block 是空闲的。 data 段则用于存储真正的数据内容。

## Inode

Inode 是文件系统中一个关键的数据结构， inode 定义了一个文件或目录的元信息在磁盘上以何种形式存储。Inode 存在于磁盘上，在内核的内存空间中也存在添加了某些额外信息的 inode 数据结构映射。由于多个 inode 大小一致切被连续存在磁盘的某一段中，因此可以很方便地给 inode 标记顺序增长的序号 inode number，操作系统也正是通过 inode number 来访问某个 inode。

```c
/*
 * Constants relative to the data blocks
 */
#define	EXT2_NDIR_BLOCKS		12
#define	EXT2_IND_BLOCK			EXT2_NDIR_BLOCKS
#define	EXT2_DIND_BLOCK			(EXT2_IND_BLOCK + 1)
#define	EXT2_TIND_BLOCK			(EXT2_DIND_BLOCK + 1)
#define	EXT2_N_BLOCKS			(EXT2_TIND_BLOCK + 1)

/*
 * Structure of an inode on the disk
 */
struct ext2_inode {
	__le16	i_mode;		/* File mode */
	__le16	i_uid;		/* Low 16 bits of Owner Uid */
	__le32	i_size;		/* Size in bytes */
	__le32	i_atime;	/* Access time */
	__le32	i_ctime;	/* Creation time */
	__le32	i_mtime;	/* Modification time */
	__le32	i_dtime;	/* Deletion Time */
	__le16	i_gid;		/* Low 16 bits of Group Id */
	__le16	i_links_count;	/* Links count */
	__le32	i_blocks;	/* Blocks count */
	__le32	i_flags;	/* File flags */
    ...
	__le32	i_block[EXT2_N_BLOCKS];/* Pointers to blocks */
    ...
	}
};
```

inode 中主要存储了文件的元数据，例如文件的类型、大小、链接数、数据地址等信息。inode 组织数据的方式类似虚拟内存，通过多级 pointer 使得大小固定的 inode 数据结构可以承载非常巨大的文件，还能够支持文件打洞（hole punching）功能，后文会有更详细的描述，缺点是多级 pointer 会在访问文件时带来磁盘 io 放大。这里的 block pointer 即为前文中描述的 block num，下图展示了两级 data block 的示意图，inode 首先有固定数量的 pointer 直接指向存储数据的 block，之后会有一个 pointer 指向一个内容为多个 pointer 的 block，这个 block 中的 pointer 才指向真正的数据块。以此类推可以有多级结构，可以指数级扩大 inode 能够承载的文件大小。

<div align="center">
    <img src="https://upload.wikimedia.org/wikipedia/commons/0/09/Ext2-inode.svg" width="80%" height="80%">
</div>


以常见的 ext2 文件系统为例，inode 有三级结构，有 12 个 direct pointer，1 个 indirect pointer，1 个 double indirect pointer，1 个 triple indirect pointer。假设磁盘 block size 为 4096，pointer size 为 4，能够计算出单个文件的最大大小为：

```
12 * 4KiB
+ (4096 / 4) * 4KiB
+ (4096 / 4) * (4096 / 4) * 4KiB
+ (4096 / 4) * (4096 / 4) * (4096 / 4) * 4KiB = 4TiB
```

## 目录

目录实际上只是一种具有特殊类型的 inode，目录 inode 的数据内用是多个顺序存储的条目。以下展示了 ext2 文件系统的条目结构，包括了 inode number，类型和名称。这里的名字就是 inode number 指向文件或目录的名字。多层目录构成了文件系统的树形结构，可能有多个名字不同条目指向同一个 inode，这种指向关系被称作（hard link）。inode 结构体种的 i_link_count 就代表了有多少条目指向自己，即指向自己的硬链接计数，删除文件的操作实际上就是删除指向 inode 的硬链接。硬链接计数为 0 的 inode 会被标记为空闲，代表着文件被删除。也就是说如果有一个文件有两个硬链接路径指向自己，只有两个路径都被删除之后，文件才可能被删除。

<div align="center">
    <img src="https://i.imgur.com/UG3lCoX.png" width="80%" height="80%">
</div>


平时在使用操作系统的过程中还会接触到软链接（symbolic link）这个概念比如 windows 上的快捷方式。软链接实现上也是一种特殊的 inode，软链接 inode 存储的内容实际上是文件的一个硬链接的路径，访问软链接时文件系统会先获取文件的硬链接路径再通过获取到的路径去访问文件 inode。和硬链接相比软链接在访问文件时多做了一次磁盘 io，且不保证指向的文件一定存在，但是可以跨文件系统建立软链接。硬链接由于是 inode 直接指向关系只能存在于同一个文件系统中。

```c
/*
 * Structure of a directory entry
 */

struct ext2_dir_entry {
	__le32	inode;			/* Inode number */
	__le16	rec_len;		/* Directory entry length */
	__le16	name_len;		/* Name length */
	char	name[];			/* File name, up to EXT2_NAME_LEN */
};
```

## 文件描述符

传统的类 unix 系统中用户最终是通过和文件描述符（fd）交互来进行 io 操作，每个进程在内核中都有个 fd 表，fd 背后可能是 file、pipe、socket。如果是使用 fd 背后则指向一个内核中的 file 对象，文件对象指向了对应的 inode。可能有多个不同进程的 fd 指向同一个 file 对象，多个文件对象也可能指向同一个 inode，file 对象还计算了指向自己的 fd 数量，只有所有 fd 被关闭，即 fd 被关闭，即 fd ref count 下降至 0， 文件对象才会被释放，内核保证了所有指向 inode 的文件对象被释放之后 inode 才会被释放，联系上文可以发现，删除一个文件时，需要删除该文件的所有硬链接了路径，且没有持有该文件 fd 的进程，才能确保文件的 inode 被释放，所占用的磁盘空间被释放。

## 文件翻转

文件翻转的目标是在单个日志文件过大的情况下，分割或清除部分日志，达到回收部分磁盘空间，避免磁盘被写满的效果。logrotate 工具实现的文件翻转方式有两种，重命名和 copy truncate。

### 重命名

重命名顾名思义指的就是在日志文件满足某些判断条件时，重命名当前的文件，创建名称和原文件相同的新文件，然后删除过期的文件。但此时有个问题，重命名文件只是修改目录 inode 中的条名称，inode num 并没有变化，原先进程的文件对象依然指向同一个 inode，进程还是会持续向重命名之后的文件写入日志，如果直接删除日志文件，背后的 inode 依然不会被释放，进程还是会不断向这个 inode 写入日志直到磁盘写满。解决办法就是发出一个通知让进程重新打开原路径的文件，这样写入日志的目标 inode 就完成了切换。通常的做法是发出一个 SIGUP 信号给进程，进程事先向内核注册相应的回调函数重新打开特定的文件 fd。通过重命名来进行日志翻转，优点是资源消耗少且过程迅速，缺点是需要写日志进程相互配合。

<div align="center">
    <img src="https://i.imgur.com/MkkxTrN.png">
</div>

### Copy Truncate

copy truncate 方式能够实现日志进程无感知的情况下进行日志翻转。但需要做日志内容复制，而且有很小的概率丢失一小部分日志。接下来介绍几个概念：

#### 稀疏文件

先回忆一下之前 inode blocks 的存储结构，类似虚拟内存，多级 block pointer 的结构能很方便地实现 allocate on write。只需要标记某个 block pointer invalid 就代表着这个 block pointer 代表的 data 内容是空白，实际上也没有真正的 block 被分配。只有真正向这个 block pointer 包含的 offset 写入数据，才会分配相对应的磁盘空间。所以在支持稀疏文件的操作系统上一个文件的大小信息可能并不能正确反映出该文件所占用的磁盘大小。

```bash
# dd if=/dev/zero of=file.img bs=1 count=0 seek=512M

# du -h --apparent-size file.img
512M    file.img

# du -h file.img
0    file.img
```

上面例子用 dd 创建了一个表面上大小是 512M 但实际上没有占用任何磁盘 block 的文件。

#### 稀疏拷贝

如果按照常规方式去复制一个稀疏文件，从原文件空读出字节流然后写入目标文件中，会导致被写入的文件会占用 apparent size 的磁盘空间，因为直接写入字节流即使字节流内容全部为空，就调用 lseek() 跳过这一段在目标文件上打个洞 (hole punching) 。这样复制出来的文件也会是和原文件相同的稀疏文件。logroate 就使用了这种简单的用户态实现，猜测是因为系统兼容性考虑。

#### 翻转过程

首先通过稀疏拷贝将日志文件复制到一个新文件，之后将原来的日志文件清空，下图中绿色代表存在数据的文件范围，白色代表文件中的洞。这里调用 truncate 系统调用会将文件所占用的物理磁盘块全部释放，并将文件大小清零。但并不会影响先前应用进程打开的文件对象，所以应用会继续在先前 offset 的为止继续写入内容，这样就实现了应用无感知的情况下释放磁盘的空间，并将文件大小清零。但并不会影响先前应用进程打开的文件对象，所以应用会继续在先前的 offset 的为止继续写入内容，这样就实现了应用无感知的情况下释放磁盘的空间，但这个过程只会在原日志文件的开头打一个洞，这就是复制日志时需要实现稀疏拷贝的原因。


观察下图中 round1 到 round2 的过程，可以预料到 log.txt 文件开头的洞会随着翻转次数的增加而随之增大，按照 logrotate 的用户态稀疏拷贝实现，性能不可避免地会出现劣化。也许可以通过 lseek 的 SEEK_DATA 选项直接跳过文件开头的洞，然后使用 sendfile 进行文件复制。这样应该可以实现一个更高效率的拷贝函数。这种日志翻转方式还有一个缺点，在复制完成到清空文件的间隔中应用进程还在不断写入日志，一次翻转过程可能会导致一小部分日志丢失。

<div align="center">
    <img src="https://i.imgur.com/5QHlyY9.png">
</div>

## 参考

https://pdos.csail.mit.edu/6.S081/2020/xv6/book-riscv-rev1.pdf
https://students.mimuw.edu.pl/ZSO/Wyklady/11_extXfs/extXfs.pdf
https://ext4.wiki.kernel.org/index.php/Ext4_Disk_Layout#Finding_an_Inode
https://en.wikipedia.org/wiki/Hard_link
https://github.com/logrotate/logrotate
