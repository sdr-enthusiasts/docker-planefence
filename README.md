# Docker-Planefence

## What is it?

This repository contains Planefence, which is an add-on to `readsb`, `dump1090`, or `dump1090-fa` (referred to herein as `your Feeder Station`.

Planefence will create a log of aircraft heard by your Feeder Station that are within a "fence", that is, less than a certain distance and lower than a certain
altitude from your station. This log is displayed on a website and is also made available in daily CSV files.
Furthermore, Planefence can send a Tweet for every plane in the fence, and (coming soon!) will be able to collect noise figures to see how loud the aircraft are that fly above your Feeder Station.

Planefence is deployed as a Docker container and is pre-built for the following architectures:
- linux/ARMv6 (armel): older Raspberry Pi's
- linux/ARMv7 (armhf): Raspberry Pi 3B+ / 4B with the standard 32 bits Raspberry OS (tested on Busted, may work but untested on Stretch or Jessie)
- linux/ARM64: Raspberry Pi 4B with Ubuntu 64 bits OS
- linux/AMD64: 64-bits PC architecture (Intel or AMD) running Debian Linux (incl. Ubuntu)
- linux/i386: 32-bits PC architecture (Intel or AMD) running Debian Linux (incl. Ubuntu)

The Docker container can be accessed on [Dockerhub (kx1t/planefence)](https://hub.docker.com/repository/docker/kx1t/planefence) and can be pulled directy using this Docker command: `docker pull kx1t/planefence`.

## Who is it for?
In order for you to use it, here are some assumptions or prerequisites:

- You are already familiar the `dump1090` family of ADS-B software (for example, `readsb`, `dump1090`, or `dump1090-fa`), how to deploy it, and the hardware needed. Ideally, you have your ADS-B station already up and running.
- You are able to access the software and install additional components.
- You know how to deploy Docker images to your machine. If you don't -- it's actually quite simple and makes installation of new components really easy. I advise you to read [Mikenye's excellent Gitbook](https://mikenye.gitbook.io/ads-b/) on the topic, which will show you step by step what to do.
- You use `docker-compose`. It's not hard to simply do `docker run` from a script, but this README has been written assuming `docker-compose`. If you don't have it, feel free to `apt-get install` it :)
- If you need further support, please join the #planefence channel at the [SDR Enthusiasts Discord Server](https://discord.gg/VDT25xNZzV). If you need immediate help, please add "@ramonk" to your message. 

## Deploying `docker-planefence`

The following instructions assume that you are working on a Raspberry Pi and that you already have the `docker` application installed. If you need help with this, instructions can be found [here](https://mikenye.gitbook.io/ads-b/setting-up-the-host-system/install-docker). 

There are 2 ways of deploying planefence -- as a stand-alone deployment where you still need to deploy a feeder station, or as part of an already existing dockerized installation of your feeder.

### Installing stand-alone
There is a sample `docker-compose` file and a sample `.env` file that contain all the deployment parameters you need. In addition, we need to prep a directory that will be linked to the directory ("volume") with the web and data files. This ensures that you can access them from the host machine, and that they will be super persistent across builds, so no information will get lost.

Follow these commands:
```
sudo mkdir -d /opt/planefence/Volumes/html/
sudo chown -R pi: /opt/planefence  # replace "pi" by the account you are using. On Ubuntu systems, this may be "ubuntu". Please leave the ":" in place! 
wget -O /opt/planefence/docker-compose.yml https://raw.githubusercontent.com/kx1t/docker-planefence/main/docker-compose.yml
wget -O /opt/planefence/.env https://raw.githubusercontent.com/kx1t/docker-planefence/main/.env-example
```
Now, and this is important, you MUST edit these two files before starting the docker container:
- `/opt/planefence/.env` contains all the variables about your station. You MUST SET THESE TO APPROPRIATE VALUES, otherwise things won't work. At a very minimum, you must adjust these: `FEEDER_ALT_FT`, `FEEDER_ALT_M`, `FEEDER_LAT`, `FEEDER_LONG`, `FEEDER_TZ`
- `/opt/planefence/docker-compose` contains a bunch of stuff regulating the docker container and how it communicates with the outside world. Specifically take note of these parameters and change them to your needs:
-- Under `services:` -> `planefence:`, there is a `ports` section. This has the syntax of `80:80`. The first number (left of the ":") indicates the port number the outside world sees. If you are already running a web server somewhere, you may want to change this to a different number. (Alternatively, you may forego the docker container's webservice altogether and use a web server on the host machine. See the description in the Advanced section below.)
-- If for any reason you didn't like the `/opt/planefence/Volumes/html/` directory and changed this in the command above, you should also change it in this file under `Services:` -> `Planefence:` -> `Volumes:`. Again, only change things LEFT of the ":". 

Once this is done, you can start the complete docker using:
```pushd /opt/planefence && docker-compose up -d && popd```

Congratulations, that's all! Browse to `http://your.ip:8088` to see the website, or browse the data in `/opt/planefence/Volumes/html/*.csv` !

### Adding to a previously deployed readsb[-protobuf]/dump1090[-fa] docker container or external machine
These instructions assume that you deployed Mikenye's dockerized containers for adsb as described in his [Gitbook](https://mikenye.gitbook.io/ads-b/). If you built your own container, the text below should be enough for you to figure out how to update your docker-compose file to add Planefence

1. Make sure you are running readsb or dump1090[-fa] with the option `--net-sbs-port=30003`. In a non-dockerized installation, you can edit the applicable file in `/etc/default`: either `dump1090`, or `dump1090-fa`, or `readsb`. In Mikenye's dockerized version of `readsb`, add the following to `docker-compose.yml` in the `environment:` section: `- READSB_NET_SBS_OUTPUT_PORT=30003`.
2. Copy the relevant parts from the [`docker-compose.yml` sample file](https://raw.githubusercontent.com/kx1t/docker-planefence/main/docker-compose.yml) to your own `docker-compose.yml`. SPecifically, add `planefence:` to the `volumes:` section and add the entire `planefence:` section that is shown under `services:` in the sample file.
3. Add the variable from the [`.env` sample file](https://raw.githubusercontent.com/kx1t/docker-planefence/main/.env-example) to your existing `.env` file, or copy the file in its entirety (and edit it!) if it doesn't already exist.
4. Expose the port 30003 on the container that runs the feeder. This will automatically make that port available to the planefence container
5. If you are running your feeder on a different machine (or in a different group), you will need to do two things:
-- ensure that the feeder installation exposes SBS on port 30003
-- update your `.env` file for planefence and put the hostname or IP address of the machine that provides the SBS output in the `PF_SOCK30003HOST` parameter, for example `PF_SOCK30003HOST=192.168.0.25`.


## Advanced configuration

### Setting up Tweeting

Planefence can send out a Tweet everytime an aircraft enters the fence. In order to do so, you need to apply for a Twitter Developer Account, create an application on your Twitter Dev account, get some keys, and run a bit of configuration. This is a one-time thing, so even it if sounds complicated, at least it needs to be done only once! Follow these steps:
1. Go to https://apps.twitter.com/app/new . Sign in with your Twitter account, apply for a developer account, and create a new app. A couple of hints:

-- If you need help, [here](https://elfsight.com/blog/2020/03/how-to-get-twitter-api-key/)'s a webpage with an excellent graphical walk-through of what you need to do.

-- Create a new application and provide some answers. Your application will be for "hobbyist" use, it's a "bot", and just provide a description of why you'd like to tweet about planes flying over your house. 

-- Make sure you have a mobile phone number registered with your account. Without it, you can't get "write" (i.e., send Tweets) permissions.  If your carrier is not supported by Twitter and you are unable to add a number, contact Twitter using https://support.twitter.com/forms/platform, selecting the last checkbox. Some users have reported success adding their number using the mobile site, https://mobile.twitter.com/settings, which seems to bypass the carrier check at the moment.

-- Request Read, Write, and Send Direct Messages access. If you don't, the logs will full up with errors ("Error processing your OAuth request: Read-only application cannot POST").

-- Keep the page with your Consumer API keys open - you will need them in the next step. Copy the Consumer API Key and Consumer API Key Secret somewhere -- it's a hassle if you lose them as you'll have to regenerate them and re-authorize the application.

2. Edit your /opt/planefence/.env file and make sure that PF_TWEET=ON

3. Restart the container (`docker-compose up -d`)

4. Remember your Twitter Consumer API Key and Consumer API Key Secret? You need them now!

5. Run this from your host system's command line: `docker exec -it planefence /root/config_tweeting.sh`

6. Follow the instructions. Make a BACK UP of your Cons Key / Secret and make a BACK UP of the config file.

7. Make a backup of your configuration file: `docker cp planefence:/root/.twurlrc .` -- you should save the `.twurlrc` file in a safe spot.

8. If you ever need to restore this file (for example, when you lose your config because you had to recreate the container), you can restore this configuration file by giving the "reverse" command: `docker cp .twurlrc planefence:/root/`


### External web service

If you want, you can use web server based on the host instead of using the web server inside the docker container. You'd do this on a machine that hosts several web pages, so you can map things like http://my.ip/tar1090 - http://my.ip/skyview - http://my.ip/planefence - etc.
To configure this:
1. remove the port mapping from `docker-compose.yml`. Note -- you cannot leave an empty `ports:` section in this file, you may have to remove (or comment out) that too. Also note - you can leave this in, but in that case your website will still be rendered to the port you originally set up.
2. Map a web directory to `/opt/planefence/Volumes/html/`. If your host is using `lighttpd`, [here](https://raw.githubusercontent.com/kx1t/docker-planefence/main/planefence/88-planefence-on-host.conf) is a handy lighttpd mod with some instructions on how you can do this.

### Build your own container
This repository contains a Dockerfile that can be used to build your own.
1. Pull the repository and issue the following command from the base directory of the repo:
`docker build --compress --pull --no-cache -t kx1t/planefence .`
2. Then simply restart the container with `pushd /opt/planefence && docker-compose up -d && popd`

# Acknowledgements, Attributions, and License
I would never have been able to do this without the huge contributions of [Mikenye](http://github.com/mikenye), [Fredclausen](http://github.com/fredclausen), and [Wiedehopf](http://github.com/wiedehopf). Thank you very much!

## Attributions
The package contains parts of, and modifications or derivatives to the following:
Dump1090.Socket30003 by Ted Sluis: https://github.com/tedsluis/dump1090.socket30003
These packages may incorporate other software and license terms.

## License
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see https://www.gnu.org/licenses/.


![](https://github.com/kx1t/docker-planefence/raw/main/.img/planefence-screenshot.png)
