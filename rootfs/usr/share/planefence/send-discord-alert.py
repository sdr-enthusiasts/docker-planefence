#!/usr/bin/env python3

# Send Discord Alerts is a utility for PlaneFence
#
# Usage: ./send-discord-alert.py <inputfile>
#
# Copyright 2022 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/planefence/
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
                "icao": row[0],
                "tail_num": row[1],
                "first_seen": row[2],
                "last_seen": row[3],
                "alt": row[4],
                "min_dist": row[5],
                "adsbx_url": row[6],
            }
            alerts.append(alert)

    pf.log(f"Loaded {len(alerts)} fence alerts")
    return alerts


async def process_alert(config, channel, plane):
    pf.log(f"Building discord message for {plane['icao']}")

    # Gather up some info for the message
    name = plane['tail_num']
    if plane["airline"] != "":
        name = plane['airline']

    altstr = "{:,}".format(int(plane['alt']))  # TODO: Safer conversion

    fa_link = f"https://flightaware.com/live/modes/{plane['icao']}/ident/{plane['tail_num']}]/redirect"

    embed = pf.embed.build(
        f"{name} is overhead at {altstr} MSL",  # TODO: ALTUNIT
        f"[Track on ADS-B Exchange]({plane['adsbx_url']})")

    # Attach data fields
    pf.embed.field(embed, "ICAO", plane['icao'])
    pf.embed.field(embed, "Tail Number", f"[{plane['tail_num']}]({fa_link})")
    pf.embed.field(embed, "Distance", f"{plane['min_dist']}nm")  # TODO: DISTUNIT
    pf.embed.field(embed, "First Seen", plane['first_seen'].split(" ")[1])

    # Get a screenshot to attach if configured
    screenshot = None
    if config.get('SCREENSHOTURL') is not None:
        screenshot = pf.get_screenshot_file(config, plane['icao'])

    # Send the message
    await channel.send(embed=embed, file=screenshot)


def main():
    pf.init_log("planefence/send-discord-alert")

    # Load configuration
    if len(sys.argv) < 2:
        print("No input file passed\n\tUsage: ./send-discord-alert.py <csvline> <airline?>")
        sys.exit(1)

    record = sys.argv[1].split(',')

    alert = {
        "icao": record[0],
        "tail_num": record[1].lstrip("@"),
        "first_seen": record[2],
        "last_seen": record[3],
        "alt": record[4],
        "min_dist": record[5],
        "adsbx_url": record[6],
        "airline": sys.argv[2] if len(sys.argv) == 3 else ""
    }
    pf.connect_discord(process_alert, alert)

    pf.log(f"Done sending alerts to Discord")


if __name__ == "__main__":
    main()
