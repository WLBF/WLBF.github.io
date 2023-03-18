---
title: Nodeos Elasticsearch Plugin
date: 2018-09-24 22:56:12
tags: eos
---
最近两个月的工作成果：[https://github.com/EOSLaoMao/elasticsearch_plugin](https://github.com/EOSLaoMao/elasticsearch_plugin)

## First Implemention

一开始是完全照抄 [mongo_db_plugin](https://github.com/EOSIO/eos/tree/master/plugins/mongo_db_plugin)，分成 8 种类型的数据：

```text
account_controls
accounts
action_traces
block_states
blocks
pub_keys
transaction_traces
transactions
```

期间碰到了 Elasticsearch 6.x breaking change 弃用 `_type` 的坑， 详见：
[https://www.elastic.co/guide/en/elasticsearch/reference/master/removal-of-types.html](https://www.elastic.co/guide/en/elasticsearch/reference/master/removal-of-types.html)

写完了之后发现速度惨不忍睹， hard replay 前 3000 blocks 只有 1.3 block/s 的速度。很明显直接套用 `mongo_db_plugin` 的逻辑和数据结构用在 Elasticsearch 上是不合适的，需要一些修改。

## Optimization

第一个改动是 `accounts` 的数据结构， Elasitcsearch 用的 http 和 MongoDB 自己的协议比起来性能上还是有差距的，为了尽量减少请求次数，把 `accounts`，`account_controls`，`pub_keys` 合并到一条记录里去，并且使用 account_name 作为 `_id` 免去了更新前先查询的操作，合并之后数据结构如下：

```json
GET accounts/_doc/6138663577826885632
{
    "name": "eosio",
    "createAt": "1537873749097",
    "pub_keys": [
      {
        "permission": "owner",
        "key": "eosio.prods"
      }
    ],
    "account_controls": [
      {
        "name": "eosio.prods",
        "permission": "owner"
      }
    ],
    "updateAt": "1537863826973"
}
```

[Elasticsearch Update API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-update.html) 支持通过 [Painless Script](https://www.elastic.co/guide/en/elasticsearch/painless/6.4/painless-lang-spec.html) 操作，可以实现一些灵活的功能。例如更新上面的 document 可以通过如下请求：

```json
POST accounts/_doc/6138663577826885632/_update
{
  "script": {
    "lang":"painless",
    "source":"""
    ctx._source.pub_keys.removeIf(item -> item.permission == params.permission);
    ctx._source.pub_keys.addAll(params.pub_keys);
    ctx._source.account_controls.removeIf(item -> item.permission == params.permission);
    ctx._source.account_controls.addAll(params.account_controls);
    ctx._source.updateAt = params.updateAt;
    """,
    "params": {
      "permission": "owner",
      "pub_keys": [
        {"permission":"owner","key":"eosio.prods"}  
      ],
      "account_controls":[
        {"permission":"owner","name":"eosio.prods"}
      ],
      "updateAt":"1537863826973"
    }
  }
}
```

----------------
整个插件的核心是下面 4 个函数：

```text
_process_applied_transaction
_process_accepted_transaction
_process_accepted_block
_process_irreversible_block
```

其中最耗时的是 `_process_applied_transaction` 原因是需要递归解析所有的 `action` 并且创建以及更新 `accounts` 信息，上面已经对 `accounts` 做出了一些修改。其他部分我没有想到什么好办法，唯一想到能做的是把递归实现改栈实现。我猜测即使改成手动用栈来实现也没有什么大的提升，理由是递归的深度不高，最多也不过是前几千个 block 中有打包了大于 100 个 `action` 的 `transaction`, 而且原本的递归是可以被尾递归优化掉的, 不清楚编译器有没有优化。为了心理安慰还是改写成了栈实现：

```c++
std::stack<std::reference_wrapper<chain::action_trace>> stack;
stack.emplace(atrace);

while ( !stack.empty() )
{
    auto &atrace = stack.top();
    stack.pop();
    write_atraces |= add_action_trace( bulk_action_traces, atrace, executed, now );
    auto &inline_traces = atrace.get().inline_traces;
    for( auto it = inline_traces.rbegin(); it != inline_traces.rend(); ++it ) {
        stack.emplace(*it);
    }
}
```

----------------

更新 `blocks`，`transactions` 数据的时候可能会出现数据竞争的问题，Elasticsearch 有一套基于 [OCC](https://en.wikipedia.org/wiki/Optimistic_concurrency_control) 的 [version](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-index_.html#index-versioning) 机制来解决这个问题，需要注意的是首次创建 document 即 `_version=1` 的 document 是通过 [_create](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-index_.html#operation-type) 来实现的。一个相关的 issue：[https://github.com/elastic/elasticsearch/issues/20702](https://github.com/elastic/elasticsearch/issues/20702)

[Elasticsearch Versioning Support](https://www.elastic.co/blog/elasticsearch-versioning-support)

----------------

经过上面的改造，速度有了比较明显的提升，但是对比 mongo_db_plugin 还是有些差距。

[Benchmark](https://github.com/EOSLaoMao/elasticsearch_plugin/blob/master/benchmark.md)