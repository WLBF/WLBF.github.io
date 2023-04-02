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

![pic-1]()

### WAS Architectural Components 

**Storage Stamps** - 一个由多个机架的存储节点组成的集群。  
**Location Service (LS)** – 管理所有 stamps 和 account namespace 以实现 stamps 之间的负载均衡和灾备。

### Three Layers within a Storage Stamp

Stream Layer -
Partition Layer -
Front-End (FE) layer -

### Two Replication Engines 










