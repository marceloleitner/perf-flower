#!/bin/bash
#
# CT HWOL have 3 events:
#  - add
#  - del
#  - stats
#
# As ADD and DEL are triggered from the datapath, but are control actions,
# they are performed in workqueues. With that, it's async, and the system
# may take a while to execute the action. During that, the system will
# see the packets in tcpdumps, as the connectionis not yet offloaded.
#
# Similarly, after 43332cf97425 ("net/sched: act_ct: Offload only ASSURED connections")
# It may take 2s for UDP connections to be offloaded. It's expected.
#
# Anyhow, here we study how long it takes from the flowtable request to
# actual offload command to the driver to take place. Also for stats commands, which
# goes through workqueues too, and an accumulated amount of add/del commands, which
# should indicate how many connections are offloaded at a moment.
#
# Plots:
#   events-add.png
#   events-del.png
#   events-stats.png
#   events-acc.png
#
# Ideally, the test should have a clear connection setup phase, then stable, and then
# the teardown. The graphs will get unreadable if the add/del sections are too wide.
# The details won't be visible.
# 
#
# Usage:
# 1. setup perf probes:
#    # ./perf-probes.sh
# 2. record it
#    # perf record -e probe:* -aR -- sleep 300
#    # <start the test>
#    # <stop perf record when the test finishes>
# 3. plot it and get stats
#    # perf script -s perf-script.py
#    # ./perf-plot.sh
# 4. check output at events-*.png
#
# Author: Marcelo Ricardo Leitner  2021
# License: GPLv3

kernel=$(perf script --header-only | sed -n 's/.*os release : //p')
ncpu=$(perf script --header-only | sed -n 's/.*nrcpus avail : //p')
cpumodel=$(perf script --header-only | sed -n 's/.*cpudesc : //p')

# Common title across the graphs
title="${kernel//_/\\\\_} - $cpumodel - $ncpu CPUs${@:+\\n}${@//_/\\\\_}"


#
# Calls
#
calls()
{
	event=$1
	column=$2

	file="events"

	first_req=$(sed 1d $file-req.dat | cut -f 1,$column | sed '/	0$/d;/	.*/{s///;q}')
	last_exec=$(sed 1d $file.dat | cut -f 1,$column | uniq -u -s 14 | tail -n1 | sed 's/	.*//')
	delta=$(echo "$last_exec - $first_req" | bc)

	if [ -z "$first_req" ]; then
		return
	fi

	if [ $column != 3 ]; then
		left_subtitle="set key left"
	else
		left_subtitle=""
	fi

	cat > $file-$event.plt <<-_EOF_
	set terminal pngcairo size 1024,768 dashed
	set output "$file-$event.png"
	set title "Conntrack SW x HW offload control path performance\\n$title"
	set xlabel "Time (s)"
	set ylabel "Event ($event) count"
	set y2label "Offload latency (s)"
	set ytics nomirror
	set y2tics
	set xrange [0:$delta]
	$left_subtitle

	plot \\
	     '$file.dat' using (\$1-$first_req):$column title "$event exec" with lines, \\
	     '$file-req.dat' using (\$1-$first_req):$column title "$event request" with lines, \\
	     '$file-latency-$event.dat' using (\$1-$first_req):2 title "$event latency" axes x1y2 with lines
	_EOF_

	gnuplot $file-$event.plt
}

#
# Accumulated events. That is, amount of CT entries offloaded in a given time.
#
acc()
{
	event=acc
	column=$2

	file="events"

	first_req=$(sed 1d $file-req.dat | cut -f 1,2 | sed '/ 0$/d;/	.*/{s///;q}')
	last_req=$(sed 1d $file-req.dat | cut -f 1,3 | uniq -u -s 14 | tail -n1 | sed 's/	.*//')

	first_exec=$(sed 1d $file.dat | cut -f 1,2 | sed '/ 0$/d;/	.*/{s///;q}')
	last_exec=$(sed 1d $file.dat | cut -f 1,3 | uniq -u -s 14 | tail -n1 | sed 's/	.*//')

	delta_req=$(echo "$last_req - $first_req" | bc)
	delta_exec=$(echo "$last_exec - $first_exec + $first_exec - $first_req" | bc)
	delta=$(echo "$last_exec - $first_req" | bc)

	cat > $file-$event.plt <<-_EOF_
	set terminal pngcairo size 1024,768 dashed
	set output "$file-$event.png"
	set title "Conntrack SW x HW offload control path performance\\nInstant HW Offloaded entries\\n$title"
	set xlabel "Time (s)"
	set ylabel "# offloaded conntrack entries"
	set ytics nomirror

	plot \\
	     [0:$delta] '$file.dat' using (\$1-$first_req):(\$2-\$3) title "$event exec" with lines, \\
	     [0:$delta] '$file-req.dat' using (\$1-$first_req):(\$2-\$3) title "$event request" with lines
	_EOF_

	gnuplot $file-$event.plt
}

_stats()
{
	echo
	echo "$1 latency:"
	cat events-latency-$1.dat | \
		LC_ALL=C datamash -H -W mean 2 pstdev 2 min 2 max 2 | \
		column -t
}

stats()
{
	echo "$title"

	_stats add
	_stats del
	_stats stats

	first_req=$(sed 1d $file-req.dat | cut -f 1,2 -d ' ' | sed '/	0$/d;/	.*/{s///;q}')
	last_req=$(sed 1d $file-req.dat | cut -f 1,3 -d ' ' | uniq -u -s 14 | tail -n1 | sed 's/	.*//')
	count_req=$(sed 1d $file-req.dat | cut -f 1,3 -d ' ' | uniq -u -s 14 | tail -n1 | sed 's/.*	//')

	first_exec=$(sed 1d $file.dat | cut -f 1,2 -d ' ' | sed '/	0$/d;/	.*/{s///;q}')
	last_exec=$(sed 1d $file.dat | cut -f 1,3 -d ' ' | uniq -u -s 14 | tail -n1 | sed 's/	.*//')
	count_exec=$(sed 1d $file.dat | cut -f 1,3 -d ' ' | uniq -u -s 14 | tail -n1 | sed 's/.*	//')

	echo
	echo "First req: $first_req"
	echo "Last req: $last_req"
	echo "Count req: $count_req"
	echo -n "Mean req: "
	echo "$count_req/($last_req - $first_req)" | LC_ALL=C bc

	echo
	echo "First exec: $first_exec"
	echo "Last exec: $last_exec"
	echo "Count exec: $count_exec"
	echo -n "Mean exec: "
	echo "$count_exec/($last_exec - $first_exec)" | LC_ALL=C bc
}


calls add 2 
calls del 3 
calls stats 4 
acc

stats

wait
