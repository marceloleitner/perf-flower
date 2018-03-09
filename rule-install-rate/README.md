# rule-install-rate

Load a bunch of tc flower rules into a clean ingress qdisc and try to identify
where the time is most spent. Currently only supports testing with hardware
offloading enabled.

A [sample][sample] output looks like:

![Sample graph][samplegraph]

[sample]: https://github.com/marceloleitner/perf-flower/blob/master/rule-install-rate/sample/
[samplegraph]: https://github.com/marceloleitner/perf-flower/raw/master/rule-install-rate/sample/fl_change.png
