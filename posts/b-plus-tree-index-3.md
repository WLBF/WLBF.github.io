---
title: B Plus Tree Index 3
date: 2021-06-09 10:57:59
tags: [database, cmu-15445]
---

在数据库领域一般将操作系统层面上的 lock 称作 latch，为了实现对 B+ tree 的并发访问，需要使用 read write latch 来对树中的 node 进行保护， 对 B+ tree 的并发访问会使用一种叫做 crabbing/coupling 的技巧。

## B+Tree Latching

Lock crabbing/coupling is a protocol to allow multiple threads to access/modify B+Tree at the same time.
The basic idea is as follows.
1. Get latch for the parent.
2. Get latch for the child.
3. Release latch for the parent if it is deemed “safe”. A “safe” node is one that will not split or merge when updated (not full-on insertion or more than half full on deletion).

### Basic Latch Crabbing Protocol:
* **Search:** Start at the root and go down, repeatedly acquire latch on the child and then unlatch parent.
* **Insert/Delete:** Start at the root and go down, obtaining X latches as needed. Once the child is latched, check if it is safe. If the child is safe, release latches on all its ancestors.

Note that read latches do not need to worry about the “safe” condition. The notion of “safe” also depends on whether the operation is an insertion or a deletion. A full node is “safe” for deletion since a merge will not be needed but is not “safe” for an insertion since we may need to split the node. The order in which latches are released is not important from a correctness perspective. However, from a performance point of view, it is better to release the latches that are higher up in the tree since they block access to a larger portion of leaf nodes.

B+ tree 节点的获取锁顺序遵循从上至下的原则，如果两个线程获取锁的顺序相反则会出现死锁情况。所以在树修改过程中不允许出现从下向上获取父节点锁的行为，这就要求在获取锁的过程中要一次性获取所有可能出现改动 (split/coalsece/redistribte/修改内容) 的 node。通过检查 node 元素数量 `n` 可以分辨出该 node 是否 safe(不会发生 split/coalsece/redistribte) 即  `n < max_size - 1 && n > max_size / 2`。crabbing 的具体实现是，从 root node 开始向 leaf node 遍历，获取每一个 node 的写锁之后将其插入一个双端队列中。如果判断当前的 node 是一个 safe node，就将队列中该 node 之前所有的 node 解锁并弹出。最终队列中会剩下包括 leaf node 在内所有可能出现改动的 node。在 split 的过程中由于新分配的 node 只有当前线程可见所以无需加锁，而在实现 coalsece/redistribute 的过程中则必须需要获取选中的 sbiling node 的锁，因为此时可能出现竞争的情况。

### Improved Lock Crabbing Protocol:
The problem with the basic latch crabbing algorithm is that transactions always acquire an exclusive latch on the root for every insert/delete operation. This limits parallelism.  
Instead, one can assume that having to resize (i.e., split/merge nodes) is rare, and thus transactions can acquire shared latches down to the leaf nodes. Each transaction will assume that the path to the target leaf node is safe, and use READ latches and crabbing to reach it and verify. If the leaf node is not safe, then we abort and do the previous algorithm where we acquire WRITE latches.
* **Search:** Same algorithm as before.
* **Insert/Delete:** Set READ latches as if for search, go to leaf, and set WRITE latch on leaf. If the leaf is
not safe, release all previous latches, and restart the transaction using previous Insert/Delete protocol.

由于 page_size 的关系，节点发生 split/coalsece/redistribte 的概率是非常低的，所以可以实现一个乐观优化。每次改动从 root node 开始像 search 过程中那样获取读锁，只有到了 leaf node 再获取写锁，如果此时双端队列中不止有 leaf node 这一个 node，说明需要 split/coalsece/redistribte。这时将整个队列中的 node 都释放掉，从 root node 开始重新顺序获取写锁。在 page_size 为 4096 的测试中，实现优化之后 B+ tree 并发访问性能大约提升了 40%。  

### Root latching

由于 B+ tree 还有可能出现 root node 的变化，这里需要特殊的处理。一种思路是额外设置一个 root_latch 在 crabbing 的过程中每次解锁 node 时检查是否满足释放 root_latch 的条件，即 root node 不会出现改动，如果满足条件即可释放 root_latch。另一种更巧妙的技巧是，设置一个虚拟 root page，每操作开始时像对待其他 page 一样将这个 v_root_page 加锁并加入队列中，之后按照的 crabbing 正常操作，如果 v_root_page 被解锁释放，代表着 root node 是安全的，可以被其他线程访问了。  
