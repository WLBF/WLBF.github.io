---
title: Zookeeper 1
tags: [distributed-system, zookeeper]
date: 2021-07-13 01:21:41
---


拖延了很久，终于读了一遍 zookeeper 的论文。



## Service Overview

<div align="center">
    <img src="https://i.imgur.com/IMBGOi4.png" width="50%" height="50%">
</div>

zookeeper 的数据抽象为多个 data node(znode) 的集合，znode 按照类似文件系统的嵌套 namespace 来组织。client 通过一个 znode 的路径来访问特定的 znode。znode 有两种类型：

**Regular:** Clients manipulate regular znodes by creating and deleting them explicitly;
**Ephemeral:** Clients create such znodes, and they either delete them explicitly, or let the system remove them automatically when the session that creates them terminates (deliberately or due to a failure).

* client 在创建新 znode 时还可以设置一个 *sequential* flag。此时创建的 znode 名字中会带有单调自增的数字后缀。
* 由于 session 机制，client 还支持 watch znode change 功能，这种 watch 功能是一次性的，当 watch 的 znode 第一次发生改变会触发一次通知。如果 session 失效，也会触发通知。


**Session.** server 在收到 client 连接的时候会创建一个 session。server 通过 timeout 确认 client 是否存活，client 在 idle 的状态下会持续发送 heartbeat 来维持自己的 session。同时 client 也会通过 timeout 来判断 server 是否存活。设 session timeout 为 `s` client library 每 `s/3`ms 发从一次 heartbeat，如果 client `2s/3`ms 内收不到回复就会尝试切换到其他 server 上。超时会导致当前 session 被关闭，session 也可以由 client 主动关闭。


## Client API

zookeeper 的关键 API:

**create(path, data, flags):**
Creates a znode with path name `path`, stores `data[]` in it, and returns the name of the new znode. `flags` enables a client to select the type of znode: *regular*, *ephemeral*, and set the *sequential* flag;

**delete(path, version):**
Deletes the znode `path` if that znode is at the expected `version`;

**exists(path, watch):**
Returns true if the znode with path name `path` exists, and returns false otherwise. The `watch` flag enables a client to set a watch on the znode;

**getData(path, watch):**
Returns the data and meta-data, such as version information, associated with the znode. The `watch` flag works in the same way as it does for `exists()`, except that ZooKeeper does not set the watch if the znode does not exist;

**setData(path, data, version):**
Writes `data[]` to znode path if the version number is the current `version` of the znode;

**getChildren(path, watch):**
Returns the set of names of the children of a znode;

**sync(path):**
Waits for all updates pending at the start of the operation to propagate to the server that the client is connected to. The path is currently ignored.

update api 带有 version 参数，用于实现条件更新，如果 version 参数值为 -1 则更新时不做 version 检查。

## ZooKeeper Implementation

<div align="center">
    <img src="https://i.imgur.com/4ZesRIS.png" width="60%" height="60%">
</div>

每个 zookeeper server 都会维护一份完整的数据在内存中，znode 默认最大为 1mb。

zookeeper 的高可用性是通过 replicated state machine 来实现的。使用的协议是 zab（类似 raft，但早于 raft 出现）， zookeeper server 分为 leader 和 follower，只有 leader 会收到 update 操作，通过将 log 复制到各个 follower 来 commit 操作，每个 server 也会周期性生成 snapshot 进行 log GC。

容错机制也和 raft 类似：Zab uses by default simple majority quorums to decide on a proposal, so Zab and thus ZooKeeper can only work if a majority of servers are correct (i.e., with `2f + 1` server we can tolerate `f` failures).

simple majority quorum 的机制也就代表着并不能确保每一个 follower server 数据都是最新的。client read 操作只会从 server 自己的数据中读取，follower read 是有可能读到 stale data 的，这也是 zookeeper 有很高性能的主要原因。


## ZooKeeper Guarantees

**Linearizability**
1. a total order of operations
2. order matches "real time"
3. read operation returns value of last write

线性一致性可以通俗的理解为分布式系统的行为和单机相似，包括操作按一定顺序执行，现实时间中后出现的操作不会早于先出现的操作执行，总是能读到最新的数据。

ZooKeeper has two basic ordering guarantees:
**Linearizable writes:** all requests that update the state of ZooKeeper are serializable and respect precedence;
**FIFO client order:** all requests from a given client are executed in the order that they were sent by the client.

zookeeper 并不提供严格的线性一致性，而是提供了写操作的线性一致性，加上 client 端操作的 FIFO 顺序保证，即同一个 client 可以同时执行多个独立的操作，client 确保这些操作按照 FIFO 的顺序执行。

## Client-Server Interactions

client 操作 FIFO 顺序是通过 zxid 来实现的，zxid 的大小定义了 write 和 read 操作之间的顺序关系，每一个 write 操作会返回一个 zxid，也可以理解成 transaction 在 log 中的 index。每一个 read request 都会携带 zxid，来确保 client 不会读到该 zxid 之前的数据。

<div align="center">
    <img src="https://i.imgur.com/C1OiBqC.png" width="80%" height="80%">
</div>

case1: Client0 执行 write0 操作成功后返回 zxid(3)，但此时 txn3 还没有被复制到 Follower0 上，Client0 此时向 Follower0 执行 read0 操作，由于 Follower0 当前最新的 zxid 小于 read0 操作的 zxid，Follower0 必须一直等待到同步到 txn3 才会返回。
case2: Client0 向 Follower1 执行 read1 zxid(3) 操作，但在此之前其他 server 已经 commit 了更新的 zxid(4) 操作，此时 read1 会直接返回 zxid(3) 的数据，Client0 收到了 stale data。

zookeeper client 在和 server 建立 session 过程中，如果 server 自身的 zxid 小于 client 的 zxid，server 将会拒绝该 client。

对于 stale data 的问题 zookeeper 给出的解决方案是 `sync` 操作，首先执行 sync 操作，随后执行 read 操作，返回的数据一定不早于 sync 执行成功的时间点。按照论文中的描述，sync 执行过程首先是将 sync 记录插入 leader 到 follower（只有发起 sync 的 follower） 的请求复制队列末尾，follower 如果同步到 sync 记录，即代表着 sync 之前所有的数据也都已经同步，此时 read 到的数据不早于发起 sync 操作的时间点。sync 时 follower 在向 leader 插入 sync 记录之前还会先检查 leader 是否合法，如果此时系统没有负载，那么 leader 需要先发起一个 null transaction 并成功 commit 来确保自己还是合法的 leader。

