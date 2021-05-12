#!/bin/bash
#
# one-time script to read all Dropbox archives and scan them for Dictator Planes

# Get all file names and write to tmpfile:

sudo systemctl stop planefence

printf "Getting list of all files in archive...\n"
rclone ls dropbox:Dump1090-logs/ | grep dump1090 | grep -v ".log.gz" | awk -F ' ' '{print $2}' | sort > /tmp/tmpfile.tmp

# rotate through the files:
(( counter=0 ))

while read -r dbfile
do
	(( counter++ ))
	printf "Getting file %d of %d: %s from Dropbox... " $counter $(cat /tmp/tmpfile.tmp | wc -l) $(echo $dbfile | awk -F '/' '{print $2}')
	rclone copy dropbox:Dump1090-logs/"$dbfile" /tmp/dumptmp

	file=$(echo $dbfile | awk -F '/' '{print $2}')

	printf "unzipping %s... " $file
	gzip -d /tmp/dumptmp/$file

	printf "%d lines... calling dictalert... " $(cat /tmp/dumptmp/${file%.*} | wc -l)

	/usr/share/planefence/dictalert.sh /tmp/dumptmp/${file%.*}

	printf "cleaning up... "
	rm -rf /tmp/dumptmp

	printf "done!\n\n"
done < "/tmp/tmpfile.tmp"

sudo systemctl start planefence
