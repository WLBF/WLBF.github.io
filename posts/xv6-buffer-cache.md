# Xv6 Buffer Cache
<!-- ---
title: Xv6 Buffer Cache
date: 2021-04-28 00:32:53
tags: [xv6, os]
--- -->

buffer cache 是文件系统中最接近磁盘的一层抽象，在 6.S081 课程中实现了基于 lru 策略的 buffer cache，在这里做一个总结。 


## xv6 文件系统中的 buffer cache

### 基本实现

xv6 文件系统中的 buffer cache 使用的是最朴素双向链表实现，需要自己维护双向链表， buf 数据结构中有 prev next 两个指针成员变量用来实现双向链表， bcache 结构体中的 lock 用来保护对 buffer cache 的并发操作，buf 结构体中的 lock 则是用来保对自身 data 成员的并发操作。

```c
struct buf {
  int valid;   // has data been read from disk?
  int disk;    // does disk "own" buf?
  uint dev;
  uint blockno;
  struct sleeplock lock;
  uint refcnt;
  struct buf *prev; // LRU cache list
  struct buf *next;
  uchar data[BSIZE];
};

struct {
  struct spinlock lock;
  struct buf buf[NBUF];

  // Linked list of all buffers, through prev/next.
  // Sorted by how recently the buffer was used.
  // head.next is most recent, head.prev is least.
  struct buf head;
} bcache;
```

在初始化中完成双向链表的构建

```c
void
binit(void)
{
  struct buf *b;

  initlock(&bcache.lock, "bcache");

  // Create linked list of buffers
  bcache.head.prev = &bcache.head;
  bcache.head.next = &bcache.head;
  for(b = bcache.buf; b < bcache.buf+NBUF; b++){
    b->next = bcache.head.next;
    b->prev = &bcache.head;
    initsleeplock(&b->lock, "buffer");
    bcache.head.next->prev = b;
    bcache.head.next = b;
  }
}
```

获取一个 buf 首先遍历双向链表检查是否已经在 cache 中，如果命中则增加 buf 的 refcnt 并返回 buf。 如果没有命中，则从链表尾部开始向头部遍历寻找 refcnt 为 0 即暂时无人使用的 buf，找到后将其替换成需要获取的 buf。
```c
// Look through buffer cache for block on device dev.
// If not found, allocate a buffer.
// In either case, return locked buffer.
static struct buf*
bget(uint dev, uint blockno)
{
  struct buf *b;

  acquire(&bcache.lock);

  // Is the block already cached?
  for(b = bcache.head.next; b != &bcache.head; b = b->next){
    if(b->dev == dev && b->blockno == blockno){
      b->refcnt++;
      release(&bcache.lock);
      acquiresleep(&b->lock);
      return b;
    }
  }

  // Not cached.
  // Recycle the least recently used (LRU) unused buffer.
  for(b = bcache.head.prev; b != &bcache.head; b = b->prev){
    if(b->refcnt == 0) {
      b->dev = dev;
      b->blockno = blockno;
      b->valid = 0;
      b->refcnt = 1;
      release(&bcache.lock);
      acquiresleep(&b->lock);
      return b;
    }
  }
  panic("bget: no buffers");
}
```

释放 buf 则是减少 refcnt, 如果 refcnt 将至 0，就将 buf 放置到链表头部，由于换出 buf 是由尾部向头部遍历，所以最近释放的 buf 会最后被遍历到，这样就实现了 lru 的效果。


```c
// Release a locked buffer.
// Move to the head of the most-recently-used list.
void
brelse(struct buf *b)
{
  if(!holdingsleep(&b->lock))
    panic("brelse");

  releasesleep(&b->lock);

  acquire(&bcache.lock);
  b->refcnt--;
  if (b->refcnt == 0) {
    // no one is waiting for it.
    b->next->prev = b->prev;
    b->prev->next = b->next;
    b->next = bcache.head.next;
    b->prev = &bcache.head;
    bcache.head.next->prev = b;
    bcache.head.next = b;
  }
  
  release(&bcache.lock);
}

void
bpin(struct buf *b) {
  acquire(&bcache.lock);
  b->refcnt++;
  release(&bcache.lock);
}

void
bunpin(struct buf *b) {
  acquire(&bcache.lock);
  b->refcnt--;
  release(&bcache.lock);
}
```

### 优化

在基本实现中 buffer cache 的 lock 是一个性能瓶颈，所有对 buffer cache 的操作都需要争抢一个锁。想要降低对 buffer cache 锁的竞争强度，一个很自然的优化就是将 buffer cache 通过哈希函数分成多个 bucket，每个 bucket 通过一个 lock 来保护，通过对 buf 的 blockno 取模来确定使用的 bucket 编号， bucket 数量一般取一个质数。这个优化也可以叫做 multi buffer cache。

```c
#define NBKT 13

struct bkt {
  struct buf head;
  struct spinlock lk;
};

struct {
  struct spinlock lock;
  struct buf buf[NBUF];

  struct bkt bkt[NBKT];
} bcache;
```
在初始化中首先初始化了 bucket 数组，之后将所有 buf 平均分配到 bucket 中。

```c
void
binit(void)
{
  struct buf *b;
  struct bkt *bkt;
  int i;

  initlock(&bcache.lock, "bcache");

  for (i = 0; i < NBKT; i++) {
    bkt = bcache.bkt + i;
    initlock(&bkt->lk, "bcache");
    bkt->head.prev = &bkt->head;
    bkt->head.next = &bkt->head;
  }

  for(b = bcache.buf, i = 0; b < bcache.buf+NBUF; b++, i++){
    bkt = bcache.bkt + (i % NBKT);

    b->next = bkt->head.next;
    b->prev = &bkt->head;
    initsleeplock(&b->lock, "buffer");
    bkt->head.next->prev = b;
    bkt->head.next = b;
  }
}
```

在 multi buffer cache 运行中会遇到一种特殊的情况，即当前的 bucket 中的 buf 全部被用完了，没有空闲的 buf，但这时其他 bucket 中依然有空余的 buf。这种情况的应对办法就是从其他的 bucket 偷窃空闲 buf，这里的实现是从相邻的下一个 bucket 开始依次尝试偷窃一个空闲 buf。在偷窃过程中由于需要操作多个 bucket 的锁，这里的逻辑需要小心处理，解决思路有两种。
* 持有 A bucket 的锁同时获取 B bucket 的锁尝试偷窃，这时需要设置一个全局的 steal lock 来却确保偷窃行为的原子性，否则可能会出现 A 和 B 交差持有对方的锁导致死锁。
* 先释放 A bucket 锁，之后获取 B bucket 锁，偷窃后再尝试获取 A bucket 锁，这样同一时间内只持有一个 bucket 的锁，可以避免死锁。但重新获取 A bucket 锁后需要检查 A 中是否已经有了相同 block 的 buf，因为在偷窃中有一段时间是不持有 A 锁的，如果在这段时间内重复 get 相同的 block，不做检查的话 A 中可能出现多个相同的 block buf。

```c
// Look through buffer cache for block on device dev.
// If not found, allocate a buffer.
// In either case, return locked buffer.
static struct buf*
bget(uint dev, uint blockno)
{
  struct buf *b;
  struct bkt *bkt;
  int i, j;
  i = blockno % NBKT;
  bkt = bcache.bkt + i;

  acquire(&bkt->lk);

  // Is the block already cached?
  for(b = bkt->head.next; b != &bkt->head; b = b->next){
    if(b->dev == dev && b->blockno == blockno){
      b->refcnt++;
      release(&bkt->lk);
      acquiresleep(&b->lock);
      return b;
    }
  }

  // Not cached.
  // Recycle the least recently used (LRU) unused buffer.
  for(b = bkt->head.prev; b != &bkt->head; b = b->prev){
    if(b->refcnt == 0) {
      b->dev = dev;
      b->blockno = blockno;
      b->valid = 0;
      b->refcnt = 1;
      release(&bkt->lk);
      acquiresleep(&b->lock);
      return b;
    }
  }
  release(&bkt->lk);


  for (j = 1; j < NBKT; j++) {
    bkt = bcache.bkt + (i + j) % NBKT;

    acquire(&bkt->lk);
    for(b = bkt->head.prev; b != &bkt->head; b = b->prev){
      if(b->refcnt == 0) {
        b->next->prev = b->prev;
        b->prev->next = b->next;
        release(&bkt->lk);


        bkt = bcache.bkt + i;
        acquire(&bkt->lk);
        b->next = bkt->head.next;
        b->prev = &bkt->head;
        bkt->head.next->prev = b;
        bkt->head.next = b;

        for(b = bkt->head.next; b != &bkt->head; b = b->next){
          if(b->dev == dev && b->blockno == blockno){
            b->refcnt++;
            release(&bkt->lk);
            acquiresleep(&b->lock);
            return b;
          }
        }

        b = bkt->head.next;
        b->dev = dev;
        b->blockno = blockno;
        b->valid = 0;
        b->refcnt = 1;

        release(&bkt->lk);
        acquiresleep(&b->lock);
        return b;
      }
    }
    release(&bkt->lk);
  }

  panic("bget: no buffers");
}
```
