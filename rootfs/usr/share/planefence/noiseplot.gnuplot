set timefmt "%s"
set format x "%H:%M:%S"
set datafile separator ","
set xdata time
# set yrange [-50:20]
set xrange [start + offset - margin : end + offset + margin]
set ylabel "Noise Level (dBFS)"
set xlabel "Time"
set term png size 800,600
set output outfile
set title plottitle
set ytics 5 nomirror tc ls 4

set style line 1 lw 3 lt rgb "red"
set style line 2 lw 3 lt rgb "orange"
set style line 3 lw 3 lt rgb "yellow"
set style line 4 lw 3 lt rgb "black"
set style line 5 lw 3 lt rgb "green"
set style line 6 lw 6 lt rgb "blue"

set key right top
set xtics rotate

# set y2tics 5 nomirror tc ls 6
# set y2label 'Loudblness (dB)' tc ls 6

set style rect fc lt -1 fs solid 0.15 noborder
set obj rect from (start + offset), graph 0 to (end + offset), graph 1

 plot infile \
	   using ($1 + offset):2 with lines ls 6 title 'Noise',\
	'' using ($1 + offset):3 with lines ls 2 title '1-min Avg',\
	'' using ($1 + offset):4 with lines ls 3 title '5-min Avg',\
	'' using ($1 + offset):5 with lines ls 4 title '10-min Avg',\
	'' using ($1 + offset):6 with lines ls 5 title '1-hr Avg'
#	'' using ($1 + offset):($2-$5) with lines ls 6 title 'Loudness (dB)' axes x1y2





# plot "/tmp/noisecapt-200612.log" \
#	   using ($1 - offset):2 with lines ls 1 title 'Noise',\
#	'' using ($1 - offset):3 with lines ls 2 title '1-min Avg',\
#	'' using ($1 - offset):4 with lines ls 3 title '5-min Avg',\
#	'' using ($1 - offset):5 with lines ls 4 title '10-min Avg',\
#	'' using ($1 - offset):6 with lines ls 5 title '1-hr Avg'\

