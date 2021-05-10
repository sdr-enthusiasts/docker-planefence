# plane-alert
Monitor ADS-B records for occurrences of planes from a list

These are extremely minimalist install notes as this repository is mainly meant for my own backup purposes.
Since it was not designed to be very portable, simply use this as sample-code to implement your own / something better.
As per the license, acknowledgement of the source would be appreciated.

Based on BASH, runs on Raspberry Pi
In order to run this, the following dependencies must be installed:
- a working `dump1090` or `dump1090-fa` or `dump1090-mutability` installation
- Ted Sluis's `Socket3003` to collect the data from a dump1090 installation: https://github.com/tedsluis/dump1090.socket30003
- Install Twurl and configure Twurl for Raspberry Pi (or comment out the part of the script that sends tweets)
- You should manually install and start the `88-plane-alert.conf` file for `lighttpd`, or some other way make a web page available that points to the install's `html` directory
- I personally would make a directory named `/usr/share/plane-alert`, chown it to `pi:pi`, and recursively copy the repository there

# How to invoke
`/usr/share/plane-alert/plane-alert.sh <filename>`

The `<filename>` is a full path to one of the log files from Socket30003 - often `/tmp/dump1090-127_0_0_1-yymmdd.txt`

# LICENSE
For full text, see the LICENSE file included with this repository.
The following is a short summary of terms. In case of conflict between this text and the terms and conditions set forth in the LICENSE file, those in the LICENSE file shall take precedence.

    Copyright (C) 2021 Ramon F. Kolb

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
