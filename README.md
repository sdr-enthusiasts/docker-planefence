# docker-planefence

Docker container with dump1090.socket30003 and planefence
Note that at the moment, the only compiled image is created for arm64 (Raspberry Pi 4B / 4 Gb with 64-bits Ubuntu 20.10)
You can build your own...

To get started:
1. Install docker (`sudo apt-get docker`)
2. Use GIT to pull this image (`mkdir ~/git && cd ~/git && git clone https://github.com/kx1t/docker-planefence.git && cd docker-planefence`)
3. Use `docker build -t kx1t/planefence .` to build your image
4. Create an directory (for example `/opt/planefence`) and put `docker-compose.yml` and `.env` from this repository into that directory:
   `sudo mkdir -p /opt/planefence && sudo chmod +rwx /opt/planefence && cp docker-compose.yml /opt/planefence && cp .env /opt/planefence`
5. Edit `/opt/planefence/.env` and fill in all variable. For PlaneFence, you MUST put values with at least the following:
```FEEDER_ALT_FT=60
FEEDER_ALT_M=18
FEEDER_LAT=xx.xxxxx
FEEDER_LONG=-xx.xxxxx
FEEDER_TZ=America/New_York
PF_MAXALT=5000
PF_MAXDIST=2.0
PF_NAME="STATION NAME"
PF_INTERVAL=80
PF_MAPURL="http://my_station.ip/tar1090"
PF_TWEET=
PF_LOG=/tmp/planefence.log
PF_DISTUNIT=nauticalmile
PF_ALTUNIT=feet
PF_SPEEDUNIT=knotph
PF_SOCK30003HOST=readsb
```
6. Note that the `docker-compose.yml` file also creates an instance of Mikenye's readsb container. You can change this if you are already another using a different instance of readsb (or dump1090[-fa]), HOWEVER:
   
   a) the Planefence container depends on being able to access the SBS output from a dump1090/dump1090-fa/readsb instance. This is easiest done by running
      readsb (or dump1090[-fa]) from the same docker-compose.yml, as this creates an intra-net between the containers
   
   b) if you replace readsb with another container (inside the same docker-compose.yml), make sure you update the `PF_SOCK30003HOST` variable in `.env` with the container's name.
   
   c) if you run readsb/dump1090[-fa] elsewhere, you may have to open a port between the docker and the host to get access to this. Also make sure that you put a reachable hostname or IP address in `PF_SOCK30003HOST`. You can open a port by editing docker-compose.yml and putting the following inside the `planefence:` section, at the same indentation level as `restart: always`:
```
   ports:
      - 30003:30003
```

