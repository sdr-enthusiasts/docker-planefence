#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys, getopt, csv, os, html.parser, math
import numpy as  np
from datetime import datetime
from datetime import timezone
from tzlocal import get_localzone
import calendar

def get_ax_link(icao, row, lat, lon, date, time):
    # format example: https://globe.adsbexchange.com/?icao=a4a567&lat=42.397&lon=-71.177&zoom=12.0&showTrace=2020-08-12
    try:
        falink = 'https://globe.adsbexchange.com/?icao='  + icao.lower() + '&lat=' + str(lat) + '&lon=' + str(lon) + '&zoom=12'
        dt_string = date + ' ' + time[:-4]
#        naive = datetime.strptime(dt_string, "%Y/%m/%d %H:%M:%S")
#        local_dt = get_localzone().localize(naive)
#        utc_tuple = local_dt.utctimetuple()
        local = naive.replace(tzinfo=datetime.now(timezone.utc).astimezone().tzinfo)
        utc = local.astimezone(tz=timezone.utc)
        utc_tuple=utc.timetuple()
        falink = falink + '&showTrace=' + str(utc_tuple[0]) + '-' + str.zfill(str(utc_tuple[1]), 2) + '-' + str.zfill(str(utc_tuple[2]), 2)
        epoch_seconds = int(utc.timestamp())
        falink = falink + '&timestamp=' + str(epoch_seconds)

    except:
        falink = falink + '&showTrace=' + date[0:4] + '-' + date[5:7] + '-' + date[8:10]

    return falink

class Record():
    def __init__(self, icao, callsign, ts1, ts2, min_alt, min_dist, link):
        self.icao = icao
        self.callsign = callsign
        self.ts1 = ts1
        self.ts2 = ts2
        self.min_alt = min_alt
        self.min_dist = min_dist
        self.link = link

def main(argv):

    inputfile = ''
    outputfile = ''
    lat = 42.3966
    lon = -71.1773
    maxdist = 2
    verbose = 0
    maxalt = 99999
    logfile = ''
    outfile = '/dev/stdout'
    tday = False
    goodcount=0
    badcount=0
    calcdist = False
    trackservice = 'adsbexchange'
    distunit="mi"
    altcorr = 0

    now_utc = datetime.now(timezone.utc)
    now = now_utc.astimezone(get_localzone())

    try:
       opts, args = getopt.getopt(argv,'',["h","help","?","distance=","lat=","lon=","dist=","log=","logfile=","v","verbose","outfile=","maxalt=","calcdist","distunit=","trackservice=","altcorr="])
    except getopt.GetoptError:
       print('Usage: planefence.py [--verbose] [--calcdist] --distance=<distance_in_statute_miles> --logfile=/path/to/logfile [--outfile=/path/to/outputfile] [--maxalt=maximum_altitude_in_ft] [--format=csv|html|both] [--trackservice=adsbexchange|flightaware]')
       sys.exit(2)

    for opt, arg in opts:
        if opt in ("-h", "-?", "--help", "--?") :
            print('Usage: planefence.py [--verbose] [--calcdist] --distance=<distance_in_statute_miles> --logfile=/path/to/logfile [--outfile=/path/to/outputfile] [--maxalt=maximum_altitude_in_ft] [--format=csv|html|both] [--trackservice=adsbexchange|flightaware]')
            print('If lat/long is omitted, then Belmont, MA (town hall) is used.')
            print('If distance is omitted, then 2 miles is used.')
            print('If outfile is omitted, then output is written to stdout. Note - if you intend to capture stdout for processing, make sure that --verbose=1 is not used.')
            print('If --today is used, the logfile is assumed to be the base format for logs, and we will attempt to pick today\'s log.')
            print('If --calcdist is used, it will calculate the distance based on the coordinates. If it is omitted, the distance from the logfile will be used. Note that calculation of distances is very processor intensive and may dramatically slow down the processing speed of large files.')
        elif opt == "--lat":
            lat = float(arg)
        elif opt =="--lon":
            lon = float(arg)
        elif opt in ("--logfile", "--log"):
            logfile = arg
        elif opt in ("--distance", "--dist"):
            maxdist = float(arg)
        elif opt in ("--v", "--verbose"):
            verbose = 1
        elif opt == "--outfile":
            outfile = arg
        elif opt == "--maxalt":
            maxalt = float(arg)
        elif opt == "--calcdist":
            calcdist = True
        elif opt == "--distunit":
            distunit = arg
        elif opt == "--trackservice":
            trackservice = arg
        elif opt == "--altcorr":
            altcorr = int(arg)

    if verbose == 1:
       # print 'lat = ', lat
       # print 'lon = ', lon
       print('max distance = ', maxdist, distunit)
       print('max altitude = ', maxalt)
       # print 'output is written to ', outfile

    if logfile == '':
       print("ERROR: Need logfile parameter")
       sys.exit(2)

    if verbose == 1:
       print('input is read from ', logfile)

    if trackservice != 'adsbexchange' and trackservice != 'flightaware':
       print("ERROR: --trackservice parameter must be adsbexchange or flightaware")
       sys.exit(2)

    if distunit != 'km' and distunit != "nm" and distunit != "mi" and distunit != "m":
       print("ERROR: --distunit must be one of [km|nm|mi|m]")
       sys.exit(2)

    if int(altcorr) < 0:
       print("ERROR: --altcorr must be a non-negative integer")
       sys.exit(2)

    lat1 = math.radians(float(lat))
    lon1 = math.radians(float(lon))

    # now we open the logfile
    # and we parse through each of the lines
    #
    # format of logfile is 0-ICAO,1-altitude,2-latitude,3-longitude,4-date,5-time,6-angle,7-distance,8-squawk,9-ground_speed(kilometerph),10-track,11-callsign
    # format of airplaneslist is [[0-ICAO,11-FltNum,4/5-FirstHeard,4/5-LastHeard,1-LowestAlt,7-MinDistance,FltLink)]

    with open(logfile, "rt") as f:
        # the line.replace is because sometimes the logfile is corrupted and contains zero bytes. Python pukes over this.
        reader = csv.reader( (line.replace('\0','') for line in f) )
        records = np.array(["ICAO","Flight Number","In-range Date/Time","Out-range Date/Time","Lowest Altitude","Minimal Distance","Flight Link"], dtype = 'object')
        #records = dict()
        counter = 0
        fltcounter = 0
        for row in reader:

            # format of logfile is 0-ICAO,1-altitude,2-latitude,3-longitude,4-date,5-time,6-angle,7-distance,8-squawk,9-ground_speed(kilometerph),10-track,11-callsign
            # put the row in variables for better code readability
            icao, raw_alt, lat, lon, date, time, angle, raw_dist, squawk, speed, track, callsign = row

            callsign = callsign.strip()

            alt=999999
            dist=999999

            if len(icao) == 6:
                # first safely convert the distance and altitude values from the row into a float.
                # if we can't convert it into a number (e.g., it's text, not a number) then substitute it by some large number
                try:
                    dist = float(raw_dist)
                except:
                    pass

                try:
                    alt = float(raw_alt) - float(altcorr)
                except:
                    pass


            # now check if it's a duplicate that is in range
            if icao in records and dist <= maxdist and alt <= maxalt:

                # first check if we already have a flight number. If we don't, there may be one in the updated record we could use?
                if records[np.where(records == icao)[0][0]][1] == "" and callsign != "":
                    records[np.where(records == icao)[0][0]][1] = callsign

                if trackservice == 'flightaware':
                    falink = 'https://flightaware.com/live/modes/' + icao.lower() + '/ident/' + callsign + '/redirect'

                if trackservice == 'adsbexchange':
                    # format example: https://globe.adsbexchange.com/?icao=a4a567&lat=42.397&lon=-71.177&zoom=12.0&showTrace=2020-08-12
                    falink = get_ax_link(icao, row, lat, lon, date, time)

                records[np.where(records == icao)[0][0]][6] = falink.strip()

                # replace "LastHeard" by the time in this row:
                records[np.where(records == icao)[0][0]][3] = date + ' ' + time[:8]

                # only replace the lowest altitude if it's smaller than what we had before
                if alt < float(records[np.where(records == icao)[0][0]][4]):
                    records[np.where(records == icao)[0][0]][4] = "{:.0f}".format(alt)

                # only replace the smallest distance if it's smaller than what we had before
                if dist < float(records[np.where(records == icao)[0][0]][5]):
                    records[np.where(records == icao)[0][0]][5] =  "{:.1f}".format(dist)

            elif dist <= maxdist and alt <= maxalt:
                # it must be a new record. First check if it's in range. If so, write a new row to the records table:
                if verbose == 1:
                    print(counter, icao, callsign, "(", dist, "<=", maxdist, ", alt=", alt, "): new")
                    counter = counter + 1

                if trackservice == 'flightaware':
                    falink = 'https://flightaware.com/live/modes/' + icao.lower() + '/ident/' + callsign + '/redirect'

                if trackservice == 'adsbexchange':
                    falink = get_ax_link(icao, row, lat, lon, date, time)

                records=np.vstack([records, np.array([icao,callsign, date + ' ' + time[:8], date + ' ' + time[:8],"{:.0f}".format(alt),"{:.1f}".format(dist),falink.strip() ])])
                fltcounter = fltcounter + 1

            elif icao in records and records[np.where(records == icao)[0][0]][1] == "" and callsign != "":
                # we have the record, but it doesn't have a flight number and we now can add it
                records[np.where(records == icao)[0][0]][1] = callsign
                if verbose == 1:
                    print("added flight number", callsign, "for", icao)


        # Now, let's start writing everything to a CSV and/or HTML file:

        # delete the header as this interferes with appending:
        records = np.delete(records, (0), axis=0)

        # Write CSV file
        if fltcounter > 0:
            # make sure that the file has the correct extension
            if verbose == 1:
                print('Output is written to: ', outfile)

            # Now write the table to a file as a CSV file
            with open(outfile, 'w') as file:
                writer = csv.writer(file, delimiter=',')
                writer.writerows(records.tolist())
        else:
            if verbose == 1:
                print('Nothing to write to: ',outfile)

        # That's all, folks!


# this invokes the main function defined above:
if __name__ == "__main__":
    main(sys.argv[1:])
