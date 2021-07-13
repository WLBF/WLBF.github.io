---
title: Bloom Filter
date: 2021-06-09 21:44:24
tags: [algorithm]
---

## 简介

[Bloom Filter](https://en.wikipedia.org/wiki/Bloom_filter#) 算是原理很简单但应用很广泛的一个算法，用途是快速判断一个元素是否存在于集合中。存在假阳性 (false postive) 现象，但不会出现假阴性 (false negative) 现象，即算法给出存在的元素有一定概率不存在，如果算法给出不存在的元素则一定不存在。  
简单描述： 存在一个 `m` 位的 bit 数组，初始状态下所有 bit 都设置位 0。同时有 `k` 个不同的 hash 函数。
* **添加：**使用 `k` 个 hash 函数对新元素进行计算，得到 `k` 个不同的位置，并把 bit 数组中的这些位置设为 1。
* **搜索：**使用 `k` 个 hash 函数对新元素进行计算，得到 `k` 个不同的位置，检查 bit 数组中这些位置是否全部为 1，如果符合则返回 true。

<div align="center">
    <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/a/ac/Bloom_filter.svg/974px-Bloom_filter.svg.png" width="70%" height="70%">
</div>

## 参数选择

对于给定 `m` 位 bit 数组， 元素总数为 `n` ，使假阳性概率最低的 hash 函数数量 `k = m/n*ln2`。在 [go-zero](https://github.com/tal-tech/go-zero) 的实现中设置 `k` 为固定值 14，具体的假阳性概率可以参考 [Bloom Filters - the math](http://pages.cs.wisc.edu/~cao/papers/summary-cache/node8.html)

## RedisBloom

redis 4.0 之后引入了 module 机制，可以很轻松地使用 RedisBloom module 实现 bloom filter 功能：  
[https://github.com/RedisBloom/RedisBloom/](https://github.com/RedisBloom/RedisBloom/)

## 手动实现

如果基于某种原因，比如 GCP 不支持，不能直接使用 redis module，可以手动实现基于 redis 的 bloom filter。参考 [go-zero](https://github.com/tal-tech/go-zero) 的实现（省略了一些代码）：


```golang
const (
	// for detailed error rate table, see http://pages.cs.wisc.edu/~cao/papers/summary-cache/node8.html
	// maps as k in the error rate table
	maps      = 14
	setScript = `
for _, offset in ipairs(ARGV) do
	redis.call("setbit", KEYS[1], offset, 1)
end
`
	testScript = `
for _, offset in ipairs(ARGV) do
	if tonumber(redis.call("getbit", KEYS[1], offset)) == 0 then
		return false
	end
end
return true
`
)
```
redis 中的 bit array 操作是通过 lua script 来实现的。

```golang
// New create a Filter, store is the backed redis, key is the key for the bloom filter,
// bits is how many bits will be used, maps is how many hashes for each addition.
// best practices:
// elements - means how many actual elements
// when maps = 14, formula: 0.7*(bits/maps), bits = 20*elements, the error rate is 0.000067 < 1e-4
// for detailed error rate table, see http://pages.cs.wisc.edu/~cao/papers/summary-cache/node8.html
func New(store *redis.Redis, key string, bits uint) *Filter {
	return &Filter{
		bits:   bits,
		bitSet: newRedisBitSet(store, key, bits),
	}
}

func (f *Filter) getLocations(data []byte) []uint {
	locations := make([]uint, maps)
	for i := uint(0); i < maps; i++ {
		hashValue := hash.Hash(append(data, byte(i)))
		locations[i] = uint(hashValue % uint64(f.bits))
	}

	return locations
}

func (r *redisBitSet) buildOffsetArgs(offsets []uint) ([]string, error) {
	var args []string

	for _, offset := range offsets {
		if offset >= r.bits {
			return nil, ErrTooLargeOffset
		}

		args = append(args, strconv.FormatUint(uint64(offset), 10))
	}

	return args, nil
}

func (r *redisBitSet) check(offsets []uint) (bool, error) {
	args, err := r.buildOffsetArgs(offsets)
	if err != nil {
		return false, err
	}

	resp, err := r.store.Eval(testScript, []string{r.key}, args)
	if err == redis.Nil {
		return false, nil
	} else if err != nil {
		return false, err
	}

	exists, ok := resp.(int64)
	if !ok {
		return false, nil
	}

	return exists == 1, nil
}

func (r *redisBitSet) set(offsets []uint) error {
	args, err := r.buildOffsetArgs(offsets)
	if err != nil {
		return err
	}

	_, err = r.store.Eval(setScript, []string{r.key}, args)
	if err == redis.Nil {
		return nil
	}

	return err
}
```

可以观察到 `getLocation` 函数中的 `k` 个不同 hash 函数是通过同样的 hash 函数每次循环在 `data` 末尾增加一个确定的字节来实现的，这里选择了 `murmur3` 作为 hash 函数。

```golang
func Hash(data []byte) uint64 {
	return murmur3.Sum64(data)
}
```

几种常见的非密码学 hash 函数：
* CRC-64(1975) - Used in networking for error detection.
* MurmurHash(2008) - Designed to a fast, general purpose hash function.
* Google CityHash(2011) - Designed to be faster for short keys (<64 bytes).
* Facebook XXHash(2012) - From the creator of zstd compression.
* Google FarmHash(2014) - Newer version of CityHash with better collision rates.