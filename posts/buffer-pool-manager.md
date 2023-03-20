# Buffer Pool Manager
<!-- ---
title: Buffer Pool Manager
date: 2021-04-29 20:15:17
tags: [database, cmu-15445]
--- -->
开始学习 CMU-15445，别人的优秀笔记：[https://zhenghe.gitbook.io/open-courses/](https://zhenghe.gitbook.io/open-courses/)


## 实现

CMU-15445 数据库课程 project 1 需要给 bustub 实现一个 lru buffer pool manager。 和之前 xv6 中的 buffer cache 功能类似，属于数据库系统的最底层抽象。由于数据库需要精细地控制 IO 操作，所以一般的数据库系统都会通过系统调用的 `O_DIRECT` flag 来绕过操作系统本身的 buffer cache。代码中已经给了大致的框架，可以看到相比于之前 xv6 中原始的实现，buffer pool manager 有了更巧妙的抽象，内存淘汰策略的逻辑抽象成了 replacer 类，替换淘汰策略只需要替换不同的 replacer 子类，在这里实现的还是 lru_replacer。page 和 frame 也做出了清晰抽象, page 代表一块磁盘上的数据，frame 则是在内存中缓存 page 的槽位，buffer pool manager 初始化的时候指定了 frame 的数量。

```c++
class BufferPoolManager {
 public:
  enum class CallbackType { BEFORE, AFTER };
  using bufferpool_callback_fn = void (*)(enum CallbackType, const page_id_t page_id);

  /**
   * Creates a new BufferPoolManager.
   * @param pool_size the size of the buffer pool
   * @param disk_manager the disk manager
   * @param log_manager the log manager (for testing only: nullptr = disable logging)
   */
  BufferPoolManager(size_t pool_size, DiskManager *disk_manager, LogManager *log_manager = nullptr);

  /**
   * Destroys an existing BufferPoolManager.
   */
  ~BufferPoolManager();

  /** @return pointer to all the pages in the buffer pool */
  Page *GetPages() { return pages_; }

  /** @return size of the buffer pool */
  size_t GetPoolSize() { return pool_size_; }

 protected:

  /**
   * Fetch the requested page from the buffer pool.
   * @param page_id id of page to be fetched
   * @return the requested page
   */
  Page *FetchPageImpl(page_id_t page_id);

  /**
   * Unpin the target page from the buffer pool.
   * @param page_id id of page to be unpinned
   * @param is_dirty true if the page should be marked as dirty, false otherwise
   * @return false if the page pin count is <= 0 before this call, true otherwise
   */
  bool UnpinPageImpl(page_id_t page_id, bool is_dirty);

  /**
   * Flushes the target page to disk.
   * @param page_id id of page to be flushed, cannot be INVALID_PAGE_ID
   * @return false if the page could not be found in the page table, true otherwise
   */
  bool FlushPageImpl(page_id_t page_id);

  /**
   * Creates a new page in the buffer pool.
   * @param[out] page_id id of created page
   * @return nullptr if no new pages could be created, otherwise pointer to new page
   */
  Page *NewPageImpl(page_id_t *page_id);

  /**
   * Deletes a page from the buffer pool.
   * @param page_id id of page to be deleted
   * @return false if the page exists but could not be deleted, true if the page didn't exist or deletion succeeded
   */
  bool DeletePageImpl(page_id_t page_id);

  /**
   * Flushes all the pages in the buffer pool to disk.
   */
  void FlushAllPagesImpl();

  /** Number of pages in the buffer pool. */
  size_t pool_size_;
  /** Array of buffer pool pages. */
  Page *pages_;
  /** Pointer to the disk manager. */
  DiskManager *disk_manager_ __attribute__((__unused__));
  /** Pointer to the log manager. */
  LogManager *log_manager_ __attribute__((__unused__));
  /** Page table for keeping track of buffer pool pages. */
  std::unordered_map<page_id_t, frame_id_t> page_table_;
  /** Replacer to find unpinned pages for replacement. */
  Replacer *replacer_;
  /** List of free pages. */
  std::list<frame_id_t> free_list_;
  /** This latch protects shared data structures. We recommend updating this comment to describe what it protects. */
  std::mutex latch_;
};

```

在操作 buffer pool manager 的过程中，如果一个 frame 中的 page pin count 降至 0，就会调用 Unpin 方法将这个 frame 加入 replacer 中，代表这个 frame 可以被其他 page 替换。如果 replacer 中的某个 frame 的 page pin count 增加，即有人 fetch 这个 page, 那么又会调用 Pin 方法将 frame 从 replacer 中移除。replacer 中的 frame 数量加上 free_list_ 和正在使用中的 frame 的数量即为全部 frame 的数量。下面给出了使用的是哈希表加上链表 lru replacer 的实现，由于这里 frame_id 为 0 开头的连续整数所以使用 vector 当做哈希表使用，vector 中存放的是链表的迭代器，方便在 O(1) 时间内定位 frame 在链表中的位置, 每次新加入的 frame 会放在链表结尾， Victim 方法会从链表头部取出 frame, 这样最旧的 frame 会最先被换出，符合 lru(least recently used) 的逻辑。


```c++
/**
 * LRUReplacer implements the lru replacement policy, which approximates the Least Recently Used policy.
 */
class LRUReplacer : public Replacer {
 public:
  /**
   * Create a new LRUReplacer.
   * @param num_pages the maximum number of pages the LRUReplacer will be required to store
   */
  explicit LRUReplacer(size_t num_pages);

  /**
   * Destroys the LRUReplacer.
   */
  ~LRUReplacer() override;

  bool Victim(frame_id_t *frame_id) override;

  void Pin(frame_id_t frame_id) override;

  void Unpin(frame_id_t frame_id) override;

  size_t Size() override;

 private:
  std::list<frame_id_t> list_;
  std::vector<std::list<frame_id_t>::iterator> table_;
  std::mutex latch_;
};


LRUReplacer::LRUReplacer(size_t num_pages) : table_(num_pages, list_.end()) {}

LRUReplacer::~LRUReplacer() = default;

bool LRUReplacer::Victim(frame_id_t *frame_id) {
  std::lock_guard<std::mutex> guard(latch_);
  if (list_.empty()) {
    return false;
  }

  frame_id_t new_frame_id = list_.front();
  list_.pop_front();
  table_[new_frame_id] = list_.end();

  *frame_id = new_frame_id;
  return true;
}

void LRUReplacer::Pin(frame_id_t frame_id) {
  std::lock_guard<std::mutex> guard(latch_);
  if (table_[frame_id] != list_.end()) {
    list_.erase(table_[frame_id]);
    table_[frame_id] = list_.end();
  }
}

void LRUReplacer::Unpin(frame_id_t frame_id) {
  std::lock_guard<std::mutex> guard(latch_);
  if (table_[frame_id] == list_.end()) {
    list_.emplace_back(frame_id);
    table_[frame_id] = std::prev(list_.end());
  }
}

size_t LRUReplacer::Size() { return list_.size(); }
```

## 优化

数据库中对 buffer pool manager 还可以进行一些优化包括

* Multiple Buffer Pools - 之前 xv6 buffer cache 中已经介绍，通过哈希函数切分 buffer pool 减小锁的竞争以及改善局部性。
* Pre-Fetching - pre fetch 数据进入 buffer pool 增加访问命中率。 
* Scan Sharing - 允许多个 query 共享 cursor 增加访问磁盘的效率。
* Buffer Pool Bypass - 序列扫描数据不会缓存在 buffer pool 中，减小换入换出开销。
