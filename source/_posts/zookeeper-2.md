---
title: Zookeeper 2
date: 2021-07-15 00:24:37
tags: [distributed-system]
---

## Examples of primitives

### Counter

使用 update 条件更新实现计数器：

```
x, v = getData("cnt")
if setData("cnt", x + 1, v), exit
goto 1
```

### Configuration Management

使用 zookeeper 进行分布式应用配置管理。最简单的例子：假设配置数据存储在 znode `zc` 中，进程只需要循环调用设置了 watch flag 的 getData 方法即可实现 `zc` 发生改动时，及时获取最新配置。
另一个更复杂的例子：集群中有多个进程，其中一个进程会被选举为 leader，每次被选举为 leader 的进程将会更新多个配置，因此配置更新应当满足：
* 只有当 leader 完成所有配置修改，剩余进程才能观察到，follower 进程不可以使用部分更新的配置。
* 如果 leader 在更新配置的过程中崩溃，follower 进程不可以使用残留的部分更新的配置。

为了满足上述要求，可以设置一个 znode ready，leader 首先将 ready 置为 false，只有在完成所有配置更新之后才会将 ready 设为 true，follower 进程只有观察到 ready 节点为 true，才会去读取配置。
上述解决方案还有一个问题，如果配置在 follower 读取过程中又再次被修改，这种情况下 follower 可能会读到 corrupted 配置。这个问题可以通过 watch flag 来解决，如果 follower 在读取配置过程中再次收到了 ready 改变通知，就放弃本次读取，重启读取流程。


### Rendezvous

很多时候分布式系统中，进程启动并没有特定的顺序。例如要启动一个 master 进程和多个 worker 进程，worker 进程可能先于 master 进程启动，此时就可以通过向 master 和 worker 传递一个 znode path `zr`，master 启动后向 `zr` 写入自己的地址和端口， worker 进程通过 watch `zr`，来获知 master 已经启动以及连接方式和。如果 `zr` 是一个 ephemarl node，那么还可以通过 `zr` 控制 master 和 worker 的生命周期。

### Group Membership

ephemarl 机制还可以用来实现 group membership，根据 session 机制 ephemarl node 反映了创建该 znode 的 member 的状态。使用 znode `zg` 代表集群，每个 member 进程启动时在 `zg`下创建一个名字为 唯一标识符的子节点，唯一标识符可以通过 sequential flag 来分配。member 进程还可以将自己的地址端口等信息写入创建的节点中。
当 member 进程结束或崩溃时，session 被释放，该 member 对应的 znode 也会被自动移除，无需其他操作。
可以通过获取 `zg` 的子节点列表获取集群的信息，如果想要持续监视集群的状态，只需要将 watch flag 设为 true， 循环调用 `getChildren(zg, true)`，每当集群出现成员变动时监视进程就可以收到通知。 


### Simple Locks

使用 zookeeper 来实现分布式锁，最简单的实现是，每个 client 尝试创建一个 path 相同的 ephemeral node `zl`，如果创建成功说明获取到了锁。如果失败则开始 watch `zl`，如果收到了 `zl` 被删除的通知，就再次尝试创建 `zl`。持有锁的 client 主动删除或崩溃都会导致 `zl` 被移除，也就释放了锁。这种实现有两个问题：1. 惊群 2. 无法实现读写锁。


### Simple Locks without Herd Effect

**Lock**

获取锁的过程是，首先在 znode `l` 下创建一个 sequential\|ephemeral znode，之后通过 getChildren 检查是否存在名字小于自己的 znode，如果存在那么就等待小于自己的 znode 被移除，如果没有小于自己的 znode 那么代表着成功获取了锁。

```
n = create(l + “/lock-”, EPHEMERAL|SEQUENTIAL)
C = getChildren(l, false)
if n is lowest znode in C, exit
p = znode in C ordered just before n
if exists(p, true) wait for watch event
goto 2
```

**Unlock**

释放锁只需要主动删除自己创建的 znode

```
delete(n)
```

这种实现可以看成是将获取锁的请求在 zookeeper 中构造成队列，这种实现的优点：

1. 释放锁只会准确地唤醒排列在自己之后的节点，不存在惊群问题。
2. 不需要 client 端进行 polling 或设置 timeouts。
3. 获取锁的请求被顺序存储在 zookeeper 中，方便用户观察锁的竞争度，也可以用来 debug，或是实现死锁检测。

### Read/Write Locks

上一个例子也很容易修改成读写锁。获取读锁过程中在检查子节点列表时，如果自己之前没有写锁，那么就可以判断获取读锁成功。如果有写锁那么等待第一个小于自己的写锁被释放。会存在多个读锁同时等待同一个写锁的情况，这个写锁被移除后，后续的读锁会同时被唤醒，这也正好符合读写锁的特性。

**Write Lock**
```
n = create(l + “/write-”, EPHEMERAL|SEQUENTIAL)
C = getChildren(l, false)
if n is lowest znode in C, exit
p = znode in C ordered just before n
if exists(p, true) wait for event
goto 2
```

**Read Lock**
```
n = create(l + “/read-”, EPHEMERAL|SEQUENTIAL)
C = getChildren(l, false)
if no write znodes lower than n in C, exit
p = write znode in C ordered just before n
if exists(p, true) wait for event
goto 3
```

### Double Barrier

实现分布式进程间的同步。设置 znode `b` 代表 barrier，每个进程在 `b` 下创建子节点来注册 barrier，删除子节点来注销 barrier，表明自己准备好离开。每个都进程可以通过观察 `b` 的子节点数量是否超过 threshold 来判断是否进入，通过 `b` 的所有子节点是否都被删除来判断是否离开 barrier。
