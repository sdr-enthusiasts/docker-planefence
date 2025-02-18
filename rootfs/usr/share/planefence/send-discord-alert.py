#!/command/with-contenv python3

# Send Discord Alerts is a utility for Planefence
#
# Usage: ./send-discord-alert.py <inputfile>
#
# Copyright 2022-2025 Ramon F. Kolb, kx1t
# Copyright 2022 Justin DiPierro
#
# Licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/planefence/
#
# The package contains parts of, and modifications or derivatives to the following:
# Dump1090.Socket30003 by Ted Sluis: https://github.com/tedsluis/dump1090.socket30003
# These packages may incorporate other software and license terms.
#
# Summary of License Terms
# This program is free software: you can redistribute it and/or modify it under the terms of
# the GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program.
# If not, see https://www.gnu.org/licenses/.

import sys
import csv

import pflib as pf


# Read the alerts in the input file
def load_alerts(alerts_file):
    alerts = []
    with open(alerts_file) as csvfile:
        reader = csv.reader(csvfile)
        for row in reader:
            # Format:
            # ICAO,Registration,FirstSeen,LastSeen,Alt,MinDist,adsbx_url,,,,,,tweet_url
            #         Fields after adsbx_url are optional
            #   If FlightNum has an @ prefixing the tail number it was tweeted
            alert = {
                "icao": row[0].strip(),
                "tail_num": row[1].strip(),
                "first_seen": row[2],
                "last_seen": row[3],
                "alt": row[4],
                "min_dist": row[5],
                "adsbx_url": row[6],
            }
            alerts.append(alert)

    pf.log(f"Loaded {len(alerts)} Planefence alerts")
    return alerts


def process_alert(config, plane):
    pf.log(f"Building discord message for {plane['icao']}")

    # Gather up some info for the message
    name = plane['tail_num']
    if plane["airline"] != "":
        name = plane['airline']
    
    try:
        if config['PF_TRACKSERVICE'] == "":
            trackservice="globe.adsbexchange.com"
            trackname="AdsbExchange"
        else:
            trackservice=config['PF_TRACKSERVICE']
            trackname=config['PF_TRACKSERVICE'].replace('https://','')
            trackname=trackname.replace('http://','')
            trackname=trackname.replace('www.','')
            trackname=trackname.replace('globe.','')
            trackname=trackname.replace('radar.','')
            trackname=trackname.replace('tar1090.','')
            trackname=trackname.replace('.com','')
            trackname=trackname.replace('.org','')
            trackname=trackname.replace('.net','')
            trackname=trackname.replace('/tar1090','')
            trackname=trackname.replace('/map','')
            trackname=trackname.replace('/radar','')
            trackname=trackname.replace('/','')
    except:
        trackservice="globe.adsbexchange.com"
        trackname="AdsbExchange"

    fa_link = pf.flightaware_link(plane['icao'], plane['tail_num'])

    webhooks, embed = pf.discord.build(
        config["DISCORD_FEEDER_NAME"],
        config["PF_DISCORD_WEBHOOKS"],
        f"{name} is overhead at {pf.altitude_str(config, plane['alt'])}",
        f"[Track on {trackname}]({plane['adsbx_url'].replace('globe.adsbexchange.com',trackservice)})")

    pf.attach_media(config, "PF", plane, webhooks, embed)

    # Attach data fields
    pf.discord.field(embed, "ICAO", plane['icao'])
    pf.discord.field(embed, "Tail Number", f"[{plane['tail_num']}]({fa_link})")
    pf.discord.field(embed, "Distance", f"{plane['min_dist']}{pf.distance_unit(config)}")

    time_seen = plane['first_seen'].split(" ")[1]
    pf.discord.field(embed, "First Seen", f"{time_seen} {pf.get_timezone_str()}")

    # Send the message
    pf.send(webhooks, config)


def main():
    pf.init_log("planefence/send-discord-alert")

    # Load configuration
    config = pf.load_config()

    if len(sys.argv) < 2:
        print("No input file passed\n\tUsage: ./send-discord-alert.py <csvline> <airline?>")
        sys.exit(1)

    record = sys.argv[1].split(',')

    alert = {
        "icao": record[0],
        "tail_num": record[1].lstrip("@"),
        "first_seen": record[2],
        "last_seen": record[3],
        "alt": int(record[4]) if record[4].isdigit() else 0,
        "min_dist": record[5],
        "adsbx_url": record[6],
        "airline": sys.argv[2] if len(sys.argv) == 3 else ""
    }

    process_alert(config, alert)

    pf.log(f"Done sending alerts to Discord")


if __name__ == "__main__":
    main()
