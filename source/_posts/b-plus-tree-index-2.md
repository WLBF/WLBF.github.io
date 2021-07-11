---
title: B Plus Tree Index 2
date: 2021-05-09 05:23:56
tags: [database, cmu-15445]
---

## Deletion

B+ tree 的删除过程相对于插入过程要更复杂一些，包括 merge(coalsece) 和 redistribute 以及 adjust root 这三种情况，在实现过程中要细心编写针对各种情况的 unit test，否则很难正确实现。

Whereas in inserts we occasionally had to split leaves when the tree got too full, if a deletion causes a tree
to be less than half-full, we must merge in order to re-balance the tree.
1. Find correct leaf L.
2. Remove the entry:
* If L is at least half full, the operation is done.
* Otherwise, you can try to redistribute, borrowing from sibling.
* If redistribution fails, merge L and sibling.
3. If merge occurred, you must delete entry in parent pointing to L.

### Coalsece

例1：  
在下图中删除了 8 这个 value 之后 leaf node P5 只剩下一个元素，此时需要选择进行 coalsece 或是 redistribue。首先选择一个 sibling node，选择左侧或右侧都可以，这里为了实现的简便，首选左侧 sibling node。P5 和 P4 合并之后需要从父节点即 P7 中删除指向 P5 的元素，这样又导致了 internal node P7 不足半满。类似地选择 P3 与 P7 进行合并。可以看到合并 P3 与 P7 的过程中从 P8 中删除了指向 P7 的指针，为了维持 internal node `n_val == n_key + 1` 的结构，还需要将 key 5 加入到 P3 中。

![tree-coalsece-2.png](https://i.imgur.com/Z9I5osf.png)
![tree-coalsece-3.png](https://i.imgur.com/9QypOKa.png)

例2：  
与例1的不同之处在与删除的是父节点的第一个子节点中的元素 1 ，由于 P3 没有 left sibling，必须选择 right sibling。由于整个过程与上个例子相似，在实现中对 P3 P7 节点变量进行 swap 即可复用上一个例子的逻辑。

![tree-coalsece-0.png](https://i.imgur.com/zydTp11.png)
![tree-coalsece-1.png](https://i.imgur.com/cOsdezK.png)

### Redistribute

例3：  
删除 key 17 18 之后 leaf node P5 不足半满，选中 left sibling P6进行操作， 而此时 P6 有 4 个元素，4 + 1 >= 5 需要 redistribute。首先从 P6 的末尾移动 key value 15 到 P5 的开头，为了维持树的结构还需要将父节点 P7 中的 key 16 替换为 key 15。  
![tree-redistribute-0.png](https://i.imgur.com/lAANP5y.png)
![tree-redistribute-1.png](https://i.imgur.com/BXcnyep.png)

例4：  
和例3类似，不同之处在与 P4 是父节点的第一个子节点， 所以选择了 right sibling，将 right sibling 开头的 key value 移动到 P4 的末尾。
![tree-redistribute-2.png](https://i.imgur.com/VYwoYTa.png)
![tree-redistribute-3.png](https://i.imgur.com/LmSpdUd.png)


例5：

删除 key 4 会引发了 P1 与 P2 coalsece，此时 internal node P3 中只剩下一个 value，需要和 P7 进行 redistribute。首先将 P7 开头的的 value 移动到 P3 末尾，相对应的 key 则是父节点中的 key 5，父节点中原本 key 5 的位置则由 P7 的首个 key 7 取代。internal node left sibling redistribute 过程相似就不再赘述。 
![tree-redistribute-4.png](https://i.imgur.com/7NoRq2J.png)
![tree-redistribute-5.png](https://i.imgur.com/eL04S3y.png)


### Adjust Root

例6：  
删除 key 4 之后由于 coalsece root 此时 root P3 只有一个子节点 P1，需要做的操作是将 root P3 删除，将子节点 P1 提升为新的 root 节点。
![tree-adjust-root-0.png](https://i.imgur.com/iH8ihvP.png)
![tree-adjust-root-1.png](https://i.imgur.com/tllT9jx.png)
