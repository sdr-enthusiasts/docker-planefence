# Send a Mastodon Post for each new plane in PlaneFence
This utility enables sending Mastodon posts of new events. Ever since Twitter started to restrict posting about locations of aircraft, are encouraging people to post to Mastodon,

There are two major parts to install this. Each of these parts is described below.

- You must have a Mastodon account and create an Application in it.
- You must follow the instructions below to configure PlaneFence to use the credentials that Mastodon provides you during this sign-up process.

## Prerequisites
This is part of the [kx1t/docker-planefence] docker container. Nothing in this document will make sense outside the context of this container.

## Signing up for a Mastodon Account and creating an Application

Mastodon is a distributed social media service. This means, that you have your choice of Mastodon servers to create and maintain your account on. Any of them will work (as long as they allow bots), but we recommend joining this one. It's the one where many of us post results of our SDR and radio reception endeavors: https://airwaves.social/

Once you have an account, please do the following:

- Sign in to Mastodon and go to the home page, for example: https://airwaves.social/home
- Click `Preferences` on the right bottom of the page
- On the left botton, click `</> Developer`
- Create a new Application by clicking the button, then:
  - Give it a name (for example, "Planefence")
  - Add a URL (if you don't have one, use something like "https://airwaves.social/@myhandle" (replace `myhandle` by your Mastodon handle))
  - Make sure that the following scopes are selected (important!!!): `read`, `write`, `follow`
  - Save the Application and (important!!!) note the Access Token

## Configuring Planefence to use Mastodon

Please set the following parameters in your `planefence.config` file:

```
MASTODON_SERVER=airwaves.social
MASTODON_ACCESS_TOKEN=vsafdwafewarewdcvdsafwaefaewfdw
```
(replace by the applicable server name and access token)

As long as both these parameters are defined and correct, Planefence and Plane-Alert will post to Mastodon.

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