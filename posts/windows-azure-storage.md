# Windows Azure Storage

## Introduction

WAS 支持三种形式的存储 Blobs(user files), Tables(structured storage), Queues(message delivery). WAS 有几个关键特性：

* **Strong Consistency**
* **Global and Scalable Namespace/Storage**
* **Disaster Recovery**
* **Multi-tenancy and Cost of Storage**

## Global Partitioned Namespace

WAS 设计的一个关键目标是给用户提供一个全局的 namespace 让用户能够获得任意容量。为了实现这一目标 namespace 由三部分组成：account name, partition name, object name. 数据 URL 有如下形式:

```
# <service>specifies the service type, which can be blob, table, or queue
http(s)://AccountName.<service>.core.windows.net/PartitionName/ObjectName
```

* Account Name - 用户选用的账户名
* Partition Name - 数据在集群中的存储位置
* Obejct Name - 在一个 Partition 中存储对象的名称

## High Level Architecture

### Windows Azure Cloud Platform
Fabric Controller 负责 Windows Azure Cloud 资源的分配管理，提供了包括 node 启停，网络配置，健康检查，服务启停等功能（看起来是个类似 k8s 的系统）。WAS 也像其他服务一样运行在 Fabric Controller 上。WAS 还可以从 Fabric Controller 获得网络拓扑，集群布局，硬件等信息。WAS 本身负责在存储介质之间复制和移动数据，并为访问存储集群的流量提供负载均衡。

如下图所示 WAS 由 Storage Stamp 和 Location Service 组成

![pic-1](https://i.imgur.com/LziX4mb.png)

### WAS Architectural Components 

* **Storage Stamps** - 一个由多个机架的存储节点组成的集群。 
* **Location Service (LS)** - 管理所有 stamps 和 account namespace 以实现 stamps 之间的负载均衡和灾备。

### Three Layers within a Storage Stamp

* **Stream Layer**
* **Partition Layer**
* **Front-End (FE) layer**

### Two Replication Engines 

* **Intra-Stamp Replication (stream layer)** - stamp 内部同步复制，在写请求的 critical path 上，维持副本数量确保数据持久性，完全由 stream layer 实现。
* **Inter-Stamp Replication (partition layer)** - stamp 之间异步复制，异地数据备份恢复。

## Stream Layer

Stream layer 给 partition layer 提供了 stream 接口，partition layer 能够对 stream 进行 open, close, delete, rename, rename, read, append to 等操作。一个 stream 由一系列 extent pointers 组成，一个 extent 由一系列 block 连接而成。

![pic-2](https://i.imgur.com/pYZE4ar.png)

**Block** - 最小数据读写单元，blocks 大小可以不相同。stream layer 每次读取 block 会验证该 block 的 checksum。整个系统的全部 block 也会定期进行 checksum 验证来确保数据完整性。  

**Extent** - Extent 是 stream layer 中的副本单元。每一个 extent 在 stamp 中有三个副本。Partition layer 使用的 Extent 目标大小是 1GB，在存储小 object 时，partition layer 会向同一个 extent 甚至同一个 block 中写入许多 object 的数据。大 object 则会被切分写入多个 extent 中。Partiton layer 记录了 object 的存储索引。

**Streams** - Stream 由一系列 extent pointers 组成，每个 stream 在 stream layer 中有自己的名称。从 partition layer 看来 stream 像是一个巨大的文件。Stream 的 metadata 由 Stream Manager(SM) 来维护。一个新 stream 可以由其他 stream 中的 extents 来组成。stream 是 append only 的，只有 stream 中最后一个 block 能够被 append。

### Stream Manager and Extent Nodes

![pic-3](https://i.imgur.com/iobUe2C.png)

**Stream Manager (SM)** - SM 记录了 stream 的名字，extents 构成，和 extents 在 Extent Nodes(EN) 上的分布。SM 是一个标准 paxos 集群，不在请求的 critical path 上。SM 负责：

* 维护所有 stream 和 extent 的状态
* 监控 EN 的健康状况
* 创建和分配 extent 到 EN
* 当出现硬件失效或不可用时，lazy re-replication extent 副本
* GC 没有 stream 使用的 extent
* 根据 stream policy 安排 extent 数据的 erasure coding

**Extent Nodes (EN)** - EN 存储了所有 SM 分配给自己的 extent 副本。EN 只有在执行 copy 任务时会和其他 EN 通信。

### Append Operation and Sealed Extent

Extent 到达 (partition layer) 指定的目标大小之后会被 seal。seal 之后的 extent 不可变，无法继续 append，会有新 extent 来接替原来的 extent。stream layer 会对 sealed extent 进行 esure coding 等操作。

### Stream Layer Intra-Stamp Replication

stream layer 和 partition layer 共同保证了 object transaction 层面上的强一致性。partition layer 依赖 stream layer 提供的保证：

1. 当 partition layer 收到写请求 ack，stream layer 确保所有副本内容一致。
2. extent seal 之后从任意副本读到内容一致。

#### Replication Flow  

#### Sealing

#### Interaction with Partition Layer

### Erasure Coding Sealed Extents

### Read Load-Balancing

### Spindle Anti-Starvation

### Durability and Journaling

为了优化三副本的性能，每一个 EN 会有一个 SSD 作为 journal drive。当 partition layer 进行 append 的时候写数据会发给 primary EN 然后并行发给两个 secondaries EN。每个 EN 处理写请求的时候会 (a) 将写请求加入 journal drive (b) 写入数据到 EN 上的目标磁盘，当以上任意一个操作成功，写请求就可以返回成功。如果 journal 先完成了后续读取请求要暂时从 memory cache 中读取，直到数据真正被写入磁盘。

## Partition Layer

Partiton layer 提供了：

* 不同类型 object 存储数据模型 
* 提供处理不同类型 object 的逻辑和语义
* object 的巨大命名空间
* object 访问负载均衡
* object 访问顺序 transaction 和强一致性

### Partition Layer Data Model

Partition layer 提供了一个重要数据结构 Object Table(OT)。OT 是一张尺寸巨大的表，被动态分割成 RangePartition 分布在 stamp 中的 partition server 上。

* Account Table - 存储 metadata 和配置。
* Blob Table - 存储所有 account 的 blob object。
* Entity Table - 用于 Windows Azure Table data abstraction。
* Message Table - 用于存储所有 account 的 queue message。
* Schema Table - 记录所有 OT 的 schema。

### Supported Data Types and Operations

OT 支持 query/get, insert, update, delete 操作，还支持同一 PartitionName 的 batch transaction，OT transaction 还提供 snapshot isolation 允许读写并行。

### Partition Layer Architecture

**Partition Manager (PM)** - 负责将 OT 切分成多个 RangePartition, 维护 RangePartition 和 Partition Server 的关系。对应关系数据存储在 Partiton Map Table 中。每个 stamp 中有多个 PM 实例通过 lock service lease 进行热备。  
**Partition Server (PS)** - 服务 RangePartition 请求，通过 lease 保证同一个 RangePartition 只有一个 PS提供服务。一个 PS 可以服务多个 OT 的 RangePartition。 
**Lock Service** - Paxos 服务用于实现分布式 lease。

![pic-4](https://i.imgur.com/VT0Uc6v.png)

### RangePartition Data Structures

#### Persistent Data Structure 

RangePartition 使用 Log-Structured Merge-Tree 结构存储持久化数据，一个 RangePartition 拥有以下 stream：

**Metadata Stream** - RangePartition 的 root stream，包含了 commit log stream 和 data stream 的名称，和两个 stream 的 offset。PS 可以通过 metadata stream 来加载 RangePartition。 

**Commit Log Stream** - 存储了从上一次 checkpoint 到现在的 insert, update, delete 操作。 

**Row Data Stream** - 存储 checkpoint 和 index 数据。

**Blob Data Stream** - 只有 Blob Table 使用，用于存储 blob data。

只有 Blob Table 同时使用 Row Data Stream 和 Blob Data Stream，Row Data Stream 用于存储 blob data index。

![pic-5](https://i.imgur.com/HcF3veK.png)

#### In-Memory Data Structures

**Memory Table** - 包含最近未 checkpoint 的改动，优先被查询。

**Index Cache** - 缓存 row data stream 的 checkpoint indexes。

**Row Data Cache** - 缓存 row data stream 的 checkpoint pages。

**Bloom Filters** - 过滤查询。

### Data Flow

### RangePartition Load Balancing

#### Load Balance

当识别到 PS load 过大时，将一个或多个 RangePartition 重新安置在低负载 PS 上。

#### Split

当识别到某个 RangePartition load 过大时，拆分该 RangePartition 之后重新安置在其他 PS 上。

#### Merge

当 RangePartition 第负载时合并 RangePartitions，将系统中 RangePartition 数量控制在一定范围内。
