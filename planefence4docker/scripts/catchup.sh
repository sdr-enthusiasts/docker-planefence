#!/bin/bash
TMPDIR=/tmp
LOGFILEBASE=$TMPDIR/dump1090-127_0_0_1-
PLANEFENCEDIR=/usr/share/planefence
MAXHIST=7

# resolve any commandline arg:
if [ "$1" != "" ]
then
        MAXHIST=$1
fi

# First stop the Planefence Systemd service if it's active:
RESTARTSERVICE=1
systemctl -q is-active planefence && sudo systemctl stop planefence || RESTARTSERVICE=0

# loop though all dates:
echo looping through last $MAXHIST of $LOGFILEBASE*.txt
for t in $(ls -1 $LOGFILEBASE*.txt | tail -$MAXHIST | rev | cut -c5-10 | rev)
do
   echo processing $t
   $PLANEFENCEDIR/planefence.sh $t
   echo Done, cycling to the next file
done

# Restart the Planefence Systemd Service if we stopped it earlier:
if [ "$RESTARTSERVICE" == "1" ]
then
	sudo systemctl start planefence
fi

echo All done. Sayonara!
