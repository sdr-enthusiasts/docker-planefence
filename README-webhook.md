# Configure Planefence / Plane-Alert HTTP Webhook notifications

- [Configure Planefence / Plane-Alert HTTP Webhook notifications](#configure-planefence--plane-alert-http-webhook-notifications)
  - [Prerequisites](#prerequisites)
  - [Step 1: Enable webhooks and set URLs](#step-1-enable-webhooks-and-set-urls)
  - [Step 2: Choose body format](#step-2-choose-body-format)
  - [Step 3: Edit persist templates and headers](#step-3-edit-persist-templates-and-headers)
  - [Placeholders](#placeholders)
  - [Content-Type behavior](#content-type-behavior)
  - [Example: ntfy](#example-ntfy)
  - [Limits and security](#limits-and-security)
  - [Summary of License Terms](#summary-of-license-terms)

This README describes how to configure Planefence to POST Planefence and/or Plane-Alert alerts to one or more HTTP(S) URLs. These webhooks are generic - they are not built for a specific service. You can use them with ntfy, a small custom endpoint, or anything else that accepts a POST. Discord already has its own notifier; do not use these settings for Discord.

## Prerequisites

This is part of the [sdr-enthusiasts/docker-planefence] docker container. Nothing in this document will make sense outside the context of this container. We assume that Planefence has been set up correctly and is working fine, and all you want to do is add HTTP webhook notifications to your existing setup.

You need an HTTP endpoint that accepts `POST` with a plain-text or JSON body. You can add optional custom headers through persist files (see below).

## Step 1: Enable webhooks and set URLs

Edit your `planefence.config` file (or use the **Notifications -> Webhook** tab in the configuration UI), and set:

```config
PA_WEBHOOK=OFF              # set ON to enable Plane-Alert HTTP webhook POSTs
PF_WEBHOOK=OFF              # set ON to enable Planefence HTTP webhook POSTs
PA_WEBHOOK_URLS=            # comma-separated HTTP(S) URLs for Plane-Alert
PF_WEBHOOK_URLS=            # comma-separated HTTP(S) URLs for Planefence
```

Planefence and Plane-Alert each have their own enable flag and URL list. There is no shared "one webhook for both" setting. Every URL on a list gets the same rendered body and headers for that side (Planefence or Plane-Alert).

As elsewhere in Planefence, enable values are things like `ON` / `OFF` (and the usual truthy forms such as `yes` / `true` / `1`).

## Step 2: Choose body format

```config
PA_WEBHOOK_FORMAT=text      # text | json (default text)
PF_WEBHOOK_FORMAT=text      # text | json (default text)
```

- `text` - a single human-readable message body (works well with ntfy and similar services).
- `json` - a structured JSON object body.

Format is chosen separately for Planefence and for Plane-Alert, not per URL. Invalid or empty values fall back to `text`.

## Step 3: Edit persist templates and headers

Bodies and headers are **not** stored in `planefence.config`. They live as fixed filenames on the Planefence persist volume (defaults are copied in on first run if the files are missing). The Web UI does not edit these file contents; edit them on the host (or inside the persist mount).

|             | Format | Template file              | Headers file         |
| ----------- | ------ | -------------------------- | -------------------- |
| Plane-Alert | text   | `webhook.pa.text.template` | `webhook.pa.headers` |
| Plane-Alert | json   | `webhook.pa.json.template` | `webhook.pa.headers` |
| Planefence  | text   | `webhook.pf.text.template` | `webhook.pf.headers` |
| Planefence  | json   | `webhook.pf.json.template` | `webhook.pf.headers` |

Headers files use one `Name: value` line per header. Blank lines and `#` comments are ignored. The defaults that ship in the image are comment-only examples - no secrets.

## Placeholders

Templates and header values may contain `||...||` placeholders.

**Record placeholders** use the same field names as MQTT / alert records (for example `||icao||`, `||tail||`, `||altitude:value||`, `||image:thumblink||`, `||link:map||`, `||db:tag1||`). Missing values become empty strings.

**Composed placeholders** are filled in by the notifier:

| Placeholder      | Meaning                                 |
| ---------------- | --------------------------------------- |
| `||title||`      | Short notification title                |
| `||message||`    | Multi-line summary body                 |
| `||links||`      | Map / tracker links                     |
| `||emergency||`  | Emergency squawk prefix when applicable |
| `||alt_unit||`   | Altitude unit string                    |
| `||dist_unit||`  | Distance unit string                    |
| `||speed_unit||` | Speed unit string                       |

For `text` format, blank lines are collapsed after substitution. Discord-only tokens such as `||COLOR||` are not supported here.

## Content-Type behavior

The notifier sets `Content-Type` from the chosen format unless the headers file already sets `Content-Type`:

- `text` -> `text/plain; charset=utf-8`
- `json` -> `application/json`

If you need a different type, put `Content-Type: ...` in that side's headers file (`webhook.pa.headers` or `webhook.pf.headers`).

## Example: ntfy

[ntfy](https://ntfy.sh/) works well as a webhook target. How you point at a topic depends on the body format:

- **`text`** - put the topic in the URL path (`https://ntfy-host/your-topic`). Optional headers such as `Title:` and `Attach:` are the usual ntfy extras.
- **`json`** - POST to the **server root** only (`https://ntfy-host/`). The topic must be in the JSON body as `"topic": "..."`. Do not put the topic in the URL for JSON publishes.

### Text

```config
PA_WEBHOOK=ON
PA_WEBHOOK_URLS=https://ntfy-host/your-topic
PA_WEBHOOK_FORMAT=text
```

Edit `webhook.pa.headers` on the persist volume (do **not** commit tokens to git), for example:

```text
Authorization: Bearer YOUR_TOKEN
Title: ||title||
Attach: ||image:thumblink||
```

- `Authorization` - whatever your ntfy instance requires (Bearer token, Basic, or omit for open topics).
- `Title: ||title||` - sets the ntfy notification title.
- `Attach: ||image:thumblink||` - optional; ntfy can attach by URL when a thumbnail link is available. These webhooks never upload local screenshot files.

### JSON

```config
PA_WEBHOOK=ON
PA_WEBHOOK_URLS=https://ntfy-host/
PA_WEBHOOK_FORMAT=json
```

Put auth in `webhook.pa.headers` as above (you can omit `Title:` / `Attach:` if those fields are already in the JSON body). Edit `webhook.pa.json.template` so it includes a `"topic"` field. Example for Plane-Alert on ntfy:

```json
{
  "topic": "planefence",
  "title": "Plane-Alert: ||owner|| is flying, ||type|| ||tail||",
  "message": "||distance:value|| ||dist_unit|| away at ||altitude:value|| ||alt_unit|| (||angle:value|| deg ||angle:name||), Speed ||groundspeed:value|| ||speed_unit||, Track: ||track:value|| deg",
  "markdown": true,
  "actions": [
    {
      "action": "view",
      "url": "||link:map||",
      "label": "Track Plane"
    }
  ]
}
```

`"topic"` is the ntfy topic name (here both Planefence and Plane-Alert can share `planefence`). Change it if you want a separate topic. The seeded JSON templates already include a `topic` field you can rename. For Planefence, use `PF_WEBHOOK*` and `webhook.pf.json.template` the same way.

### Check it

Restart or wait for the next Planefence cycle, then trigger a watchlist / fence alert and check your ntfy client. If the POST fails, look in the container logs.

The same pattern applies to Planefence with `PF_WEBHOOK*`, `webhook.pf.text.template` / `webhook.pf.json.template`, and `webhook.pf.headers`.

## Limits and security

- There is no multipart upload support. Media is URL-based only (placeholders such as `||image:thumblink||` in the body or in headers like ntfy's `Attach:`). Local screenshot paths are not sent as files.
- Keep tokens and private URLs on the persist volume (`webhook.*.headers`, `planefence.config` on the host). Do not commit Authorization headers or bearer tokens to a repository.
- Defaults seeded into persist may include commented ntfy examples; leave real secrets out of those files if you share or version the tree.

## Summary of License Terms

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
