# WARNING !!!
This version of PlaneFence contains updates that are specific to make it run inside a Docker Container. 
If you do not want to run this inside docker, please go to https://github.com/kx1t/planefence

# PlaneFence
Collection of scripts using Socket30003 logs to create a list of aircraft that fly low over your location.
Copyright 2020 by Ramon F. Kolb - Licensed under GPL3.0 - see separate license file.

For an example, see http://planefence.ramonk.net

This documentation is for PlaneFence v3.12. For a summary of changes since v1, see at the end of this document. (There was no publicly released PlaneFence v2.)

## Attributions, inclusions, and prerequisites

1. You must have a Raspberry Pi with a working version of dump1090, dump1090-fa, dump1090-mutability, or the equivalent dump978 versions installed. If you don't have this, stop right here. It makes no sense to continue unless you understand the basic functions of the ADSB receiver for Raspberry Pi
2. The scripts in this repository rely on [dump1090.socket30003](https://github.com/tedsluis/dump1090.socket30003), used and distributed under the GPLv3.0 license. 
3. The instructions below err on the side of completeness. It may look a bit overwhelming, but if you follow each step to the letter, you should be able to set this up in 30 minutes or less.

What does this mean for you? Follow the installation instructions and you should be good :)


# Seeing your PlaneFence page
Once the app is running, you can find the results at `http://<address_of_rpi>/planefence`. Give it a few minutes after installation!
Replace `<address_of_rpi>` with whatever the address is you normally use to get to the SkyAware or Dump1090 map.
For reference, see (http://planefence.ramonk.net).

# Optional - Tweeting Your Updates
(not yet implemented)
Once you have PlaneFence completely up and running, you can add an option to send a Tweet for every overflying plane.
The setup of this is a bit complicated as you will have to register your own Twitter Developer Account, and get a 
App Key for your application.
Detailed installation instructions can be accessed here:
https://github.com/kx1t/planefence/blob/master/README-twitter.md

If you want to see an example of how this works, go here: https://twitter.com/PlaneBoston

# Known Issues
- Planes that are seen multiple times during consecutive runs, may show up multiple times
- The script hasn't been thoroughly tested. Please provide feedback and exerpts of /tmp/planefence.log that show the activites around the time the issues occurred.
- The code is a bit messy and at times, disorganized. However, it's overly documented and should be easy to understand and adapt.

# Summary of License Terms
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Release History
- v1: PlaneFence based on BASH and Python scripts. Iterates through all logs every time it is invoked
- v1: Using CRON to invoke script every 2 minutes
- v2: never publicly released
- v3.0: total rewrite of planefence.sh and major simplification of planefence.py
- v3.0: only iterates through the socket30003 log lines that weren't processed previously. Reduced execution time dramatically, from ~1 minute for 1M lines, to an average of ~5 seconds between two runs that are 2 minutes apart.
- v3.0: uses Systemd to run planefence as a daemon; removed need for cronjob.
- v3.11: clean-up, minor fixes, updated documentation, etc.
- v.3.12: added auto-install script
