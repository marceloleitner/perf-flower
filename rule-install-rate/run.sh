#!/bin/bash -e
#
# Run rule-install-rate on a pre-generated set of rules
#
# Author: Marcelo Ricardo Leitner, 2018
# GPLv2
#

iface=p5p1
rules=40000
skip=""   # skip_hw / skip_sw   (place holder, neither are supported :)

batchfile=tc-rules.batch


check_rpm()
{
	ret=0
	for i in "$@"; do
		if ! rpm -q $i >& /dev/null; then
			echo "Please install $i"
			ret=1
		fi
	done
	return $ret
}

check_system()
{
	kerneldebug="kernel-debuginfo-$(uname -r)"
	check_rpm gnuplot $kerneldebug perf
}

#
# Load as much as possible
#
generate_batch()
{
	s=$(date +%s)
	echo "Generating $batchfile..."
	python > $batchfile <<EOF
for i in range($rules):
	a=i & 0xff
	b=(i & 0xff00) >> 8
	c=(i & 0xff0000) >> 16
	print "filter add dev $iface parent ffff: protocol ip prio 1 flower $skip \
	       src_mac ec:13:db:%02X:%02X:%02X dst_mac ec:14:c2:%02X:%02X:%02X \
	       src_ip 56.%d.%d.%d dst_ip 55.%d.%d.%d \
	       action drop" % (a, b, c, c, b, a, a, b, c, c, b, a)
EOF
	e=$(date +%s)
	echo "Generated $rules rules in $((e-s)) seconds."
}

prep_batch()
{
	if [ ! -f $batchfile ]; then
		[ ! -e $batchfile ] || rm -f $batchfile
		generate_batch
	fi

	lines=$(wc -l $batchfile)
	lines=${lines/ *}
	if [ $lines != $rules ]; then
		generate_batch
	fi
}

cleanup()
{
	echo "Cleaning up ingress qdisc."
	echo "  removing it..."
	tc qdisc del dev $iface ingress || :
	echo "  adding it back..."
	tc qdisc add dev $iface ingress
	echo "Done."
}

do_test()
{
	./rule-install-rate.py capture -- tc -b $batchfile
}

generate_report()
{
	./rule-install-rate.py parse
}

main()
{
	check_system
	cleanup
	prep_batch
	do_test
	generate_report
}

main "$@"
