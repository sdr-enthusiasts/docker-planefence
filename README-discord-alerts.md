# Send a message to Discord for each new plane in PlaneFence

Setting up Discord notifications involves only two simple steps:

- Create a Webhook
- Configure PlaneFence

We'll go into the details of each step below.

## Table of Contents
- [Send a message to Discord for each new plane in PlaneFence](#send-a-message-to-discord-for-each-new-plane-in-planefence)
  - [Table of Contents](#table-of-contents)
  - [Prerequisites](#prerequisites)
  - [Creating a Webhook URL](#creating-a-webhook-url)
  - [Configure Planefence](#configure-planefence)
- [Summary of License Terms](#summary-of-license-terms)


## Prerequisites

- You'll need a Discord server to invite the bot to. Anyone can create their own server for free. Follow [these instructions](https://support.discord.com/hc/en-us/articles/204849977-How-do-I-create-a-server-) on Discord's support site.

This is part of the [sdr-enthusiasts/docker-planefence] docker container. Nothing in this document will make sense outside the context of this container.

## Creating a Webhook URL

If you're sending alerts to a channel that you control you'll need to set up a Webhook URL first. If someone has provided you with a Webhook URL to send alerts to already you can skip to the last step in this section.

- In your Discord server right-click the channel you want messages to go to and click "Edit Channel"

- In the Integrations page click "Create Webhook"

- Config the Name that you'd like messages to appear as and set a profile image then click "Copy Webhook URL"

- If you want to post to the [#planefence-alert channel](https://discord.gg/ytAW4WZ66B) on the SDR-Enthusiasts Discord Server (which is where most of us hang out), please join that server and send a DM to @kx1t. 

## Configure Planefence

- In your `planefence.config` file paste the webhook url into `PA_DISCORD_WEBHOOKS` to send plane-alert messages and `PF_DISCORD_WEBHOOKS` to send planefence messages.

- If you're posting alerts to a shared channel you can set `DISCORD_FEEDER_NAME` to something that identifies where the alert came from. If you're near an airport you could use its ICAO identifier.

- To get messages from Planefence set `PF_DISCORD=ON` and to get messages from plane-alert set `PA_DISCORD=ON`.

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
