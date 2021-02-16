# docker-planefence

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

### Adding to a previously deployed readsb[-protobuf]/dump1090[-fa] docker container
These instructions assume that you deployed Mikenye's dockerized containers for adsb as described in his [Gitbook](https://mikenye.gitbook.io/ads-b/). If you built your own container, the text below should be enough for you to figure out how to update your docker-compose file to add Planefence

1. Make sure you are running readsb or dump1090[-fa] with the option `--net-sbs-port=30003`. In a non-dockerized installation, you can edit the applicable file in `/etc/default`: either `dump1090`, or `dump1090-fa`, or `readsb`. In Mikenye's dockerized version of `readsb`, add the following to `docker-compose.yml` in the `environment:` section: `- READSB_NET_SBS_OUTPUT_PORT=30003`.
2. Copy the relevant parts from the [`docker-compose.yml` sample file](https://raw.githubusercontent.com/kx1t/docker-planefence/main/docker-compose.yml) to your own `docker-compose.yml`. SPecifically, add `planefence:` to the `volumes:` section and add the entire `planefence:` section that is shown under `services:` in the sample file.












## Build your own container

If you are new to Docker and want to convert (or build) your own containerized ADS-B station, I strongly recommend to read and follow Mikenye's Gitbook with step by step instructions, available here: https://mikenye.gitbook.io/ads-b/

The instructions below assume that you already have Docker and Git installed on your Raspberry Pi. The install instructions may be a bit short. Follow the instructions in Mikenye's gitbook linked above if you need help.

For support, please join me at the #planefence channel on the "SDR Enthusiasts" Discord server: https://discord.gg/VDT25xNZzV

To get started:
1. Install docker (`sudo apt-get docker`)
2. Use GIT to pull this image (`mkdir ~/git && cd ~/git && git clone https://github.com/kx1t/docker-planefence.git && cd docker-planefence`)
3. Use `docker build -t kx1t/planefence .` to build your image
4. Create an directory (for example `/opt/planefence`) and put `docker-compose.yml` and `.env` from this repository into that directory:
   `sudo mkdir -p /opt/planefence && sudo chmod +rwx /opt/planefence && cp docker-compose.yml /opt/planefence && cp .env /opt/planefence`
5. Edit `/opt/planefence/.env` and fill in all variables. There are a few extra ones that can be used with Mikenye's container collection for ADSB (
6. Note that the `docker-compose.yml` file also creates an instance of Mikenye's readsb container. If you are already running readsb (or dump1090[-fa]) elsewhere (either in a different container or non-containerized), you will need to make the following changes:

   a) if you replace readsb with another container (inside the same `docker-compose.yml`), make sure you update the `PF_SOCK30003HOST` variable in `.env` with the container's name.

   b) Make sure you are running readsb or dump1090[-fa] with the option `--net-sbs-port=30003`. In a non-dockerized installation, you can edit the applicable file in `/etc/default`: either `dump1090`, or `dump1090-fa`, or `readsb`. In Mikenye's dockerized version, add the following to `docker-compose.yml` in the `environment:` section: `- READSB_NET_SBS_OUTPUT_PORT=30003`.

   c) if you run readsb/dump1090[-fa] elsewhere, you may have to open a port between the docker and the host to get access to this. Also make sure that you put a reachable hostname or IP address in `PF_SOCK30003HOST`. You can open a port by editing `docker-compose.yml` and putting the following inside the `planefence:` section, at the same indentation level as `restart: always`:
```
   ports:
      - 30003:30003
```
