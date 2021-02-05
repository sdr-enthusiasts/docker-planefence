#!/bin/bash

# Back up planefence related stuff to Dropbox
# Only works if you are Ramon

#First for dump1090.socket30003 logs:
FILEMASK="/tmp/dump1090-127_0_0_1-*.txt"
BKUPTIME="30"	# back up older than 30 days

[ "$1" != "" ] && BKUPTIME=$1

echo Backing up all records older than $BKUPTIME days
echo ------------------------
echo processing socket1090 logs
FILES=$(find $FILEMASK -type f -mtime +$BKUPTIME -print)
for f in $FILES
do
	printf "Processing %s: " $f
	printf "Compressing... "
	gzip --quiet --best $f
	printf "Uploading to Dropbox... "
	# make the directory if it doesn't exist...
	rclone mkdir dropbox:Dump1090-logs/20$(echo $f | rev | cut -c 9-10 | rev)-$(echo $f | rev | cut -c 7-8 | rev)
	# Now upload the file...
	rclone move $f.gz dropbox:Dump1090-logs/20$(echo $f | rev | cut -c 9-10 | rev)-$(echo $f | rev | cut -c 7-8 | rev)
	printf "Done!\n"
done

# Now back up PlaneFence data:
# back up these files:
FILEMASK="/usr/share/planefence/html/planefence-* /usr/share/planefence/html/planeheatdata* /usr/share/planefence/html/noisegraph* /usr/share/planefence/html/noisecapt-spectro-2*"
FILEDIR="/usr/share/planefence/html"
TGZFILE="pf-backup-"
TMPTAR="/tmp"

echo Backing up planefence data:
# copy backup file to tmp directory if it exists:
#cp -f $FILEDIR/$TGZFILE*.tar.gz  $TMPTAR
# unzip it so regular `tar` can handle it:
#echo Unzipping existing tar.gz files...
#for f in $TMPTAR/$TGZFILE*.tar.gz
#do
#	gzip -d $f
#done

# Add $FILEMASK files to the TAR file and delete them only if successful:

echo Backing up files to .tar archives...
printf "Processing... "
for f in $FILEMASK
do
	printf "%s " $f
	if (( ( (`date +%s` - `stat -c %Y $f`) / 86400 ) > $BKUPTIME )) # if file last write date is later than $BKUPTIME, only then write it into the TAR
	then
		# if there is no .tar file with the correct yyy-mm in the TMP directory, but this file exists as a tar.gz file in the output directory, then go get it
		if [ ! -f "$TMPTAR/$TGZFILE$(date -d @`stat -c %Y $f` +%Y-%m).tar" ] && [ -f "$FILEDIR/$TGZFILE$(date -d @`stat -c %Y $f` +%Y-%m).tar.gz" ]
		then
			echo Fetching $FILEDIR/$TGZFILE$(date -d @`stat -c %Y $f` +%Y-%m).tar.gz \> $TMPTAR/$TGZFILE$(date -d @`stat -c %Y $f` +%Y-%m).tar
			cp $FILEDIR/$TGZFILE$(date -d @`stat -c %Y $f` +%Y-%m).tar.gz $TMPTAR
			gzip -d $TMPTAR/$TGZFILE$(date -d @`stat -c %Y $f` +%Y-%m).tar.gz
		fi

		tar rvf $TMPTAR/$TGZFILE$(date -d @`stat -c %Y $f` +%Y-%m).tar $f  && rm -f $f || ( echo "Problem adding file to TAR, exiting..."; exit 1 )
	fi
done
printf "\n"
echo "GZipping files..."
for f in $TMPTAR/$TGZFILE*.tar
do
        gzip --quiet --best $f || BACKUPOK=false
done

echo Copying files back to HTML directory...
for f in $TMPTAR/$TGZFILE*.tar.gz
do
	cp -f $f $FILEDIR
done

echo Backing up to Dropbox...
for f in $TMPTAR/$TGZFILE*.tar.gz
do
	rclone mkdir dropbox:Dump1090-logs/$(echo $f | cut -d '-' -s -f 3-4 | cut -c 1-7 )
	rclone move $f dropbox:Dump1090-logs/$(echo $f | cut -d '-' -s -f 3-4 | cut -c 1-7 )
done

#-------------------
# Now do the same thing for the heatmap directory


# Now back up heastmap data:
# back up these files:
FILEMASK="/usr/share/heatmap/html/heatmapdata-*.js /usr/share/heatmap/html/index-*.html "
FILEDIR="/usr/share/heatmap/html"
TGZFILE="heatmap-backup-"
TMPTAR="/tmp"

# copy backup file to tmp directory if it exists:
#cp -f $FILEDIR/$TGZFILE*.tar.gz  $TMPTAR
# unzip it so regular `tar` can handle it:
#echo Unzipping existing tar.gz files...
#for f in $TMPTAR/$TGZFILE*.tar.gz
#do
#	gzip -d $f
#done

# Add $FILEMASK files to the TAR file and delete them only if successful:

BACKUPOK=true
echo Heatmap data:
echo Backing up files to .tar archives...
printf "Processing... "
for f in $FILEMASK
do
       printf "%s " $f
       # if there is no .tar file with the correct yyy-mm in the TMP directory, but this file exists as a tar.gz file in the output directory, then go get it
       if [ ! -f "$TMPTAR/$TGZFILE$(date -d @`stat -c %Y $f` +%Y-%m).tar" ] && [ -f "$FILEDIR/$TGZFILE$(date -d @`stat -c %Y $f` +%Y-%m).tar.gz" ]
       then
	       echo Fetching $FILEDIR/$TGZFILE$(date -d @`stat -c %Y $f` +%Y-%m).tar.gz \> $TMPTAR/$TGZFILE$(date -d @`stat -c %Y $f` +%Y-%m).tar
               cp $FILEDIR/$TGZFILE$(date -d @`stat -c %Y $f` +%Y-%m).tar.gz $TMPTAR
               gzip -d $TMPTAR/$TGZFILE$(date -d @`stat -c %Y $f` +%Y-%m).tar.gz
       fi

	if (( ( (`date +%s` - `stat -c %Y $f`) / 86400 ) > $BKUPTIME )) # if file last write date is later than $BKUPTIME, only then write it into the TAR
	then
		tar rvf $TMPTAR/$TGZFILE$(date -d @`stat -c %Y $f` +%Y-%m).tar $f   && rm -f $f || ( echo "Problem adding file to TAR, exiting..."; exit 1 )
	fi
done

printf "\n"
echo "GZipping files..."
for f in $TMPTAR/$TGZFILE*.tar
do
        gzip --quiet --best $f || BACKUPOK=false
done

echo Copying files back to HTML directory...
for f in $TMPTAR/$TGZFILE*.tar.gz
do
	cp -f $f $FILEDIR
done

echo Backing up to Dropbox...
for f in $TMPTAR/$TGZFILE*.tar.gz
do
	rclone mkdir dropbox:Dump1090-logs/$(echo $f | cut -d '-' -s -f 3-4 | cut -c 1-7 )
	rclone move $f dropbox:Dump1090-logs/$(echo $f | cut -d '-' -s -f 3-4 | cut -c 1-7 )
done
