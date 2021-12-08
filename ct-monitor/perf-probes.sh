#!/bin/bash -ex
#
# Adds the perf probes for perf-plot.sh
#

perf probe -d probe:* || :


# Offload request
perf probe -m nf_flow_table -a 'nf_flow_offload_add:6 offload'
perf probe -m nf_flow_table -a 'nf_flow_offload_del:6 offload'
perf probe -m nf_flow_table -a 'nf_flow_offload_stats:11 offload'


# Actual offloading
# This got restructured in upstream. Originally, it used a single work queue
# for the 3 operations. Now, they have their own work queues.
# 2ed37183abb7 ("netfilter: flowtable: separate replace, destroy and stats to different workqueues")
# Yet, a single handler is still used.
perf probe -m nf_flow_table -a flow_offload_work_handler
perf probe -m nf_flow_table -a 'flow_offload_work_add offload'
perf probe -m nf_flow_table -a 'flow_offload_work_del offload'
perf probe -m nf_flow_table -a 'flow_offload_work_stats offload'
