#!/usr/bin/python3
#
# Script for inspecting flower rule install rate performance.
#
# PreReq:
#  kernel installed with debuginfos available.
#  perf
#  gnuplot
#
# Usage:
# 
#   First step is to capture the information. Prepare the system up to the
# point on which it is ready to have rules installed. Then, execute:
#   # ./perf-flower.py capture -- tc -b tc-rules.batch
# in order to capture flower updates when running such tc command.
#   This step will clear all probes on group flower, and re-insert them.
# One probe at beginning of the function, one at its return, and 3 other
# probes on specific code lines.
#
#   Second step is to parse this captured data, which can be done on another
# system. Simply:
#   # ./perf-flower.py parse
# and it will parse the perf.data file and produce the gnuplot output at
# file 'fl_change.png'.
#
# What the curves mean:
#  tc flower cumulative: it is simply the total amount of time spent. It
#    consists of tc flower code plus socket handling and everything else.  That
#    is, all time spent between fl_change() calls is considered in there and
#    that is what OVS, i.e., would face.
#  tc flower sw part: It's the amount of time spent on adding the filter on the
#     sw path, and just that. It has no socket handling, no nothing else.
#  tc flower hw part: It's the amount of time spent on adding the filter on the
#     hw path, and just that. It has no socket handling, no nothing else.
#  tc flower just flower: it's the amount of time spent only on fl_change.
#     All socket handling is ignored, and just the delta between end and start
#     of fl_change() is considered. That is, how much depends on flower when
#     compared to 'tc flower cumulative' and the socket/rtnl stuff.
#
# Author: Marcelo Ricardo Leitner
# License: GPLv3
#

import os
import sys

#
# perf script parsing and output generation
#

class Probe():
    def __init__(self):
        description = "tc flower"
        self.first_ts = 0.0
        self.xy = [ [], [], [], [] ]
        self.write_gnuplot_cfg(description)

    def write_gnuplot_cfg(self, description):
        fp = open('fl_change.plt', 'w')
        fp.write("""
        set terminal pngcairo size 1024,768 dashed
        set output "fl_change.png"
        set title "Flower rule install performance\\nTime consumed per rule install and install rate"
        set xlabel "Time (s)"
        set ylabel "Datapath flows"
        set y2label "Insert rate"
        set ytics nomirror
        set y2tics

        plot \
             'fl_change.dat' index 0 using 1:2 title "{0} cumulative" with lines, \
             'fl_change.dat' index 1 using 1:2 title "{0} sw part" with lines, \
             'fl_change.dat' index 2 using 1:2 title "{0} hw part" with lines, \
             'fl_change.dat' index 3 using 1:2 title "{0} just flower" with lines, \
             'fl_change.dat' index 0 every ::1 using 1:($2/$1) \
                title "{0} acc insert rate" axes x1y2 with lines
        """.format(description))
        fp.close()

    def add_point(self, ts, probe):
        if probe == 'flower__fl_change_entry':
            self.change_entry_ts = ts
            if self.first_ts == 0.0:
                self.first_ts = ts
                count = 0
            else:
                count = self.xy[0][-1][1]
            count += 1
            self.xy[0].append((ts-self.first_ts, count))
        elif probe == 'flower__fl_change_sw':
            self.change_sw_ts = ts
        elif probe == 'flower__fl_change_hw':
            delta = ts - self.change_sw_ts
            if not len(self.xy[1]):
                new_entry = ( delta, 1 )
            else:
                new_entry = ( delta + self.xy[1][-1][0],
                              1 + self.xy[1][-1][1] )
            self.xy[1].append(new_entry)

            self.change_hw_ts = ts
        elif probe == 'flower__fl_change_fold':
            # If hw ts is missing, skip_hw was used and we have to use the sw
            # timestamp instead
            try:
                delta = ts - self.change_hw_ts
                if not len(self.xy[2]):
                    new_entry = ( delta, 1 )
                else:
                    new_entry = ( delta + self.xy[2][-1][0],
                                  1 + self.xy[2][-1][1] )
                self.xy[2].append(new_entry)
            except:
                delta = ts - self.change_sw_ts
                if not len(self.xy[1]):
                    new_entry = ( delta, 1 )
                else:
                    new_entry = ( delta + self.xy[1][-1][0],
                                  1 + self.xy[1][-1][1] )
                self.xy[1].append(new_entry)
        elif probe.startswith('flower__fl_change_ret'):
            delta = ts - self.change_entry_ts
            if not len(self.xy[3]):
                new_entry = ( delta, 1 )
            else:
                new_entry = ( delta + self.xy[3][-1][0],
                              1 + self.xy[3][-1][1] )
            self.xy[3].append(new_entry)

    def save(self):
        fp = open('fl_change.dat', 'w')
        for idx in self.xy:
            if len(idx):
                for ts, count in idx:
                    fp.write('%f %d\n' % (ts, count))
            else:
                # So gnuplot sees this block.
                fp.write('0 0\n')
            fp.write('\n\n')
        fp.close()


def trace_begin():
    global p
    print("in trace_begin")
    p = Probe()

def trace_end():
    p.save()
    os.system("gnuplot fl_change.plt")
    print("in trace_end")

def trace_unhandled(event_name, context, event_fields_dict, perf_sample_dict={}):
    ts = event_fields_dict['common_s'] + event_fields_dict['common_ns']/1000000000.0
    p.add_point(ts, event_name)

#
# Do the data capture
#
def clear_perf_probes():
    os.system('perf probe -d flower:* >& /dev/null')

def load_module():
    # make sure flower is loaded, otherwise we can't install the probes
    ret = os.system('modprobe cls_flower')
    if ret:
        sys.exit(ret)

def get_kernel_version():
    fp = open('/proc/version', 'r')
    version = fp.readline()
    del fp

    version = version[14:]
    version = version[:version.index(' ')]

    return version

def perf_probe_setup():
    """Perf can't locate the source for a kernel build with 'make pkg-rpm', so
    we need to specify the source dir."""
    global perf_probe_args

    version = get_kernel_version()

    dirname = "/lib/modules/{0}/source".format(version)
    while True:
        try:
            tgt = os.readlink(dirname)
            dirname = tgt
        except OSError as err:
            if err.errno == 22:
                # Not a link anymore, so we fount it
                break
            dirname = ""

    if len(dirname):
        perf_probe_args = "-s {0}".format(dirname)
    else:
        perf_probe_args = ""

def install_entry_probe():
    ret = os.system('perf probe -m cls_flower -a flower:fl_change_entry=fl_change')
    if ret:
        sys.exit(ret)

def install_ret_probe():
    ret = os.system('perf probe -m cls_flower -a flower:fl_change_ret=fl_change%return')
    if ret:
        sys.exit(ret)

def install_probe_codeline(probe, code):
    # Find at which line we should install the probe
    output = check_output(["/bin/sh", "-c",
        "perf probe %s -m cls_flower -L fl_change | grep -F '%s'" % (perf_probe_args, code)])
    output = output.decode()
    line = int(output.strip().split(' ')[0])

    # Install the probe
    check_call(["/bin/sh", "-c",
        "perf probe -m cls_flower -a flower:%s=fl_change:%d" % (probe, line)])

def install_sw_probe():
    try:
        # After 1f17f7742eeb ("net: sched: flower: insert filter to ht before offloading it to hw")
        install_probe_codeline('fl_change_sw', 'err = fl_ht_insert_unique(fnew, fold, &in_ht);')
        return
    except:
        pass

    try:
        install_probe_codeline('fl_change_sw', 'if (!fold && __fl_lookup(fnew->mask, &fnew->mkey))')
        return
    except:
        pass

    try:
        install_probe_codeline('fl_change_sw', 'if (!fold && fl_lookup(head, &fnew->mkey))')
        return
    except:
        pass

    # Last attempt. If it also fails, abort everything.
    install_probe_codeline('fl_change_sw', 'if (!fold && fl_lookup(fnew->mask, &fnew->mkey))')

def install_hw_probe():
    install_probe_codeline('fl_change_hw', 'err = fl_hw_replace_filter')

def install_fold_probe():
    install_probe_codeline('fl_change_fold', 'if (fold)')

def capture():
    global check_output, check_call
    from subprocess import check_output, check_call, CalledProcessError

    clear_perf_probes()
    load_module()
    perf_probe_setup()
    try:
        install_entry_probe()
        install_ret_probe()
        install_sw_probe()
        install_hw_probe()
        install_fold_probe()
    except CalledProcessError as err:
        print('ERROR: Flower code has changed and we couldn\'t install a probe.')
        raise

    print('Excellent, all probes were installed.')
    print('Executing perf record.')
    cmd = ['perf', 'record', '-e', 'flower:*', '-aR', '--' ]
    cmd.extend(sys.argv[3:])
    print(cmd)
    os.execvp('perf', cmd)

#
# application mode handling
#
if len(sys.argv) == 1:
    print("""Usage:
{0} capture -- <command>    capture flower stats during <command> execution
{0} parse                   parse a perf.data sample and produce outputs""".format(sys.argv[0]))
    sys.exit(0)
elif sys.argv[1] == 'capture':
    # Capture mode
    capture()
elif sys.argv[1] == 'parse':
    # parse requested. Re-execute through perf
    os.execvp('perf', ('perf', 'script', '-s', sys.argv[0], '+parse'))
elif sys.argv[1] == '+parse':
    # called from within perf script environment
    sys.path.append(os.environ['PERF_EXEC_PATH'] + \
            '/scripts/python/Perf-Trace-Util/lib/Perf/Trace')

    from perf_trace_context import *
    from Core import *

