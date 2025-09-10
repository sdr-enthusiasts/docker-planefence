#!/bin/bash


YESTERDAY="$(date -d "yesterday" +%y%m%d)"

pushd /run/socket30003 >/dev/null || exit 1
cp dumpfile.txt "dump1090-beast-aggregator-$YESTERDAY.txt"
awk -v DATE="$(date -d "yesterday" +%Y/%m/%d)" -F, -v OFS=, '{ $5=DATE; print }' dump1090-beast-aggregator-$YESTERDAY.txt > file.csv.tmp && mv file.csv.tmp dump1090-beast-aggregator-$YESTERDAY.txt

shuf -n 1 "dump1090-beast-aggregator-$YESTERDAY.txt" > /usr/share/planefence/persist/.planefence-state-lastrec
echo "done"
popd >/dev/null || exit 1
