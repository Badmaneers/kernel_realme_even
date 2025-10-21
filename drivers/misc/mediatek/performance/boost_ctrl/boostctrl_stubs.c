// SPDX-License-Identifier: GPL-2.0
/* Minimal stubs to provide symbols when boost controllers are not built */

#include <linux/types.h>
#include <linux/errno.h>
#include <linux/kernel.h>
#include "topo_ctrl.h"

int topo_ctrl_get_nr_clusters(void)
{
	return 1; /* assume single cluster if topo ctrl not present */
}
EXPORT_SYMBOL(topo_ctrl_get_nr_clusters);

int update_userlimit_cpu_freq(int kicker, int num_cluster,
		struct cpu_ctrl_data *freq_limit)
{
	/* No-op stub: return success */
	return 0;
}
EXPORT_SYMBOL(update_userlimit_cpu_freq);
