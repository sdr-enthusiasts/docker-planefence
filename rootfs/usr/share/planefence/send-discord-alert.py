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
from datetime import date

import discord
import pflib as pf
pf.init_log("planefence/send-discord-alert")

# Dev Notes:
# Plane Alert DB contains mapping of ICAO code to tags: /usr/share/planefence/persist/plane-alert-db.txt
# Seems the input files are in: /usr/share/planefence/html
#   A new file every day named: planefence-yymmdd.csv
# Format:
# ICAO,Registration,FirstSeen,LastSeen,Alt,MinDist,adsbx_url,,,,,,tweet_url
#         Fields after adsbx_url are optional
#   If FlightNum has an @ prefixing the number it was tweeted

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

    log(f"Loaded {len(alerts)} fence alerts")
    return alerts


async def process_alerts(config, channel, alerts):
    for plane in alerts:
        log(f"Building discord message for {plane['icao']}")
        # Build the Embed object with the sighting details
        embed = discord.Embed(title=f"Plane Fence", color=0x007bff, description=f"[Track on ADS-B Exchange]({plane['adsbx_url']})")
        embed.add_field(name="ICAO", value=plane['icao'], inline=True)
        embed.add_field(name="Tail Number", value=plane['tail_num'], inline=True)
        embed.add_field(name="First Seen", value=plane['first_seen'], inline=True)
        embed.add_field(name="Last Seen", value=plane['last_seen'], inline=True)

        embed.set_footer(text="Planefence by kx1t - docker:kx1t/planefence")

        # Get a screenshot to attach if configured
        screenshot = None
        if config['screenshot_url'] is not None:
            screenshot = pf.get_screenshot_file(config, plane['icao'])

        # Send the message
        await channel.send(embed=embed, file=screenshot)


def main():
    # Load configuration
    if len(sys.argv) != 2:
        print("No input file passed\n\tUsage: ./send-discord-alert.py <inputfile>")
        sys.exit(1)

    input_file = sys.argv[1]
    alerts = load_alerts(input_file)

    pf.connect_discord(process_alerts, alerts)

    log(f"Done sending alerts to Discord")


if __name__ == "__main__":
    main()
