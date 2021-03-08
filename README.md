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

## Install PlaneFence - Prerequisites

Note - this guide assumes that `/home/pi` is your home directory. If it is not (for example, Ubuntu builds use `/home/ubuntu` as their default account), please change all occurrences of `/home/pi` to your home directory path.

This guide assumes that you have `docker` and `docker-compose` installed. If you don't, please follow the relevant sections of [this guide](https://mikenye.gitbook.io/ads-b/setting-up-the-host-system/install-docker).

Last, we are going to assume that you have a version of `tar1090`, `dump1090[-fa]`, or `readsb` running somewhere in reach of your Planefence machine, potentially even as a container on the same machine. --> It is important to enable SBS data on port 30003 on that instance. PlaneFence will use this to get its data. Again, Mikenye's Gitbook will help you install a container with this, if needed.

### Getting ready

If you are adding this to an existing collection of docker containers on your machine, you can add the information from this project to your existing `docker-compose.yml`. If not, you should create a project directory (`sudo mkdir -p /opt/planefence && sudo chmod a+rwx /opt/planefence && cd /opt/planefence`) and make a new `docker-compose.yml` there.

Get the template Docker-compose.yml file from here:
```
curl -s https://raw.githubusercontent.com/kx1t/docker-planefence/dev/docker-compose.yml > docker-compose.yml
```

### Planefence Configuration
#### Initial docker configuration
In the `docker-compose.yml` file, you should configure the following:
- IMPORTANT: The image, by default, points at the release image. For the DEV version, change this: `image: kx1t/planefence`
- IMPORTANT: Update `TZ=America/New_York` to whatever is appropriate for you. Note that this variable is case sensitive
- There are 2 volumes defined. My suggestion is NOT to change these (except for updating `/home/pi/.planefence` -> `/home/ubuntu/planefence` if required). However, if you have to, you can map the HTML directory to some other location. ONLY change what is to the LEFT of the colon.
- You can exit the editor and start the container (`docker-compose up -d`). The first time you do this, it can take a minute or so.
- Monitor the container (`docker logs -f planefence`). At first start-up, it should be complaining about not being configure. That is expected behavior.

#### Planefence Settings Configuration
- When you start the container for the first time, it will create a few directories with setup files. You MUST edit these setup files before things will work! You can check if the system recognized you've made edits by typing `docker logs planefence` - if you haven't set up the system, it *will* complain.
- MANDATORY: First -- copy the template config file in place: `cp ~/.planefence/planefence.config-RENAME-and-EDIT-me ~/.planefence/planefence.config`
  - ALTERNATIVE - if you have used PlaneFence in the past and created a `.env` file, you can use this file as a basis for your `planefence.config` file. You can copy it with `sudo cp /opt/planefence/.env ~/.planefence/planefence.config`. However, there are many new features and setting described in the planefence.config-RENAME-and-EDIT-me file. You should take notice and copy these in! There are some items (like the setup for the different feeders) that are not needed by `planefence.config`.
- MANDATORY: `sudo nano ~/.planefence/planefence.config` Go through all parameters - their function is explained in this file. Edit to your liking and save/exit using `ctrl-x`. THIS IS THE MOST IMPORTANT AND MANDATORY CONFIG FILE TO EDIT !!!
- OPTIONAL: `sudo nano ~/.planefence/plane-ignore.txt`. In this file, you can add things that PlaneFence will ignore. If there are specific planes that fly too often over your home, add them here. Use 1 line per entry, and the entry can be a ICAO, flight number, etc. You can even use regular expressions if you want. Be careful -- we use this file as an input to a "grep" filter. If you put something that is broad (`.*` for example), then ALL PLANES will be filtered out.
- OPTIONAL: `sudo nano ~/.planefence/airlinecodes.txt`. This file maps the first 3 characters of the flight number to the names of the airlines. We scraped this list from a Wikipedia page, and it is by no means complete. Feel free to add more to them -- please add an issue at https://github.com/kx1t/planefence/issues so we can add your changes to the default file.
- OPTIONAL: If you configured Twitter support before, `sudo nano ~/.planefence/.twurlrc`. You can add your back-up TWURLRC file here, if you want.
- OPTIONAL: Configure tweets to be sent. For details, see these instructions: https://github.com/kx1t/docker-planefence/README-planetweet.md
- OPTIONAL: `sudo nano ~/.planefence/plane-alert-db.txt`. This is the list of tracking aircraft of Plane-Alert. It is prefilled with the planes of a number of "interesting" political players. Feel free to add your own, delete what you don't want to see, etc. Just follow the same format.
- OPTIONAL: If you have multiple containers running on different web port, and you would like to consolidate them all under a single host name, then you should consider installing a "reverse web proxy". This can be done quickly and easily - see instructions [here](https://github.com/kx1t/docker-planefence/README-nginx-rev-proxy.md).
- OPTIONAL: If you have a soundcard and microphone, adding NoiseCapt is as easy as hooking up the hardware and running another container. You can add this to your existing `docker-compose.yml` file, or run it on a different machine on the same subnet. Instructions are [here](https://github.com/kx1t/docker-noisecapt/).


#### Applying your setup
- If you made a bunch of changes for the first time, you should restart the container. In the future, most updates to `~/.planefence/planefence.config` will be picked up automatically
- You can restart the Planefence container by doing: `pushd /opt/planefence && docker stop planefence && docker-compose up -d && popd` (replace `/opt/planefence` to whatever the directory is where your `docker-compose.yml` file is located

## What does it look like when it's running?
- Planefence build example: https://planefence.ramonk.net
- Plane-alert build example: https://plane-alert.ramonk.net

## Seeing your own setup and troubleshooting
- Be patient. Some of the files won't get initialized until the first "event" happens: a plane is in PlaneFence range or is detected by Plane-Alert
- Check, check, double-check. Did you configure the correct container in `docker-compose.yml`? Did you edit the `planefence.config` file?
- Check the logs: `docker logs -f planefence`. Some "complaining" about lost connections or files not found is normal, and will correct itself during operation. The logs will be quite explicit if there's something you need to take action about.
- Check the website: http://myip:8081 should update every 80 seconds (starting about 80 seconds after the initial startup). The top of the website shows a last-updated time and the number of messages received from the feeder station.
- Plane-alert will appear at http://myip:8081/plane-alert
- Twitter setup is complex. [Here](https://github.com/kx1t/docker-planefence#setting-up-tweeting)'s a description on what to do.

## Building my own container
This section is for those who don't trust my container building skills (honestly, I wouldn't trust myself!) or who run on an architecture that is different than `armhf` (Raspberry Pi 3B+/4 with Raspberry OS 32 bits),`arm64` (Raspberry Pi 4 with Ubuntu 64 bits), or `amd64` (Linux PC). In that case, you may have to create your own container using these steps. This assumes that you have `git` installed. If you don't, please install it first using `sudo apt-get install git`.
 ```
sudo mkdir -p /opt/planefence
sudo chmod a+rwx /opt/planefence
cd /opt/planefence
git clone https://github.com/kx1t/docker-planefence
cd docker-planefence
docker build --compress --pull -t kx1t/planefence:mycontainer .
```
This should create a container ready to use on your local system. Make sure to update your `docker-compose.yml` to point the image at `kx1t/planefence:mycontainer`


## Getting help
- If you need further support, please join the #planefence channel at the [SDR Enthusiasts Discord Server](https://discord.gg/VDT25xNZzV). If you need immediate help, please add "@ramonk" to your message. Alternatively, email me at kx1t@amsat.org.

That's all!
![](https://media.giphy.com/media/3oKHWikxKFJhjArSXm/giphy.gif)
