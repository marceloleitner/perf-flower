#!/bin/bash -ex
#
# Adds the perf probes for perf-plot.sh
#

perf probe -d probe:* || :
perf probe -m cls_flower -a fl_change
perf probe -m cls_flower -a fl_change%return
perf probe -m cls_flower -a fl_delete
perf probe -m cls_flower -a fl_delete%return
# Switch to other NICs here if you wish, and on perf-plot.sh
perf probe -m mlx5_core -a mlx5e_configure_flower
perf probe -m mlx5_core -a mlx5e_configure_flower%return
perf probe -a tc_dump_tfilter
perf probe -a tc_dump_tfilter%return

if perf probe -a tc_ctl_tfilter; then
	perf probe -a tc_ctl_tfilter%return
else
	perf probe -a tc_new_tfilter
	perf probe -a tc_new_tfilter%return
	perf probe -a tc_del_tfilter
	perf probe -a tc_del_tfilter%return
fi
