#!/bin/bash
#
# Plots:
#  - fl_change() calls over time and its rate.
#  - time spent on some key functions and cumulative times
#  - ditto for stats polling
#
# The script is smart enough to track task CPU changes, which may happen
# especially if rtnl_lock is not held by rtnetlink anymore.
#
# Usage:
# 1. setup perf probes:
#    # ./perf-probes.sh
# 2. record it
#    # perf record -e probe:* -aR -- sleep 300
#    # <start the test>
#    # <stop perf record when the test finishes>
# 3. plot it
#    # ./perf-plot.sh
# 4. check output at fl_change-*.png
#
# Author: Marcelo Ricardo Leitner  2019
# License: GPLv2

script=$(perf script --ns)
if grep -qw tc_new_tfilter <<<"$script"; then
	tc_new=tc_new_tfilter
else
	tc_new=tc_ctl_tfilter
fi

#
# General stats
#
start_time=$(grep probe:$tc_new: <<<"$script" | head -n1 | awk '{print $4}' | sed s/://)
end_time=$(grep probe:${tc_new}__return: <<<"$script" | tail -n1 | awk '{print $4}' | sed s/://)

# Carve out
#    revalidator12  5079 [028] 16126.431019:                probe:tc_dump_tfilter: (ffffffff8c554490)
# Into
#    5079 16126.431019 tc_dump_tfilter
# Restrict it to the test time, and sort it by process (so that its calls are
# serialized)
pscript=$(awk '{ sub(":$", "", $4); sub("[^:]+:", "", $5); sub(":$", "", $5); print $2, $4, $5 }' <<<"$script" |\
	sed -n "/ $start_time /,/ $end_time /{p}" |\
	sort
	)
#echo "$pscript" > fl_change.dbg

inserts=$(grep -cw fl_change <<<"$pscript")
deletes=$(grep -cw fl_delete <<<"$pscript")
changes=$(grep -cw mlx5e_configure_flower <<<"$pscript")
kernel=$(perf script --header-only | sed -n 's/.*os release : //p')
ncpu=$(perf script --header-only | sed -n 's/.*nrcpus avail : //p')
cpumodel=$(perf script --header-only | sed -n 's/.*cpudesc : //p')

echo "Start time: $start_time"
echo "End time: $end_time"
echo "Test duration: $(echo "($end_time-$start_time)" | bc)"
echo "Avg insert rate: $(echo "$inserts/($end_time-$start_time)" | bc)"
echo "Avg delete rate: $(echo "$deletes/($end_time-$start_time)" | bc)"
echo "Avg change rate: $(echo "$changes/($end_time-$start_time)" | bc)"
echo "Kernel: $kernel"

# Common title across the graphs
title="${kernel//_/\\\\_}\n$cpumodel - $ncpu CPUs${@:+\\n}${@//_/\\\\_}"

#
# Call frequency
#

awk '/fl_change$/{print $2}' <<<"$pscript" | sort -n > fl_change-rate.dat

first=$(head -n1 fl_change-rate.dat)

cat > fl_change-rate.plt <<_EOF_
set terminal pngcairo size 1024,768 dashed
set output "fl_change-rate.png"
set title "Flower rule install performance\\nTime consumed and install rate\\n$title"
set xlabel "Datapath flows"
set ylabel "Time (s)"
set y2label "Insert rate (flows/s)"
set ytics nomirror
set y2tics

plot \\
     'fl_change-rate.dat' using (\$1-$first) title "Time" with lines, \\
     'fl_change-rate.dat' every ::1 using :(\$0/(\$1-$first) < 20000 ? \$0/(\$1-$first) : 0) \\
        title 'fl\\_change rate' axes x1y2 with lines
_EOF_

gnuplot fl_change-rate.plt

#
# Call durations
#

#perf script | grep -e probe:fl_change: -e probe:fl_change__return: | awk '{print $4}' |\
#	sed s/:// | sed -e 'N;s/\n/ /' > fl_change.dat
# Serialize per process, and then per timestamp
grep -e 'fl_change$' -e 'fl_change__return' <<<"$pscript" |\
	awk '{ print $2 }' |\
	sed -e 'N;s/\n/ /' |\
	sort -n > fl_change-call_duration.dat

echo >> fl_change-call_duration.dat
echo >> fl_change-call_duration.dat

#perf script | grep -e probe:$tc_new: -e probe:${tc_new}__return: | awk '{print $4}' |\
#	sed s/:// | sed -e 'N;s/\n/ /' >> fl_change.dat
# Serialize per process, and then per timestamp
grep -e "${tc_new}$" -e "${tc_new}__return" <<<"$pscript" |\
	awk '{ print $2 }' |\
	sed -e 'N;s/\n/ /' |\
	sort -n >> fl_change-call_duration.dat

echo >> fl_change-call_duration.dat
echo >> fl_change-call_duration.dat

#perf script | grep -e probe:mlx5e_configure_flower: -e probe:mlx5e_configure_flower__return: | awk '{print $4}' |\
#	sed s/:// | sed -e 'N;s/\n/ /' >> fl_change.dat
# Serialize per process, and then per timestamp
grep -e "mlx5e_configure_flower$" -e "mlx5e_configure_flower__return" <<<"$pscript" |\
	awk '{ print $2 }' |\
	sed -e 'N;s/\n/ /' |\
	sort -n >> fl_change-call_duration.dat

cat > fl_change-call_duration.plt <<_EOF_
set terminal pngcairo size 1024,768 dashed
set output "fl_change-call_duration.png"
set title "Flower rule install performance\\nTime consumed and install rate\\n$title"
set xlabel "Datapath flows"
set ylabel "Time (s)"
set y2label "Cumulative time (s)"
set ytics nomirror
set y2tics

plot \\
     'fl_change-call_duration.dat' index 0 using (\$2-\$1) title 'fl\\_change call duration' with lines, \\
     'fl_change-call_duration.dat' index 1 using (\$2-\$1) title '${tc_new//_/\\_} call duration' with lines, \\
     'fl_change-call_duration.dat' index 2 using (\$2-\$1) title 'mlx5e\\_configure\\_flower call duration' with lines, \\
     'fl_change-call_duration.dat' index 0 using (\$2-\$1) title 'fl\\_change cumulative time' axes x1y2 with lines smooth cumulative, \\
     'fl_change-call_duration.dat' index 1 using (\$2-\$1) title '${tc_new//_/\\_} cumulative time' axes x1y2 with lines smooth cumulative, \\
     'fl_change-call_duration.dat' index 2 using (\$2-\$1) title 'mlx5e\\_configure\\_flower cumulative time' axes x1y2 with lines smooth cumulative
_EOF_

gnuplot fl_change-call_duration.plt

#
# Time spent dumping stats
#

#sed -n "/ $start_time:/,/ $end_time:/{/probe:tc_dump_tfilter/p}" <<<"$script" |\
#	awk '{print $4}' | sed s/:// | sed -e 'N;s/\n/ /' > fl_change.dat
# Serialize per process, and then per timestamp
grep -e "tc_dump_tfilter$" -e "tc_dump_tfilter__return" <<<"$pscript" |\
	sort |\
	awk '{ print $2 }' |\
	sed -e 'N;s/\n/ /' |\
	sort -n \
	> fl_change-stats.dat

cat > fl_change-stats.plt <<_EOF_
set terminal pngcairo size 1024,768 dashed
set output "fl_change-stats.png"
set title "Stats monitoring impact, call duration and acumulated time\n$title"
set xlabel "Test time (s)"
set ylabel "Time spent (s)"
set y2label "Cumulative time (s)"
set ytics nomirror
set y2tics

plot \\
     'fl_change-stats.dat' index 0 using (\$1-$start_time):(\$2-\$1) title 'tc\\_dump\\_tfilter call duration' with points, \\
     'fl_change-stats.dat' index 0 using (\$1-$start_time):(\$2-\$1) title "acumulated call duration" axes x1y2 with lines smooth cumulative
_EOF_

if grep -q . fl_change-stats.dat; then
	gnuplot fl_change-stats.plt
else
	rm -f fl_change-stats.png
fi
