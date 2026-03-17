# Feature Documentation

This page summarizes documented features from `README.md` and related README files.

## Core Features

- Fence-based aircraft logging using distance and altitude thresholds
- Web UI for Planefence and Plane-Alert
- Daily CSV export support
- REST query endpoints for Planefence and Plane-Alert data

## Data Source Compatibility

Documented feeder/source compatibility:

- `ultrafeeder`
- `readsb`
- `dump1090`
- `dump1090-fa`
- `tar1090`

## Notifications

Supported channels listed in project docs/config:

- BlueSky
- Mastodon
- Discord
- Telegram
- RSS
- MQTT

X/Twitter support is documented as deprecated in `README.md`.

## Plane-Alert Candidate Collection

Documented candidate collection features:

- `PA_COLLECT_CANDIDATES` toggle
- Pattern filter input file
- Candidate output file
- Optional match logging file

## API Features

Documented endpoints and formats:

- Planefence query endpoint: `pf_query.php`
- Plane-Alert query endpoint: `pa_query.php`
- Output formats: `json` (default) and `csv`
- Query values support awk-style regular expressions

## Related Feature Docs

- Discord: `README-discord-alerts.md`
- Mastodon: `README-Mastodon.md`
- Telegram: `README-telegram.md`
- Reverse proxy: `README-nginx-rev-proxy.md`
