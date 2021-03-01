# Installing or Upgrading Planefence to the latest dev version.

## Install a new instance

Note - this guide assumes that `/home/pi` is your home directory. If it is not (for example, Ubuntu builds use `/home/ubuntu` as their default account), please change all occurrences of `/home/pi` to your home directory path.

The guide also assumes you run on a `armhf` or `arm64` machine. If not, see the section "Building my own container" below and then follow the rest of the guide.

Last, the guide assumes that you have `docker` and `docker-compose` installed. If you don't, please follow the relevant sections of [this guide](https://mikenye.gitbook.io/ads-b/setting-up-the-host-system/install-docker).

### Getting ready
Some of these things you may already have done. You can skip those steps. We erred on the side of completeness.
1. Create a landing directory for Planefence:
```
sudo mkdir -p /opt/planefence && sudo chmod a+rwx /opt/planefence && cd /opt/planefence
```
2. Get the template Docker-compose.yml file
```
curl -s https://raw.githubusercontent.com/kx1t/docker-planefence/dev/docker-compose.yml > docker-compose.yml
```

Now, there are a few possibilities:
1. You are already running a container with `tar1090`, `dump1090[-fa]`, or `readsb` on the same machine with docker-compose and want to add PlaneFence to this
2. You are running `tar1090`, `dump1090[-fa]`, or `readsb` elsewhere, either dockerized or stand-alone. This includes the use case where you are running the feeder software stand-alone on the same machine
3. You don't run `tar1090`, `dump1090[-fa]`, or `readsb` anywhere else and you need to install an instance of this software on your local machine.


### Situation 1 - Adding Planefence to an existing, local, containerized setup of `tar1090`, `dump1090[-fa]`, or `readsb`
- Extract from `docker-compose.yml` the entire `planefence:` section under `services:`. Open your existing `docker-compose.yml` and add this section there. Note -- YML is very sensitive to indents. Make sure that they line up in the target file the same way as they were in the file you copied from.

### Situation 2- You are running your feeder elsewhere
- Edit the `docker-compose.yml` file attached and remove or comment out the following:
```
#volumes:
#  readsbpb_rrd:
#  readsbpb_autogain:
```
- Remove or comment out the entire `readsb:` section from line 42 through the end of the file
- On your other setup, MAKE SURE (!!) that you generate SBS formatted data on port 30003. How to do this varies by setup and goes beyond this manual, but please reach out for help if needed!

### Situation 3 - Adding a feeder from scratch
- It is assumed that you understand what this entails. If you don't -- please read [Mikenye's excellent Gitbook](https://mikenye.gitbook.io/ads-b/) on the topic!
- The example here adds a `readsb-protobuf` container. Setup for `dump1090[-fa]` or `tar1090` is very similar
- `readsb-protobuf` will need a `.env` file. We will tell you how to EASILY create one after you are done fully configuring PlaneFence.

### Planefence Configuration
#### Initial docker configuration
In the `docker-compose.yml` file, you should configure the following:
- The image, by default, points at the release image. For the DEV version, change this: `image: kx1t/planefence:arm-test-pr`
- If you are using your host machine's webservice, you can comment out this section. Leave it in if you want to use PlaneFence's built-in web server. In that case you can change 8088 to a port number of your liking:
```
#   ports:
#     -8088:80
```
- Update `TZ=America/New_York` to whatever is appropriate for you. Note that this variable is case sensitive
- There are 2 volumes defined. My suggestion is NOT to change these (except for updating `/home/pi/.planefence` -> `/home/ubuntu/planefence` if required). However, if you have to, you can map the HTML directory to some other location. ONLY change what is to the LEFT of the colon.
- You can exit the editor and start the container (`docker-compose up -d`). The first time you do this, it can take a minute or so.

#### Planefence Settings Configuration
- When you start the container for the first time, it will create a few directories with setup files. You MUST edit these setup files before things will work! You can check if the system recognized you've made edits by typing `docker logs planefence` - if you haven't set up the system, it *will* complain.
- MANDATORY: First -- copy the template config file in place: `sudo cp ~/.planefence/planefence.config-RENAME-and-EDIT-me ~/.planefence/planefence.config`
    -- ALTERNATIVE - if you have used PlaneFence in the past and created a `.env` file, you can use this file as a basis for your `planefence.config` file. You can copy it with `sudo cp /opt/planefence/.env ~/.planefence/planefence.config`. However, there are many new features and setting described in the planefence.config-RENAME-and-EDIT-me file. You should take notice and copy these in!
- MANDATORY: `sudo nano ~/.planefence/planefence.config` Go through all parameters - their function is explained in this file. Edit to your liking and save/exit using `ctrl-x`. THIS IS THE MOST IMPORTANT AND MANDATORY CONFIG FILE TO EDIT !!!
- OPTIONAL: `sudo nano ~/.planefence/plane-ignore.txt`. In this file, you can add things that PlaneFence will ignore. If there are specific planes that fly too often over your home, add them here. Use 1 line per entry, and the entry can be a ICAO, flight number, etc. You can even use regular expressions if you want. Be careful -- we use this file as an input to a "grep" filter. If you put something that is broad (`.*` for example), then ALL PLANES will be filtered out.
- OPTIONAL: `sudo nano ~/.planefence/airlinecodes.txt`. This file maps the first 3 characters of the flight number to the names of the airlines. We scraped this list from a Wikipedia page, and it is by no means complete. Feel free to add more to them -- please add an issue at https://github.com/kx1t/planefence/issues so we can add your changes to the default file.
- OPTIONAL: `sudo nano ~/.planefence/.twurlrc`. You can add your back-up TWURLRC file here, if you want.
- OPTIONAL: `sudo nano ~/.planefence/plane-alert-db.txt`. This is the list of tracking aircraft of Plane-Alert. It is prefilled with the planes of a number of "interesting" political players. Feel free to add your own, delete what you don't want to see, etc. Just follow the same format.

#### Applying your setup
- If you are using the "Adding a feeder from scratch" configuration above, it will want a `.env` file. You can provide it simply with a copy of your planefence.config file: `cp ~/.planefence/planefence.config /opt/planefence/.env`. (You can ignore this if you didn't follow the "Adding a feeder from scratch" setup.)
- Now, you can restart the Planefence container and the new setup should automatically be applied: `pushd /opt/planefence && docker-compose up -d && popd`

## What does it look like when it's running?
- Planefence dev build: http://ramonk.net:8081
- Plane-alert dev build: http://ramonk.net:8081/plane-alert

## Seeing my own setup and troubleshooting
- Be patient. Many of the files won't get initialized until the first "event" happens: a plane is in PlaneFence range or is detected by Plane-Alert
- Check, check, double-check. Did you configure the correct container in `docker-compose.yml`? cat 
- Check the logs: `docker logs -f planefence`
- Check the website: http://myip:8081 should update every 80 seconds (starting about 80 seconds after the initial startup). The top of the website shows a last-updated time and the number of messages received from the feeder station.
- Plane-alert will appear at http://myip:8081/plane-alert
- Twitter setup is complex. [Here](https://github.com/kx1t/docker-planefence#setting-up-tweeting)'s a description on what to do.
- If you have a soundcard and microphone, adding NoiseCapt is as easy as hooking up the hardware and running another container. You can add this to your existing `docker-compose.yml` file, or run it on a different machine on the same subnet. Instructions are [here](https://github.com/kx1t/docker-noisecapt/blob/main/README.md).

## Building my own container
This section is for those who don't trust my container building skills (honestly, I wouldn't trust myself!) or who run on an architecture that is different than `armhf` (Raspberry Pi 3B+/4 with Raspberry OS 32 bits) or `arm64` (Raspberry Pi 4 with Ubuntu 64 bits). In that case, you may have to create your own container using these steps. This assumes that you have `git` installed. If you don't, please install it first using `sudo apt-get install git`.
 ```
sudo mkdir -p /opt/planefence
sudo chmod a+rwx /opt/planefence
cd /opt/planefence
git clone https://github.com/kx1t/docker-planefence
cd docker-planefence
docker build --compress --pull -t kx1t/planefence:arm-test-pr .
```
This should create a container ready to use on your local system.


## Getting help
- If you need further support, please join the #planefence channel at the [SDR Enthusiasts Discord Server](https://discord.gg/VDT25xNZzV). If you need immediate help, please add "@ramonk" to your message.

That's all!
