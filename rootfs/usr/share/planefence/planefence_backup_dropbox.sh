#!/bin/bash
mkdir /tmp/pf-backup
cd /tmp/pf-backup
source /usr/share/planefence/planefence.conf

[ "$PLANEFENCEDIR" == "" ] && PLANEFENCEDIR="/usr/share/planefence"
[ "$OUTFILEDIR" == "" ] && OUTFILEDIR="/usr/share/dump1090-fa/html/planefence"

tar -czvf planefence-progs-$(date +"%Y-%m-%d").tar.gz $PLANEFENCEDIR
tar -czvf planefence-data-$(date +"%Y-%m-%d").tar.gz $OUTFILEDIR

rclone move -q planefence-progs-$(date +"%Y-%m-%d").tar.gz dropbox:Dump1090-logs/Planefence_backup/
rclone move -q planefence-data-$(date +"%Y-%m-%d").tar.gz dropbox:Dump1090-logs/Planefence_backup/

cd /
rm -rf /tmp/pf-backup

