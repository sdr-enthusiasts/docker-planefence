# Docker-Planefence

- [Docker-Planefence](#docker-planefence)
  - [What is it?](#what-is-it)
  - [Who is it for?](#who-is-it-for)
  - [Install PlaneFence - Prerequisites](#install-planefence---prerequisites)
    - [Getting ready](#getting-ready)
    - [Planefence Configuration](#planefence-configuration)
      - [Initial docker configuration](#initial-docker-configuration)
      - [Planefence Settings Configuration](#planefence-settings-configuration)
      - [Applying your setup](#applying-your-setup)
  - [What does it look like when it's running?](#what-does-it-look-like-when-its-running)
  - [API access to your data](#api-access-to-your-data)
    - [Introduction](#introduction)
    - [API parameters and usage examples](#api-parameters-and-usage-examples)
      - [Planefence Query parameters](#planefence-query-parameters)
      - [Plane-Alert Query parameters](#plane-alert-query-parameters)
  - [Troubleshooting](#troubleshooting)
  - [Getting help](#getting-help)


## What is it?

This repository contains Planefence, which is an add-on to `ultrafeeder`, `readsb`, `dump1090`, or `dump1090-fa` (referred to herein as `your Feeder Station`.

Planefence will create a log of aircraft heard by your Feeder Station that are within a "fence", that is, less than a certain distance and lower than a certain
altitude from your station. This log is displayed on a website and is also made available in daily CSV files.
Furthermore, Planefence can send a notification for every plane in the fence to Mastodon, Discord, and/or Twitter, and with some add-on software/hardware, you will be able to collect noise figures to see how loud the aircraft are that fly above your Feeder Station.

Planefence is deployed as a Docker container and is pre-built for the following architectures:

- linux/ARMv7 (armhf): Raspberry Pi 3B+ / 4B with 32 bits Debian 10 Linux or later (RaspOS, Armbian, DietPi, etc.)
- linux/ARM64: Raspberry Pi 4B with 64 bits Debian OS 10 or later (RaspOS, Armbian, DietPi, Ubuntu, etc.)
- linux/AMD64: 64-bits PC architecture (Intel x86 or AMD) running Debian 10 Linux or later (incl. Ubuntu)

The Docker container is available at `ghcr.io/sdr-enthusiasts/docker-planefence` and can be pulled directy using this Docker command: `docker pull ghcr.io/sdr-enthusiasts/docker-planefence`.

## Who is it for?

Here are some assumptions or prerequisites:

- You are already familiar the `dump1090` family of ADS-B software (for example, `ultrafeeder`, `readsb`, `tar1090`, `dump1090`, or `dump1090-fa`), how to deploy it, and the hardware needed. Ideally, you have your ADS-B station already up and running.
- You know how to deploy Docker images to your machine. If you don't -- it's actually quite simple. It makes installation of new components really easy. [Mikenye's excellent Gitbook](https://mikenye.gitbook.io/ads-b/) contains a step-by-step guide, and [here](https://github.com/sdr-enthusiasts/docker-install) you can find a quick install script.
- You use `docker-compose`. This README has been written assuming `docker-compose`. If you don't have it, feel free to `apt-get install` it. It should be easy to convert the `docker-compose.yml` instructions to a command-line `docker run` string, but you are on your own to do this.
- Further support is provided at the #planefence channel at the [SDR Enthusiasts Discord Server](https://discord.gg/VDT25xNZzV). If you need immediate help, please tag "@k1xt" to your message.

## Install PlaneFence - Prerequisites

Note - this guide assumes that `/home/pi` is your home directory. If it is not (for example, Ubuntu builds use `/home/ubuntu` as their default account), please change all mentions of `/home/pi` to the applicable home directory path.

There must already be an instance of `ultrafeeder`, `tar1090`, `dump1090[-fa]`, or `readsb` connected to a SDR somewhere in reach of your Planefence machine:

- This could be in the same stack of containers, separately on the same machine, or even on another machine.
- It is important to enable SBS data on port 30003 on that instance. PlaneFence will use this to get its data. See the Troubleshooting section for help to get this done

### Getting ready

1. If you are adding this to an existing stack of docker containers on your machine, you can add the information from this project to your existing `docker-compose.yml`.
2. If you are not adding this to an existing container stack, you should create a project directory: `sudo mkdir -p /opt/planefence && sudo chmod a+rwx /opt/planefence && cd /opt/planefence` . Then add a new `docker-compose.yml` there.
3. Get the template Docker-compose.yml file from here:

```bash
curl -s https://raw.githubusercontent.com/sdr-enthusiasts/docker-planefence/main/docker-compose.yml > docker-compose.yml
```

### Planefence Configuration

#### Initial docker configuration

In the `docker-compose.yml` file, you should configure the following:

- IMPORTANT: The image, by default, points at the release image. For the DEV version, change this: `image: ghcr.io/sdr-enthusiasts/docker-planefence:dev`
- IMPORTANT: Update `TZ=America/New_York` to whatever is appropriate for you. Note that this variable is case sensitive
- There are 2 volumes defined. My suggestion is NOT to change these unless you know what you are doing
- After you exit the editor, start the container (`docker-compose up -d`). The first time you do this, it can take a minute or so.
- Monitor the container (`docker logs -f planefence`). At first start-up, it should be complaining about not being configure. That is expected behavior.
- Once you see the warnings about `planefence.config` not being available, press CTRL-C to get the command prompt.

#### Planefence Settings Configuration

- After you start the container for the first time, it will create a few directories with setup files. You MUST edit these setup files before things will work!
- MANDATORY: First -- copy the template config file in place: `sudo cp /opt/adsb/planefence/config/planefence.config-RENAME-and-EDIT-me /opt/adsb/planefence/config/planefence.config`
- MANDATORY: `sudo nano /opt/adsb/planefence/config/planefence.config` Go through all parameters - their function is explained in this file. Edit to your liking and save/exit using `ctrl-x`. THIS IS THE MOST IMPORTANT AND MANDATORY CONFIG FILE TO EDIT !!!
- OPTIONAL: `sudo nano /opt/adsb/planefence/config/planefence-ignore.txt`. In this file, you can add aircraft that PlaneFence will ignore. If there are specific planes that fly too often over your home, add them here. Use 1 line per entry, and the entry can be a ICAO, flight number, etc. You can even use regular expressions if you want. Be careful -- we use this file as an input to a "grep" filter. If you put something that is broad (`.*` for example), then ALL PLANES will be filtered out.
- OPTIONAL: `sudo nano /opt/adsb/planefence/config/airlinecodes.txt`. This file maps the first 3 characters of the flight number to the names of the airlines. We scraped this list from a Wikipedia page, and it is by no means complete. Feel free to add more to them -- please add an issue at https://github.com/sdr-enthusiasts/docker-planefence/issues so we can add your changes to the default file.
- OPTIONAL: If you configured Twitter support before, `sudo nano /opt/adsb/planefence/config/.twurlrc`. You can add your back-up TWURLRC file here, if you want.
- OPTIONAL: Configure tweets to be sent. For details, see these instructions: https://github.com/kx1t/docker-planefence/blob/main/README-planetweet.md
- OPTIONAL: `sudo nano /opt/adsb/planefence/config/plane-alert-db.txt`. This is the list of tracking aircraft of Plane-Alert. It is prefilled with the planes of a number of "interesting" political players. Feel free to add your own, delete what you don't want to see, etc. Just follow the same format.
- OPTIONAL: If you have multiple containers running on different web port, and you would like to consolidate them all under a single host name, then you should consider installing a "reverse web proxy". This can be done quickly and easily - see instructions [here](https://github.com/kx1t/docker-planefence/README-nginx-rev-proxy.md).
- OPTIONAL: If you have a soundcard and microphone, adding NoiseCapt is as easy as hooking up the hardware and running another container. You can add this to your existing `docker-compose.yml` file, or run it on a different machine on the same subnet. Instructions are [here](https://github.com/kx1t/docker-noisecapt/).
- OPTIONAL for Plane-Alert: You can add custom fields, that (again optionally) are displayed on the Plane-Alert list. See [this discussion](https://github.com/kx1t/docker-planefence/issues/38) on how to do that.
- OPTIONAL: The website will apply background pictures if you provide them. Save your .jpg pictures as `/opt/adsb/planefence/config/pf_background.jpg` for Planefence and `/opt/adsb/planefence/config/pa_background.jpg` for Plane-Alert. (You may have to restart the container or do `touch /opt/adsb/planefence/config/planefence.config` in order for these backgrounds to become effective.)
- OPTIONAL: Add images of tar1090 to your Tweets in Planefence and Plane-Alert. In order to enable this, simply add the `pf-screenshot` section to your `Docker-compose.yml` file as per the example in this repo's [`docker-compose.yml`](https://github.com/sdr-enthusiasts/docker-planefence/blob/main/docker-compose.yml) file. Note - to simplify configuration, Planefence assumes that the hostname of the screenshotting image is called `pf-screenshot` and that it's reachable under that name from the Planefence container stack.
- OPTIONAL: Show [OpenAIP](http://map.openaip.net) overlay on Planefence web page heatmap. Enable this by setting the option `PF_OPENAIP_LAYER=ON` in `/opt/adsb/planefence/config/planefence.config`

---

#### Plane-Alert Exclusions

In some circumstances you may wish to blacklist certain planes, or types of planes, from appearing in Plane-Alert and its Mastodon and Discord posts. This may be desireable if, for example, you're located near a military flight training base, where you could be flooded with dozens of notifications about T-6 Texan training aircraft every day, which could drown out more interesting planes. To that end, excluding planes can be accomplished using the `PA_EXCLUSIONS=` parameter in `/opt/adsb/planefence/config/planefence.config`. Currently, you may exclude whole ICAO Types (such as `TEX2` to remove all T-6 Texans), specific ICAO hexes (e.g. `AE1ECB`), specific registrations and tail codes (e.g. `N24HD` or `92-03327`), or any freeform string (e.g. `UC-12`, `Mayweather`, `Kid Rock`). Multiple exclusions should be separated by commas. It is case insensitive. An example:
```yml
PA_EXCLUSIONS=tex2,AE06D9,ae27fe,Floyd Mayweather,UC-12W
```
This would exclude *all* T-6 Texans, the planes with ICAO hexes `AE06D9` (a Marine Corps UC-12F Huron) and `AE27FE` (a Coast Guard MH-60T), any planes with "Floyd Mayweather" anywhere in the database entry, and any planes with "UC-12W" anywhere in the database entry. URLs and image links are intentionally not searched.

*Please note:* this is a **powerful feature** which may produce unintended consequences. You should verify that it's working correctly by examining the container logs after making changes to `planefence.config`. You should see, e.g.:
```
tex2 appears to be an ICAO type and is valid, entries excluded: 479
AE06D9 appears to be an ICAO hex and is valid, entries excluded: 1
ae27fe appears to be an ICAO hex and is valid, entries excluded: 1
Floyd Mayweather appears to be a freeform search pattern, entries excluded: 1
UC-12W appears to be a freeform search pattern, entries excluded: 8
490 entries excluded.
```

Also note that after adding exclusions, any pre-existing entries for those excluded planes in your Plane Alert web user interface will not be entirely removed, but some fields will disappear. If you've made a mistake and revert your exclusion changes to `planefence.config`, affected entries in your web user interface will be fully restored after a few minutes.

---

#### Applying your setup

- If you made a bunch of changes for the first time, you should restart the container. In the future, most updates to `/opt/adsb/planefence/config/planefence.config` will be picked up automatically
- You can restart the Planefence container by doing: `pushd /opt/adsb && docker-compose up -d planefence --force-recreate && popd`

## What does it look like when it's running?

- Planefence deployment example: https://planefence.com/planefence
- Plane-Alert deployment example: https://planefence.com/plane-alert
- Mastodon notifications: https://airwaves.social/@planeboston

## API access to your data

### Introduction

Planefence and Plane-Alert keep a limited amount of data available. By default, PlaneFence keeps 2 weeks of data around, while Plane-Alert isn't time limited. This data is accessible using a REST interface that makes use of HTTP GET. You can access this API from the directory where your Planefence or Plane-Alert web pages are deployed. For example:

- If Planefence is available at https://planefence.com/planefence, then you can reach the Planefence API at https://planefence.com/planefence/pf-query.php
- If Plane-Alert is available at https://planefence.com/plane-alert, then you can reach the Plane-Alert API at https://planefence.com/plane-alert/pa-query.php

### API parameters and usage examples

The Planefence and Plane-Alert APIs accept awk-style Regular Expressions as arguments. For example, a tail number starting with N, followed by 1 digit, followed by 1 or more digits or letters would be represented by this RegEx: `n[0-9][0-9A-Z]*` .  Querie arguments are case-insensitive: looking for `n` or for `N` yield the same results.
Each query must contain at least one of the parameters listed below. Optionally, the `type` parameter indicates the output type. Accepted values are `json` or `csv`; if omitted, `json` is the default value. (These argument values must be provided in lowercase.)
Note that the `call` parameter (see below) will start with `@` followed by the call (tail number or flight number as reported via ADS-B/MLAT/UAT) if the entry was tweeted. So make sure to start your `call` query with `^@?` to include both tweeted an non-tweeted calls.
#### Planefence Query parameters
| Parameter | Description | Example |
|---|---|---|
| `hex` | Hex ID to return | https://planeboston.com/planefence/pf_query.php?hex=^A[AB][A-F0-9]*&type=csv returns a CSV with any Planefence records of which the Hex IDs that start with A, followed by A or B, followed by 0 or more hexadecimal digits |
| `tail` | Call sign (flight number or tail) to return | https://planeboston.com/planefence/pf_query.php?call=^@?AAL[0-9]*&type=json returns any flights of which the call starts with "AAL" or "@AAL" followed by only numbers. (Note - the call value will start with `@` if the entry was tweeted, in which case the `tweet_url` field contains a link to the tweet.) |
| `start` | Start time, format `yyyy/MM/dd hh:mm:ss` | https://planeboston.com/planefence/pf_query.php?start=2021/12/19.*&type=csv returns all entries that started on Dec 19, 2021. |
| `end` | End time, format `yyyy/MM/dd hh:mm:ss` | https://planeboston.com/planefence/pf_query.php?end=2021/12/19.*&type=csv returns all entries that ended on Dec 19, 2021. |

#### Plane-Alert Query parameters

| Parameter | Description | Example |
|---|---|---|
| `hex` | Hex ID to return | https://planeboston.com/plane-alert/pa_query.php?hex=^A[EF][A-F0-9]*&type=csv returns a CSV with any Planefence records of which the Hex IDs that start with A, followed by E or F, followed by 0 or more hexadecimal digits. (Note - this query returns most US military planes!) |
| `tail` | Tail number of the aircraft | https://planeboston.com/plane-alert/pa_query.php?tail=N14[0-9]NE&type=csv returns any records of which the tail starts with "N14", followed by 1 digit, followed by "NE". |
| `name` | Aircraft owner's name | https://planeboston.com/plane-alert/pa_query.php?name=%20Life\|%20MedFlight&type=csv returns any records that have " Life" or " MedFlight" in the owner's name. |
| `equipment` | Equipment make and model | https://planeboston.com/plane-alert/pa_query.php?equipment=EuroCopter returns any records of which the equipment contains the word "EuroCopter" |
| `timestamp` | Time first seen, format `yyyy/MM/dd hh:mm:ss` | https://planeboston.com/plane-alert/pa_query.php?timestamp=2022/01/03 returns any records from Jan 3, 2022. |
| `call` | Callsign as reported by aircraft | https://planeboston.com/plane-alert/pa_query.php?call=SAM returns any records of which the callsign contains "SAM". |
| `lat` | Latitude first observation, in decimal degrees | https://planeboston.com/plane-alert/pa_query.php?lat=^43 returns any records of which the latitude starts with "43" (i.e., 43 deg N) |
| `lon` | Longitude first observation, in decimal degrees | https://planeboston.com/plane-alert/pa_query.php?lon=^-68 returns any records of which the longitude starts with "-68" (i.e., 68 deg W) |

## Troubleshooting

- Be patient. Some of the files won't get initialized until the first "event" happens: a plane is in PlaneFence range or is detected by Plane-Alert. This includes the planes table and the heatmap.
- If your system doesn't behave as expected: check, check, double-check. Did you configure the correct container in `docker-compose.yml`? Did you edit the `planefence.config` file?
- Check the logs: `docker logs -f planefence`. Some "complaining" about lost connections or files not found is normal, and will correct itself after a few minutes of operation. The logs will be quite explicit if it wants you to take action
- Check the website: http://myip:8088 should update every 80 seconds (starting about 80 seconds after the initial startup). The top of the website shows a last-updated time and the number of messages received from the feeder station.
- Plane-alert will appear at http://myip:8088/plane-alert
- Twitter setup is complex and Elon will ban you if you publish anything about one of his planes. [Here](https://github.com/sdr-enthusiasts/docker-planefence#setting-up-tweeting)'s a description on what to do. We advice you to skip Twitter and send notifications to [Mastodon](https://github.com/sdr-enthusiasts/docker-planefence/README-Mastodon.md) instead.
- Error "We cannot reach {host} on port 30003". This could be caused by a few things:
  - Did you set the correct hostname or IP address in `PF_SOCK30003HOST` in `planefence.config`? This can be either an IP address, or an external hostname, or the name of another container in the same stack.
  - Did you enable SBS (BaseStation -- *not* Beast!) output? Here are some hints on how to enable this:
   - For non-containerized `dump1090[-fa]`/`readsb`/`tar1090`: add command line option `--net-sbs-port 30003`
   - For containerized `readsb-protobuf`: add to the `environment:` section of your `docker-compose.yml` file:
  
      ```yaml
            - READSB_NET_SBS_OUTPUT_PORT=30003
            - READSB_EXTRA_ARGS=--net-beast-reduce-interval 2 --net-sbs-reduce
      ```

    - For users of the `ultrafeeder` container, no additional changes should be needed (see below for enabling MLAT aircraft)
    - if you are using a different container stack, then you should also add `- 30003:30003` to the `ports:` section
   - For users of `ultrafeeder`, if you want to enabled MLAT, make sure to set the following parameter in the `ultrafeeder` environment variables: `- READSB_FORWARD_MLAT_SBS=true`

## Getting help

- If you need further support, please join the #planefence channel at the [SDR Enthusiasts Discord Server](https://discord.gg/VDT25xNZzV) and look for "@kx1t" to your message. Alternatively, email me at kx1t@amsat.org.

That's all!

![](https://media.giphy.com/media/3oKHWikxKFJhjArSXm/giphy.gif)
