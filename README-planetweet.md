# Send a Tweet for each new plane in PlaneFence

- [Send a Tweet for each new plane in PlaneFence](#send-a-tweet-for-each-new-plane-in-planefence)
  - [TWEETING DISCONTINUED, SWITCH TO MASTODON OR DISCORD](#tweeting-discontinued-switch-to-mastodon-or-discord)
  - [Prerequisites](#prerequisites)
  - [Signing up for a Twitter Development Account and getting Twitter Credentials](#signing-up-for-a-twitter-development-account-and-getting-twitter-credentials)
- [Summary of License Terms](#summary-of-license-terms)


## TWEETING DISCONTINUED, SWITCH TO MASTODON OR DISCORD

NOTE -- WE ARE DISCONTINUING ACTIVE SUPPORT FOR SENDING TWITTER NOTIFICATIONS
In short, the latest changes and uncertainties to the "X" platform have made it impossible to reliably send out Tweets. Many of us have gotten suspended from the platform because of notifications related to aircraft owned by Elon Musk. Also, the API that we are using will soon be discontinued, and the alternative (paid) options are expensive and not economically viable for the average hobbyist user.

Instead, consider notifications to Mastodon or Discord. Instructions to set these up can be found:

- for Mastodon, [here](https://github.com/sdr-enthusiasts/blob/main/README-Mastodon.md)
- for Discord, [here](https://github.com/sdr-enthusiasts/blob/main/README-discord-alerts.md)

--------------------------------------------------------------------------------------

This utility enables tweeting of new events. It consists of a BASH shell script that monitors today's planes as written by PlaneFence, and sends out a tweet for every new plane using [Twurl](https://github.com/twitter/twurl).

There are two major parts to install this. Each of these parts is described below.

- You must apply for your own Twitter Developer Account and create an app.
- You must follow the instructions below to configure PlaneFence to use the credentials that Twitter provides you during this sign-up process.

## Prerequisites
This is part of the [kx1t/docker-planefence] docker container. Nothing in this document will make sense outside the context of this container.

## Signing up for a Twitter Development Account and getting Twitter Credentials

You'll need a registered Twitter application. If you've never registered a Twitter application before, do the following:

- If you need help, [here's a webpage](https://elfsight.com/blog/2020/03/how-to-get-twitter-api-key/) with an excellent graphical walk-through of what you need to do. In short, this is the same as doing the following:

- Go to https://developer.twitter.com/en/apps and sign in to your Twitter account. Click "Create an app".

- If you've previously registered a Twitter application, it should be listed at https://apps.twitter.com/.
- Once you've registered an application, make sure to set your application's Access Level to "Read, Write and Access Direct Messages". If you don't, PlaneFence's tweets *will* fail.

- A mobile phone number must be associated with your account in order to obtain write privileges. If your carrier is not supported by Twitter and you are unable to add a number, contact Twitter using https://support.twitter.com/forms/platform, selecting the last checkbox. Some users have reported success adding their number using the mobile site, https://mobile.twitter.com/settings, which seems to bypass the carrier check at the moment.

- Copy your `Consumer API keys` to a secure spot. Don't lose them - you will need them in the next step.

Now, you're ready to authorize PlaneFence to send out tweets. Give the following command from the host machine's command line, while PlaneFence is running and follow the instructions:
```
docker exec -it planefence /root/config_tweeting.sh
```

- Last, don't forget to edit `planefence.config` and set `PF_TWEET=ON`. Note -- this parameter ONLY concerns general PlaneFence tweeting and doesn't affect Plane-Alert tweeting (see below).

- If you also want Plane-Alert to send Twitter DM's, please read the instructions in `planefence.config` on how to enable this. Configuring Twitter as described above is a prerequisite for Plane-Alert tweets to work, however if you don't want to send any general PlaneFence tweets, you can leave `PF_TWEET=OFF`

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
