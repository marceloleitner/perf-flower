
        set terminal pngcairo size 1024,768 dashed
        set output "fl_change.png"
        set title "Flower rule install performance\nTime consumed per rule install and install rate"
        set xlabel "Time (s)"
        set ylabel "Datapath flows"
        set y2label "Insert rate"
        set ytics nomirror
        set y2tics

        plot              'fl_change.dat' index 0 using 1:2 title "tc flower cumulative" with lines,              'fl_change.dat' index 1 using 1:2 title "tc flower sw part" with lines,              'fl_change.dat' index 2 using 1:2 title "tc flower hw part" with lines,              'fl_change.dat' index 3 using 1:2 title "tc flower just flower" with lines,              'fl_change.dat' index 0 every ::1 using 1:($2/$1)                 title "tc flower acc insert rate" axes x1y2 with lines
        