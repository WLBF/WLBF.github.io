---
title: Kafka
date: 2021-07-18 17:25:43
tags: [distributed-system, kafka]
---

看完 zookeeper 正好再看看 kafka。kafka 2.8.0 弃用 zookeeper 进行协调，转而开始使用 raft。本篇内容完全基于 kafka 论文，可能会有一些过时的信息。

## Kafka Architecture and Design Principles

<div align="center">
    <img src="https://i.imgur.com/ZyEshQA.png" width="60%" height="60%">
</div>

相同类型的消息流称为 topic。producer 会向 topic 发布消息。发布的消息会被存储在 broker 中。consumer 会从 broker 订阅一个或多个 topic，通过从 broker 拉取数据来消费消息。一个 kafka 集群中会有多个 broker。为了均衡负载一个 topic 会被划分成多个 partition，每个 broker 会存储一个或多个 partition。

Sample producer code:
```
producer = new Producer(…);
message = new Message(“test message str”.getBytes());
set = new MessageSet(message);
producer.send(“topic1”, set);
```

Sample consumer code: 
```
streams[] = Consumer.createMessageStreams(“topic1”, 1)
for (message : streams[0]) {
  bytes = message.payload();
  // do something with the bytes
}
```



### Efficiency on a Single Partition

#### Simple storage:

<div align="center">
    <img src="https://i.imgur.com/QNUdQMl.png" width="60%" height="60%">
</div>

kafka 的存储结构十分简单。每一个 partition 对应一个 logical log。一个 log 由多个大小近似（1GB）的 segment file 组成。每次 producer 发布消息，broker 只是简单的将消息追加在最后一个 log 的最后一个 segment file 末尾。为了提升性能 segment file 不会每条信息都 flush 磁盘，而是累积一定数量的消息或达到一定的时间间隔才会 flush 磁盘。一条消息只有被 flush 到磁盘上之后才对 consumer 可见。

不同于其他消息系统，kafka 中的消息并没有显式的 message id，每条消息都是通过 log 的 logical offset 来寻址的，message offset 即 message id。这样避免了使用复杂的索引结构来关联 message id 和消息真正的存储地址。 message offset 是自增的但不是连续的。给当前 message offset 加上当前消息的长度即可得到下一个消息的 message offset。

consumer 从 partition 中顺序地消费消息。如果 consumer 消费到某个 offset，代表这个 consumer 已经消费了这个 offset 之前所有的消息。consumer 每次会异步地从 broker 批量拉取消息，consumer 向 broker 发送的请求中包括 offset 和准备接收的消息数量，broker 收到请求后会通过 offset 列表查询消息的地址，之后返回给 consuemr。出于性能考虑 producer 和 consumer 在实现上都不会单条发送收取消息，而是累积一定数量，大约几百 kb再进行处理。

#### Efficient transfer:

kafka 没有另外实现磁盘的 buffer cache，而是直接使用了操作系统的 buffer cache。这样做在 broker 重启之后可以直接通过 cache 获益，同时也减小了 vm-base 语言 GC 的影响。在测试中生产和消费的性能和数据大小呈线性关系。

consumer 在通过网络访问 broker 时，broker 要从本地读取文件通过网络发送出去。这里 kafka 使用了 zero-copy 优化，通过使用 sendfile API 减小了 system call 和 copy 的次数。 

#### Stateless broker:

在 kafka 中 broker 是无状态的，并不维护 partition 的 offset 信息。offset 信息由 consumer 自己来维护。这样大大简化了 broker 的实现，但也带来了消息删除的问题。即 broker 并不知道哪条消息已经被消费过，可以删除。kafka 通过设置一个保存时间来解决这个问题，消息存储超过一定时间后会被自动删除，一般是 7 天。

这种设计还有另一个优势，consumer 可以故意 rewind back 自己的 offset，来重复消费相同的消息。这个功能有时十分有用，例如：一个 consumer 出现 error，consumer 可以在 error 修复后重放之前的消息。

### Distributed Coordination

每个 producer 可以随机或通过特定方式选择 partition 发送 消息

在 kafka 中存在 *consumer groups* 概念，一个 consumer groups 由一个或多个订阅了相同 topics 的 consumer 组成。topic 中的一个消息只会被发送给 consumer groups 中的一个 consumer。不同 consumer groups 之间没有关联，不需要进行协调。同一个 consumer groups 中的 consumers 可能是独立的进程或分布在不同机器上。协调机制的目标是将 brokers 中存储的消息尽量平均分配给每一个 consumer，同时不带来过大的开销。协调机制由两部分组成：

**P1:** 无论何时，一个 partition 中的所有消息在每一个 consumer group 中只会被一个 consumer 消费。这样避免了同一个 consumer group 中不同 consumer 之间的协调。因此要求每个 topic 的 partition 数量要大于每个 consumer group 中 cousumer 的数量。

**P2:** 使用 zookeeper 来进行协调，主要用来实现以下任务：

1. 监测 broker 和 consumer 的新增和删除。
2. 当 1 中时间发生时，触发每个 consumer 的 rebalance 进程。
3. 记录消费关系和每个 partition 的 offset。

具体来说，broker 或 consumer 启动时会将自己的信息加入到 broker registry 和 consumer registry 中。 broker 信息包括自身的地址端口和存储的 topic 和 partition 集合。consumer 信息包括自身所属的 consumer group 和订阅的 topic 集合。一个 consumer group 关联一个 ownership registry 和一个 offset registry。ownership registry 每一个子节点代表一个该 consumer group 订阅的 partition，子节点的值即为当前在消费这个 partition 的 consumer id。offset registry 下则存储了每一个 partition 的最后一条被消费记录的 offset。

broker registry, consumer registry 和 ownership registry 下的节点都是 ephemeral 的。如果一个 broker 崩溃，那么 broker registry 中的对应节点就会消失。如果一个 consumer 崩溃那么 consumer registry 中的节点和 ownership registry 中所有相关 partition 节点都会消失。每一个 consumer 还会同时 watch broker registry 和 consumer registry 如果，broker 集合或 consumer group 发生了改变，那么 consumer 就会收到通知。

consumer 初始化或收到了 broker/consumer 变化通知的时候，consumer 会进行 rebalance 来确定当前自己应该消费哪一个 partition：

```
Algorithm 1: rebalance process for consumer Ci in group G
For each topic T that Ci subscribes to {
  remove partitions owned by Ci from the ownership registry
  read the broker and the consumer registries from Zookeeper
  compute PT = partitions available in all brokers under topic T
  compute CT = all consumers in G that subscribe to topic T
  sort PT and CT
  let j be the index position of Ci in CT and let N = |PT|/|CT|
  assign partitions from j*N to (j+1)*N - 1 in PT to consumer Ci
  for each assigned partition p {
    set the owner of p to Ci in the ownership registry
    let Op = the offset of partition p stored in the offset registry
    invoke a thread to pull data in partition p from offset Op
 }
}
```

consumer 首先从 consumer/broker registry 读取 topic T 的 partition 列表 PT 和订阅 topic T 的 consumer 列表 CT。将 PT 按照 CT 的数量平均划分成不同的 chunk，每一个 consumer 根据自己在 CT 中的位置确定地选取一个 chunk。随后 consumer 会向 ownership registry 中跟新信息，并从 offset registry 读取 partition 的 offset，开始从选定的 partition 消费消息。

一个 consumer group 中可能有多个 consumer，rebalance 时可能会出现不同的 consumer 尝试消费同一个 partition 的情况。如果出现冲的话 正在 rebalance 的 consumer 会放弃所有 partition 等待一定时间之后再尝试 rebalance。

创建新 consumer group 时缺少 offset 信息。这种情况下，consumer 会根据配置使用 partition 最大或最小的 offset。 访问 broker 的 API 可以获取 partition 的最大最小 offset 信息。

### Delivery Guarantees

kafka 只提供 at-least-once 送达。大部分时候消息在 consumer group 中只会发送一次，但可能出现重复消息的情况。例如 consumer 在更新 offset 之前崩溃，后续恢复的 consumer 会重复消费之前的消息。这要求消费端具有去重能力。

kafka 只能保证同一个 partition 中的消息是有序的，并不能确保不同 partition 中消息的顺序。

kafka 会对消息做 CRC 检查，来清除 corrupted message。

如果一个 broker 下线那么这个 broker 存储的消息将全部无法访问，如果 broker 存储的文件损坏，这个 broker 将会永久丢失数据。