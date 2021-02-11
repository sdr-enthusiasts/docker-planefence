# docker-planefence

Docker container with dump1090.socket30003 and planefence
Note that at the moment, the only compiled image is created for arm64 (Raspberry Pi 4B / 4 Gb with 64-bits Ubuntu 20.10)
You can build your own following the instructions below.

## Build your own container

If you are new to Docker and want to convert (or build) your own containerized ADS-B station, I strongly recommend to read and follow Mikenye's Gitbook with step by step instructions, available here: https://mikenye.gitbook.io/ads-b/

The instructions below assume that you already have Docker and Git installed on your Raspberry Pi. The install instructions may be a bit short. Follow the instructions in Mikenye's gitbook linked above if you need help.

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

