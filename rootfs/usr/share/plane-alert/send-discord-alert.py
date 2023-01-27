#!/usr/bin/env python3

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
import csv

import pflib as pf

# Human readable location stuff
from geopy.geocoders import Nominatim
geolocator = Nominatim(user_agent="plane-alert")

def get_readable_location(plane):
    loc = geolocator.reverse("{}, {}".format(plane['lat'], plane['long']), exactly_one=True, language='en')
    if loc is None:
        pf.log("[error] No geolocation information return for '{}, {}'".format(plane['lat'], plane['long']))
        return ""

    adr = loc.raw.get('address', {})

    print("Location data:")
    print(adr)

    village = adr.get('village', "")
    municipality = adr.get('municipality', "")
    city = adr.get('city', "")
    town = adr.get('town', "")
    country = adr.get('country', "")
    country_code = adr.get('country_code', "").upper()

    place = city or town or village or municipality

    if country_code == "US":
        state = pf.get_us_state_abbrev(adr.get('state', ""))

        return f"{place}, {state}, {country_code}"
    else:
        return f"{place}, {country}"

def process_alert(config, plane):
    pf.log(f"Building Discord alert for {plane['icao']}")

    dbinfo = pf.get_plane_info(plane['icao'])

    fa_link = pf.flightaware_link(plane['icao'], plane['tail_num'])

    title = f"Plane Alert - {plane['plane_desc']}"
    color = 0xf2e718
    squawk = plane.get('squawk', "")
    if pf.is_emergency(squawk):
        title = f"Air Emergency! {plane['tail_num']} squawked {squawk}"
        color = 0xff0000

    description = f""
    if plane.get('owner', "") != "":
        description = f"Operated by **{plane.get('owner')}**"

    location = get_readable_location(plane)
    if location == "":
        # No location info, just embed ADSBX link
        description += f"\nTrack on [ADSB Exchange]({plane['adsbx_url']})"
    else:
        description += f"\nSeen near [**{location}**]({plane['adsbx_url']})"

    webhooks, embed = pf.discord.build(config["DISCORD_FEEDER_NAME"], config["PA_DISCORD_WEBHOOKS"], title, description, color=color)
    pf.attach_media(config, "PA", dbinfo, webhooks, embed)

    # Attach data fields
    pf.discord.field(embed, "ICAO", plane['icao'])
    pf.discord.field(embed, "Tail Number", f"[{plane['tail_num']}]({fa_link})")

    if plane.get('callsign', "") != "":
        pf.discord.field(embed, "Callsign", plane['callsign'])

    if plane.get('time', "") != "":
        pf.discord.field(embed, "First Seen", f"{plane['time']} {pf.get_timezone_str()}")

    if dbinfo.get('category', "") != "":
        pf.discord.field(embed, "Category", dbinfo['category'])

    if dbinfo.get('tag1', "") != "":
        pf.discord.field(embed, "Tag", dbinfo['tag1'])

    if dbinfo.get('tag2', "") != "":
        pf.discord.field(embed, "Tag", dbinfo['tag2'])

    if dbinfo.get('tag3', "") != "":
        pf.discord.field(embed, "Tag", dbinfo['tag3'])

    if dbinfo.get('link', "") != "":
        pf.discord.field(embed, "Link", f"[Learn More]({dbinfo['link']})")

    # Send the message
    pf.send(webhooks, config)


def main():
    pf.init_log("plane-alert/send-discord-alert")

    # Load configuration
    config = pf.load_config()

    if len(sys.argv) != 2:
        print("No input record passed\n\tUsage: ./send-discord-alert.py <csvline>")
        sys.exit(1)

    # CSV format is:
    #      ICAO,TailNr,Owner,PlaneDescription,date,time,lat,lon,callsign,adsbx_url,squawk
    row = sys.argv[1].split(',')
    alert = {
        "icao": row[0].strip(),
        "tail_num": row[1].strip(),
        "owner": row[2].strip(),
        "plane_desc": row[3],
        "date": row[4],
        "time": row[5],
        "lat": row[6],
        "long": row[7],
        "callsign": row[8].strip(),
        "adsbx_url": row[9],
        "squawk": row[10] if len(row) > 10 else "",
    }

    # Process file and send alerts
    process_alert(config, alert)

    pf.log(f"Done sending Discord alert for {alert['icao']}")


if __name__ == "__main__":
    main()
