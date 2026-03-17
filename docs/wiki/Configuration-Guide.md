# Configuration Guide

Primary reference file:
`rootfs/usr/share/planefence/stage/persist/planefence.config.RENAME-and-EDIT-me`

## Required Station and Data Source Parameters

Set these before first real use:

- `FEEDER_LAT`
- `FEEDER_LONG`
- `PF_SOCK30003HOST`
- `PF_SOCK30003PORT` (default shown: `30003`)
- `PF_MAXDIST`
- `PF_MAXALT`

## General Parameters

Commonly adjusted values:

- `PF_INTERVAL`
- `PF_DISTUNIT`
- `PF_ALTUNIT`
- `PF_SPEEDUNIT`
- `PF_FUDGELOC` (privacy-related coordinate rounding)
- `PF_TRACKSERVICE`
- `PF_ELEVATION`
- `OPENSKYDB_DOWNLOAD`

## Web UI Parameters

- `PF_HTTP_PORT`
- `PF_NAME`
- `PF_TABLESIZE`
- `PF_MAPURL`
- `PF_MAPZOOM`
- `PF_SHOWIMAGES`
- `PF_OPENAIP_LAYER`
- `PF_OPENAIPKEY`

## Planefence Behavior Parameters

- `PLANEFENCE`
- `PF_MOTD`
- `PF_DELETEAFTER`
- `PF_NOISECAPT`
- `PF_CHECKREMOTEDB`
- `PF_IGNOREDUPES`
- `PF_COLLAPSEWITHIN`

## Plane-Alert Parameters

- `PLANEALERT`
- `PA_TABLESIZE`
- `PA_MOTD`
- `PF_PARANGE`
- `PF_PA_SQUAWKS`
- `PA_HISTTIME`
- `PA_EXCLUSIONS`
- `PA_SHOW_STALE_PAGE`

### Alert List Inputs (`PF_ALERTLIST`)

`PF_ALERTLIST` supports up to 10 comma-separated entries, where each entry can be:

- A filename in your mapped config directory
- A URL

According to the template comments, concatenated lists replace the built-in `plane-alert-db.txt`, and including the default upstream list is recommended.

Example default value from template:

```bash
PF_ALERTLIST=https://raw.githubusercontent.com/sdr-enthusiasts/plane-alert-db/main/plane-alert-db-images.csv
```

Related fields:

- `PF_ALERTHEADER` (controls column interpretation)
- `PA_COLLECT_CANDIDATES` and related candidate file/log parameters

## Notification Parameters

Global notification controls:

- `NOTIF_DATEFORMAT`
- `PF_NOTIFEVERY`
- `PF_NOTIF_MINTIME`
- `PF_NOTIF_BEHAVIOR`
- `PF_ATTRIB`
- `PA_ATTRIB`

Channel-specific groups in the template:

- Discord (`PF_DISCORD`, `PA_DISCORD`, webhooks, media, colors)
- Mastodon (`PF_MASTODON`, `PA_MASTODON`, server/token/visibility)
- MQTT (PF and PA URL/port/TLS/topic/credentials fields)
- RSS (`PF_RSS_*`, `PA_RSS_*`)
- BlueSky (`BLUESKY_*`, `PF_BLUESKY_ENABLED`, `PA_BLUESKY_ENABLED`)
- Telegram (`TELEGRAM_BOT_TOKEN`, `PF_*/PA_*` telegram controls)

## Configuration Workflow

1. Start the container once to generate config files.
2. Edit `planefence.config.RENAME-and-EDIT-me` values.
3. Rename the file to `planefence.config`.
4. Recreate the container.
5. Confirm behavior in logs and web UI.
