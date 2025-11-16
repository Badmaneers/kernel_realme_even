// SPDX-License-Identifier: GPL-2.0
/*
 * Compatibility layer for old mbcache API
 *
 * This provides backward compatibility for vendor drivers (e.g., exFAT)
 * that use the old mbcache API with block_device and sector_t parameters.
 *
 * The old API used (bdev, sector) pairs while the new API uses u64 values.
 * This layer wraps the new implementation to support legacy code.
 */

#include <linux/spinlock.h>
#include <linux/slab.h>
#include <linux/list.h>
#include <linux/module.h>
#include <linux/blkdev.h>
#include <linux/hash.h>
#include <linux/mbcache.h>
#include <linux/mbcache_compat.h>

/*
 * We need to access the internal mb_cache structure to iterate keys.
 * This mirrors the structure definition from fs/mbcache.c
 */
struct mb_cache_internal {
	struct hlist_bl_head	*c_hash;
	int			c_bucket_bits;
	unsigned long		c_max_entries;
	spinlock_t		c_list_lock;
	struct list_head	c_list;
	unsigned long		c_entry_count;
	struct shrinker		c_shrink;
	struct work_struct	c_shrink_work;
};

/*
 * Convert (block_device, sector) pair to u64 value for new API
 * We use a simple hash combining bdev pointer and sector
 */
static inline u64 bdev_sector_to_value(struct block_device *bdev, sector_t sector)
{
	return ((u64)(unsigned long)bdev << 32) | (u64)sector;
}

/*
 * mb_cache_entry_alloc_compat - allocate a cache entry (old API)
 * @cache: cache where the entry will be used
 * @mask: gfp mask for allocation
 *
 * Allocates and returns a new cache entry. The entry is not inserted
 * into the cache yet. Use mb_cache_entry_insert_compat() for that.
 */
struct mb_cache_entry *mb_cache_entry_alloc_compat(struct mb_cache *cache,
						   gfp_t mask)
{
	struct mb_cache_entry *entry;

	entry = kzalloc(sizeof(struct mb_cache_entry), mask);
	if (!entry)
		return NULL;

	INIT_LIST_HEAD(&entry->e_list);
	INIT_HLIST_BL_NODE(&entry->e_hash_list);
	atomic_set(&entry->e_refcnt, 1);
	entry->e_flags = 0;
	set_bit(MBE_REUSABLE_B, &entry->e_flags);

	return entry;
}
EXPORT_SYMBOL(mb_cache_entry_alloc_compat);

/*
 * mb_cache_entry_insert_compat - insert entry into cache (old API)
 * @cache: cache to insert into
 * @entry: entry to insert
 * @bdev: block device
 * @block: block number
 * @key: key (usually hash of data)
 *
 * Inserts an allocated entry into the cache. Returns 0 on success,
 * -EBUSY if entry with same key and value already exists.
 */
int mb_cache_entry_insert_compat(struct mb_cache *cache,
				 struct mb_cache_entry *entry,
				 struct block_device *bdev,
				 sector_t block, u32 key)
{
	u64 value = bdev_sector_to_value(bdev, block);
	int ret;

	entry->e_key = key;
	entry->e_value = value;

	ret = mb_cache_entry_create(cache, GFP_NOFS, key, value, true);
	if (ret == 0 || ret == -EBUSY) {
		if (ret == -EBUSY) {
			kfree(entry);
		}
		return ret;
	}

	kfree(entry);
	return ret;
}
EXPORT_SYMBOL(mb_cache_entry_insert_compat);

/*
 * mb_cache_entry_release_compat - release entry reference (old API)
 * @cache: cache the entry belongs to
 * @entry: entry to release
 *
 * Equivalent to mb_cache_entry_put() in new API.
 */
void mb_cache_entry_release_compat(struct mb_cache *cache,
				   struct mb_cache_entry *entry)
{
	mb_cache_entry_put(cache, entry);
}
EXPORT_SYMBOL(mb_cache_entry_release_compat);

/*
 * mb_cache_entry_free_compat - free entry without releasing (old API)
 * @entry: entry to free
 *
 * Only use this if entry was never inserted into cache.
 */
void mb_cache_entry_free_compat(struct mb_cache_entry *entry)
{
	kfree(entry);
}
EXPORT_SYMBOL(mb_cache_entry_free_compat);

/*
 * mb_cache_entry_get_compat - get entry by block device and sector (old API)
 * @cache: cache to search
 * @bdev: block device
 * @block: block number
 *
 * Find and return entry matching the given bdev and block.
 * Returns NULL if not found.
 */
struct mb_cache_entry *mb_cache_entry_get_compat(struct mb_cache *cache,
						 struct block_device *bdev,
						 sector_t block)
{
	struct mb_cache_internal *cache_int = (struct mb_cache_internal *)cache;
	u64 value = bdev_sector_to_value(bdev, block);
	u32 key;
	struct mb_cache_entry *entry;

	/*
	 * For old API compatibility, we need to search by value only.
	 * Since we don't know the key, we'll search through all entries.
	 * This is less efficient but maintains compatibility.
	 */
	for (key = 0; key < (1U << cache_int->c_bucket_bits); key++) {
		entry = mb_cache_entry_get(cache, key, value);
		if (entry)
			return entry;
	}

	return NULL;
}
EXPORT_SYMBOL(mb_cache_entry_get_compat);

/*
 * mb_cache_entry_delete_or_get_compat - delete or get entry (old API)
 * @cache: cache to operate on
 * @bdev: block device
 * @block: block number
 *
 * Remove entry from cache if unused, or return it with a reference if in use.
 * Returns NULL if entry was deleted or not found.
 */
struct mb_cache_entry *mb_cache_entry_delete_or_get_compat(
				struct mb_cache *cache,
				struct block_device *bdev,
				sector_t block)
{
	struct mb_cache_internal *cache_int = (struct mb_cache_internal *)cache;
	u64 value = bdev_sector_to_value(bdev, block);
	u32 key;
	struct mb_cache_entry *entry;

	/*
	 * Search for the entry across all possible keys.
	 * This is a compatibility limitation.
	 */
	for (key = 0; key < (1U << cache_int->c_bucket_bits); key++) {
		entry = mb_cache_entry_delete_or_get(cache, key, value);
		if (entry)
			return entry;
	}

	return NULL;
}
EXPORT_SYMBOL(mb_cache_entry_delete_or_get_compat);

/*
 * mb_cache_entry_wait_unused_compat - wait until entry is unused (old API)
 * @entry: entry to wait on
 *
 * Wait until the entry reference count drops to the minimum (only hash ref).
 */
void mb_cache_entry_wait_unused_compat(struct mb_cache_entry *entry)
{
	mb_cache_entry_wait_unused(entry);
}
EXPORT_SYMBOL(mb_cache_entry_wait_unused_compat);

/*
 * mb_cache_entry_touch_compat - mark entry as used (old API)
 * @cache: cache the entry belongs to
 * @entry: entry to mark
 */
void mb_cache_entry_touch_compat(struct mb_cache *cache,
				 struct mb_cache_entry *entry)
{
	mb_cache_entry_touch(cache, entry);
}
EXPORT_SYMBOL(mb_cache_entry_touch_compat);

MODULE_AUTHOR("Compatibility Layer");
MODULE_DESCRIPTION("mbcache compatibility layer for old API");
MODULE_LICENSE("GPL");