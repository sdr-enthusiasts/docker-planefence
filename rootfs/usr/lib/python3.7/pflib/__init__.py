# Python3 module of functions for Plane Fence and Plane Alert
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

import os
import tempfile
import shutil

import discord
import requests


class InvalidConfigException(Exception):
    pass


def testmsg(msg):
    if os.getenv("TESTING") == "true":
        print(msg)


def log(msg):
    # TODO: Setup proper logging
    print(msg)


def load_discord_config():
    """
    Expected environment variables:
        DISCORD_TOKEN
        DISCORD_SERVER_ID
        DISCORD_CHANNEL_ID
        SCREENSHOTURL

    :return: dict[string]any
    """
    config = {
        "token": os.getenv("DISCORD_TOKEN"),
        "server_id": int(os.getenv("DISCORD_SERVER_ID", 0)),  # TODO: Safer conversion 
        "channel_id": int(os.getenv("DISCORD_CHANNEL_ID", 0)),  # TODO: Safer conversion
        "screenshot_url": os.getenv("SCREENSHOTURL")
    }
    
    # Validate configuration
    if config["token"] is None:
        log("Missing DISCORD_TOKEN")
        raise InvalidConfigException

    if config["server_id"] == 0:
        log("Missing DISCORD_SERVER_ID")
        raise InvalidConfigException

    if config["channel_id"] == 0:
        log("Missing DISCORD_CHANNEL_ID")
        raise InvalidConfigException

    return config


def run_client(callback, *cbargs):
    """
    :param callback: function(config, channel, ...)
    :param cbargs: Any arguments that you want passed in to the callback.
    :return: None
    """
    config = load_discord_config()
    client = discord.Client()

    @client.event
    async def on_ready():
        server = discord.utils.get(client.guilds, id=config['server_id'])
        channel = server.get_channel(config['channel_id'])

        log(f"{client.user.name} has connected to {server.name}")

        try:
            callback(config, channel, *cbargs)
        finally:
            await client.close()


def get_screenshot_file(config, icao):
    testmsg(f"Getting Screenshot for {icao}...")
    snap_response = requests.get(f"{config['screenshot_url']}/snap/{icao}", stream=True, timeout=45.0)
    testmsg("Screenshot Got!")

    if snap_response.status_code == 200:
        tmp = tempfile.NamedTemporaryFile(suffix=".png")
        with open(tmp.name, 'wb') as f:
            snap_response.raw.decode_content = True
            shutil.copyfileobj(snap_response.raw, f)

        testmsg(f"Screenshot written to {tmp.name}")
        return discord.File(tmp.name)
    else:
        log(f"[Error] - Non-200 response from screenshot container: {snap_response.status_code}")
        return None
