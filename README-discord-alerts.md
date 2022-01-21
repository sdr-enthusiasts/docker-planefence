# Send a message to Discord for each new plane in PlaneFence
Setting up Discord notifications involves only a few simple steps:

- Create a Bot
- Invite it to a server
- Configure PlaneFence

We'll go into the details of each step below.

## Prerequisites

- You'll need a Discord server to invite the bot to. Anyone can create their own server for free. Follow [these instructions](https://support.discord.com/hc/en-us/articles/204849977-How-do-I-create-a-server-) on Discord's support sitee.

This is part of the [kx1t/docker-planefence] docker container. Nothing in this document will make sense outside the context of this container.

## Setting up a Discord Bot

- Open the [Discord Developer Portal](https://discord.com/developers/applications) and click New Application at the top-right

- Enter a name for your application and click "Create". The name of your application is what will show up as the username that the messages were sent by. You can change this at any time.

- On the left-hand sidebar click Bot and then click the "Add Bot" button, and then "Yes". On the next page in the "Token" section click the "Copy" button. This is what PlaneFence needs to send messages as your bot.

- In your `.env` file add an entry for `DISCORD_TOKEN=<paste your token>`

## Bring your bot into a server

- In the left-hand sidebar of your Application's plage click the "OAuth 2" button and then "URL Generator" below that.

- In the Scopes list we only need to check the "bot" box. It should be in the middle row, 5th entry down.

- Once you click that you'll get a new list of Bot Permissions. We only need "Send Messages" at the top of the middle column.

- At the bottom of the page find the "Generated URL". Copy and pate that into your browser's address bar.

- Select the server you'd like to receive alerts in and then "Continue" and "Authorize".

- Your bot should show up in every public channel of your server. If you'd like the alerts to go to a private channel you'll need to go into the Edit Channel page and then the "Permissions" tab. Click "Add members or roles" and select your bot.

## Configure Planefence

- If you haven't already save thed token from the first step into your `.env` file be sure to do that.

- We also need to tell Planefence what Server and Channel to send to. Open the Preferences of your Discord client and go to the "Advanced" page (towards the bottom). Enable "Developer Mode"

- Right click on your server in the list on the far-left of the application and click "Copy ID" at the bottom. Paste that into `planefence.config` as `DISCORD_SERVER_ID=<paste>`.

- With your server selected right-click the channel you want the messages to be posted in and click "Copy ID" at the bottom. Paste this into `planefence.config` as `DISCORD_CHANNEL_ID=<paste>`

- Last, don't forget to set `PF_DISCORD=ON`. By default both PlaneFence and Plane-Alert will send messages to Discord. You can disable planefence messages by setting `PF_DISCORD_DISABLE="planefence"` or disable plane-alert messages by setting `PF_DISCORD_DISABLE="plane-alert"`.

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
