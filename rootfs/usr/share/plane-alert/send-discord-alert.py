#!/usr/bin/env python
# Send Discord Alert is a utility for PLANE-ALERT
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
import os
import csv
import shutil
import tempfile

import discord
import requests


def testmsg(msg):
    if os.getenv('TESTING') == 'true':
        print(msg)


# Read the alerts in the input file
def load_alerts(alerts_file):
    alerts = []
    with open(alerts_file) as csvfile:
        reader = csv.reader(csvfile)
        for row in reader:
            # Skip header
            if len(row) < 10:
                continue
            # CSV format is:
            #      ICAO,TailNr,Owner,PlaneDescription,date,time,lat,lon,callsign,adsbx_url,squawk
            alerts.append({
                "icao": row[0],
                "tail_num": row[1],
                "owner": row[2],
                "plane_desc": row[3],
                "date": row[4],
                "time": row[5],
                "lat": row[6],
                "long": row[7],
                "callsign": row[8],
                "adsbx_url": row[9],
                "squawk": row[10]
            })

    testmsg(f"Loaded {len(alerts)} alerts")
    return alerts


def main():
    # Load configuration
    if len(sys.argv) != 2:
        print("No input file passed\n\tUsage: ./send-discord-alert.py <inputfile>")
        sys.exit(1)

    input_file = sys.argv[1]
    token = os.getenv('DISCORD_TOKEN')
    server_id = int(os.getenv('DISCORD_SERVER_ID', 0))
    channel_id = int(os.getenv('DISCORD_CHANNEL_ID', 0))
    screenshot_url = os.getenv('SCREENSHOTURL')

    # Validate configuration
    if token is None:
        print("Missing DISCORD_TOKEN")
        sys.exit(1)

    if server_id == 0:
        print("Missing DISCORD_SERVER_ID")
        sys.exit(1)

    if channel_id == 0:
        print("Missing DISCORD_CHANNEL_ID")
        sys.exit(1)

    # TODO: Move alert generation out here.

    # Set up the Discord client
    client = discord.Client()

    @client.event
    async def on_ready():
        server = discord.utils.get(client.guilds, id=server_id)

        testmsg(f"{client.user.name} has connected to {server.name}")
        channel = server.get_channel(channel_id)

        alerts = load_alerts(input_file)
        for plane in alerts:
            # Build the Embed object with the sighting details
            embed = discord.Embed(title=f"Plane Alert - {plane['plane_desc']}", color=0x007bff, description=f"[Tracking Link]({plane['adsbx_url']})")
            embed.add_field(name="ICAO", value=f"{plane['icao']}", inline=True)
            embed.add_field(name="Tail Number", value=f"{plane['tail_num']}", inline=True)
            embed.add_field(name="Callsign", value=f"{plane['callsign']}", inline=True)
            embed.add_field(name="Owner", value=f"{plane['owner']}", inline=True)
            embed.add_field(name="Seen At", value=f"{plane['date']} {plane['time']}", inline=True)
            if plane.get('squawk', "") != "":
                embed.add_field(name="Squawk", value=f"{plane['squawk']}", inline=True)

            embed.set_footer(text="Planefence by kx1t - docker:kx1t/planefence")

            # Get a screenshot to attach if configured
            screenshot = None
            tmp = None
            if screenshot_url is not None:
                testmsg(f"Getting Screenshot for {plane['icao']}...")
                snap_response = requests.get(f"{screenshot_url}/snap/{plane['icao']}", stream=True, timeout=45.0)
                testmsg("Screenshot Got!")
                if snap_response.status_code == 200:
                    tmp = tempfile.NamedTemporaryFile(suffix=".png")
                    with open(tmp.name, 'wb') as f:
                        snap_response.raw.decode_content = True
                        shutil.copyfileobj(snap_response.raw, f)

                        screenshot = discord.File(tmp.name)
                    testmsg(f"Screenshot written to {tmp.name}")

            # Send the message
            await channel.send(embed=embed, file=screenshot)

            # Cleanup
            if tmp is not None:
                tmp.close()

        await client.close()

    # Connect to Discord and send the messages
    client.run(token)

    print(f"Done sending alerts to Discord")


if __name__ == "__main__":
    main()
