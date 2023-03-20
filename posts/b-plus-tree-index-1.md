# B Plus Tree Index 1
<!-- ---
title: B Plus Tree Index 1
date: 2021-05-09 05:23:34
tags: [database, cmu-15445]
--- -->

CMU-15445 课程的 project 2 是完整实现一个支持并发的 B+ Tree Index。

## B Plus Tree

A B+Tree is a self-balancing tree data structure that keeps data sorted and allows searches, sequential access, insertion, and deletions in O(log(n)). It is optimized for disk-oriented DBMS’s that read/write large blocks of data.

<div align="center">
    <img src="https://i.imgur.com/HjYlZc7.png" width="70%" height="70%">
</div>

Formally, a B+Tree is an M-way search tree with the following properties:

* It is perfectly balanced (i.e., every leaf node is at the same depth).
* Every inner node other than the root is at least half full (M/2 − 1 <= num of keys <= M − 1).
* Every inner node with k keys has k+1 non-null children.

Every node in a B+Tree contains an array of key/value pairs. The keys in these pairs are derived from the attribute(s) that the index is based on. The values will differ based on whether a node is an inner node or a leaf node. For inner nodes, the value array will contain pointers to other nodes. Two approaches for leaf node values are record IDs and tuple data. Record IDs refer to a pointer to the location of the tuple. Leaf nodes that have tuple data store the the actual contents of the tuple in each node.  
Arrays at every node are (almost) sorted by the keys

## Selection Conditions
Because B+Trees are in sorted order, look ups have fast traversal and also do not require the entire key. The
DBMS can use a B+Tree index if the query provides any of the attributes of the search key. This differs
from a hash index, which requires all attributes in the search key.

## Duplicate Keys
There are two approaches to duplicate keys in a B+Tree.
The first approach is to append record IDs as part of the key. Since each tuple’s record ID is unique, this will ensure that all the keys are identifiable.  
The second approach is to allow leaf nodes to spill into overflow nodes that contain the duplicate keys. Although no redundant information is stored, this approach is more complex to maintain and modify.

## Clustered Indexes
The table is stored in the sort order specified by the primary key, as either heap- or index-organized storage. Since some DBMSs always use a clustered index, they will automatically make a hidden row id primary key if a table doesn’t have an explicit one, but others cannot use them at all.

## Insert

To insert a new entry into a B+Tree, one must traverse down the tree and use the inner nodes to figure out
which leaf node to insert the key into.
1. Find correct leaf `L`.
2. Add new entry into `L` in sorted order:
* If `L` has enough space, the operation is done.
* Otherwise split `L` into two nodes `L` and `L2`. Redistribute entries evenly and copy up middle key. Insert index entry pointing to `L2` into parent of `L`.
3. To split an inner node, redistribute entries evenly, but push up the middle key.

Example:
1. Insert 11 into leaf page 5.  
![tree-insert-00](https://i.imgur.com/pbjMtR2.png)
  
2. Leaf page 5 reach max size.  
![tree-insert-01](https://i.imgur.com/dbbLz4a.png)
  
3. Leaf page 5 split, insert leaf page 6 to root page, root page reach max size.  
![tree-insert-02](https://i.imgur.com/mvExwTB.png)
  
4. Root page split and populate new root page 8.  
![tree-insert-03](https://i.imgur.com/vjiTTdG.png)
