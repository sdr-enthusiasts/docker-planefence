# Send a Mastodon Post for each new plane in PlaneFence

- [Send a Mastodon Post for each new plane in PlaneFence](#send-a-mastodon-post-for-each-new-plane-in-planefence)
  - [Prerequisites](#prerequisites)
  - [Signing up for a Mastodon Account and creating an Application](#signing-up-for-a-mastodon-account-and-creating-an-application)
  - [Configuring Planefence to use Mastodon](#configuring-planefence-to-use-mastodon)
  - [Automatic verification checkmark of your Mastodon account](#automatic-verification-checkmark-of-your-mastodon-account)
    - [Troubleshooting Mastodon verified links](#troubleshooting-mastodon-verified-links)
  - [Summary of License Terms](#summary-of-license-terms)

This utility enables sending Mastodon posts of new events. Ever since Twitter started to restrict posting about locations of aircraft, are encouraging people to post to Mastodon,

There are two major parts to install this. Each of these parts is described below.

- You must have a Mastodon account and create an Application in it.
- You must follow the instructions below to configure PlaneFence to use the credentials that Mastodon provides you during this sign-up process.

## Prerequisites

This is part of the [sdr-enthusiasts/docker-planefence] docker container. Nothing in this document will make sense outside the context of this container.

## Signing up for a Mastodon Account and creating an Application

Mastodon is a distributed social media service. This means, that you have your choice of Mastodon servers to create and maintain your account on. Any of them will work (as long as they allow bots), but we recommend joining this one. It's the one where many of us post results of our SDR and radio reception endeavors: <https://airwaves.social/>

Once you have an account, please do the following:

- Sign in to Mastodon and go to the home page, for example: <https://airwaves.social/home>
- Click `Preferences` on the bottom right of the page
![image](https://user-images.githubusercontent.com/15090643/208437930-ee33596d-5015-4283-923c-12913552f6db.png)

- On the bottom left, click `</> Development`
![image](https://user-images.githubusercontent.com/15090643/208438201-27c29fec-cad9-43fe-88f6-c4009961b162.png)

- Create a new Application by clicking the button, then:
  - Give it a name (for example, "Planefence")
  - Add a URL (if you don't have one, use something like "<https://airwaves.social/@myhandle>" (replace `myhandle` by your Mastodon handle))
  - Make sure that the following scopes are selected (important!!!): `read`, `write`, `follow`
  - Press `Submit` at the bottom of the page
![image](https://user-images.githubusercontent.com/15090643/208438325-2f5dd1b7-ebd8-404e-8929-7bf5e7875037.png)
![image](https://user-images.githubusercontent.com/15090643/208438373-de1defdb-41ee-4528-a659-f2faa846733d.png)

- Open the Application and (important!!!) note the Access Token
![image](https://user-images.githubusercontent.com/15090643/208438462-b40cc847-f36c-4db7-bacb-54a68fae2cff.png)
![image](https://user-images.githubusercontent.com/15090643/208438987-3e1fd9c2-5ce9-46c0-92e9-20bb78f55a8c.png)

## Configuring Planefence to use Mastodon

Please set the following parameters in your `planefence.config` file:

```text
MASTODON_SERVER=airwaves.social
MASTODON_ACCESS_TOKEN=vsafdwafewarewdcvdsafwaefaewfdw
PF_MASTODON=ON
PA_MASTODON=ON
PA_MASTODON_VISIBILITY=unlisted
PF_MASTODON_VISIBILITY=unlisted
```

- Replace the values with the applicable server name and access token.
- If `PF_MASTODON` is not set to `ON`, then no PlaneFence Mastodon notifications will be sent.
- If `PA_MASTODON` is not set to `ON`, then no Plane-Alert Mastodon notifications will be sent.
- `Px_MASTODON_VISIBILITY` can be `public` (visible in everyone's feed), `unlisted` (only visible on your profile page), or `private` (invisible to anyone except for you).

## Automatic verification checkmark of your Mastodon account

If you add a link to your public Planefence or Plane-Alert page in the Extra Fields section of your Public Profile on Mastodon, you will get automatic account verification (with a cool green checkmark) for your Mastodon account. Your Planefence and Plane-Alert pages will automatically add a hidden verification link with the `rel="me"` element as described in the "Verification" tab of your Mastodon Profile Edit page.

![image](https://github.com/sdr-enthusiasts/docker-planefence/assets/15090643/4164a6c3-c029-4c8b-8d66-182181d2c70a)
![image](https://github.com/sdr-enthusiasts/docker-planefence/assets/15090643/99708e0b-71d1-4b47-9f01-0db56bc738ee)

### Troubleshooting Mastodon verified links

- If verification fails, please ensure that your Planefence and Plane-Alert webpages are reachable when you press "Save my profile" in Mastodon. This will kick off a new verification attempt.
- Another thing to check is that your reverse web proxy (if you use one) isn't too aggressive blocking Bots. Specifically, User Agents that start with `http.rb` should be allowed to pass. Here are a few examples of verification attempts (from the webproxy's `access.log`):

```text
66.94.123.74 - - [03/Feb/2024:21:00:24 -0500] "GET /planefence/ HTTP/1.1" 200 27716 "-" "http.rb/5.1.1 (Mastodon/4.2.1; +https://airwaves.social/)"
66.94.123.74 - - [03/Feb/2024:21:00:25 -0500] "GET /plane-alert/ HTTP/1.1" 200 524687 "-" "http.rb/5.1.1 (Mastodon/4.2.1; +https://airwave.social/)"
```

## Summary of License Terms

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
