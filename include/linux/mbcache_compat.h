/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_MBCACHE_COMPAT_H
#define _LINUX_MBCACHE_COMPAT_H

/*
 * Compatibility header for old mbcache API
 *
 * Vendor drivers (like exFAT) that use the old mbcache interface
 * should include this header instead of <linux/mbcache.h>
 */

#include <linux/mbcache.h>
#include <linux/blkdev.h>

/*
 * Old API function declarations
 * These wrap the new mbcache implementation for backward compatibility
 */

/* Allocate a new cache entry (not yet inserted) */
struct mb_cache_entry *mb_cache_entry_alloc_compat(struct mb_cache *cache,
                           gfp_t mask);

/* Insert entry into cache with block device and sector */
int mb_cache_entry_insert_compat(struct mb_cache *cache,
                 struct mb_cache_entry *entry,
                 struct block_device *bdev,
                 sector_t block, u32 key);

/* Release (put) entry reference */
void mb_cache_entry_release_compat(struct mb_cache *cache,
                   struct mb_cache_entry *entry);

/* Free entry that was never inserted */
void mb_cache_entry_free_compat(struct mb_cache_entry *entry);

/* Get entry by block device and sector */
struct mb_cache_entry *mb_cache_entry_get_compat(struct mb_cache *cache,
                         struct block_device *bdev,
                         sector_t block);

/* Delete entry if unused, otherwise return it with reference */
struct mb_cache_entry *mb_cache_entry_delete_or_get_compat(
                struct mb_cache *cache,
                struct block_device *bdev,
                sector_t block);

/* Wait until entry becomes unused */
void mb_cache_entry_wait_unused_compat(struct mb_cache_entry *entry);

/* Mark entry as recently used */
void mb_cache_entry_touch_compat(struct mb_cache *cache,
                 struct mb_cache_entry *entry);

#endif /* _LINUX_MBCACHE_COMPAT_H */