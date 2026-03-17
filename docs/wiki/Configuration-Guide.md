# Configuration Guide

This is the quick-start configuration path for most users.

For full parameter-by-parameter documentation, see:
`Advanced-Configuration-Reference.md`

Primary source file:
`rootfs/usr/share/planefence/stage/persist/planefence.config.RENAME-and-EDIT-me`

## 1. First-Run Workflow

1. Start the container once so config files are generated.
2. Edit `planefence.config.RENAME-and-EDIT-me`.
3. Rename it to `planefence.config`.
4. Recreate the Planefence container.
5. Validate with logs and web UI.

## 2. Minimum Required Parameters

Set these before production use:

| Parameter | Why It Matters | Example/Default Behavior |
| --- | --- | --- |
| `FEEDER_LAT` | Station latitude; used for fence distance and map context. | Example: `90.12345` |
| `FEEDER_LONG` | Station longitude; used for fence distance and map context. | Example: `-70.12345` |
| `PF_SOCK30003HOST` | SBS data source host name/IP. | Example: `ultrafeeder` |
| `PF_SOCK30003PORT` | SBS data source TCP port. | Default: `30003` |
| `PF_MAXDIST` | Fence radius around your station. | Example: `2.0` |
| `PF_MAXALT` | Altitude cap for in-fence events. | Example: `5000` |

## 3. Recommended Early Settings

| Parameter | Recommendation | Default/Behavior |
| --- | --- | --- |
| `PF_DISTUNIT` | Choose unit system first. | Template: `nauticalmile` |
| `PF_ALTUNIT` | Align altitude with your preference. | Template: `feet` |
| `PF_NAME` | Set station label shown in UI. | Template: `"MY"` |
| `PF_MAPURL` | Point to your tar1090/map URL for deep links. | Template example provided |
| `PF_TRACKSERVICE` | Use your preferred track service. | Template: `globe.adsbexchange.com` |
| `PF_FUDGELOC` | Keep privacy rounding enabled unless needed otherwise. | Template: `3` |
| `PF_DELETEAFTER` | Adjust retention policy for disk management. | Empty defaults to `14`; `0` keeps forever |

## 4. Feature Toggles You’ll Commonly Use

| Area | Key Parameters | Default/Behavior |
| --- | --- | --- |
| Core features | `PLANEFENCE`, `PLANEALERT` | Both enabled in template |
| Plane-Alert inputs | `PF_ALERTLIST`, `PF_ALERTHEADER` | Default list points to `plane-alert-db-images.csv` |
| Candidate collection | `PA_COLLECT_CANDIDATES`, `PA_COLLECT_CANDIDATES_FILTER_FILE`, `PA_COLLECT_CANDIDATES_LOG` | Collection is `ON` in template |
| Discord | `PF_DISCORD`, `PA_DISCORD`, `*_WEBHOOKS` | Disabled by default |
| Mastodon | `PF_MASTODON`, `PA_MASTODON`, token/server/visibility fields | Disabled by default |
| Telegram | `PF_TELEGRAM_ENABLED`, `PA_TELEGRAM_ENABLED`, bot/chat fields | Disabled by default |
| MQTT | `PF_MQTT_*`, `PA_MQTT_*` | Disabled when URL is empty |
| RSS | `PF_RSS_*`, `PA_RSS_*` | Disabled when site link is empty |
| BlueSky | `PF_BLUESKY_ENABLED`, `PA_BLUESKY_ENABLED`, app password/handle | Disabled by default |

## 5. High-Impact Optional Parameters

| Parameter | Impact |
| --- | --- |
| `PA_EXCLUSIONS` | Suppresses unwanted aircraft in Plane-Alert UI and notifications. |
| `PF_NOTIFEVERY` | Can significantly increase notification volume when enabled. |
| `PF_COLLAPSEWITHIN` | Changes how frequently repeat observations create separate entries. |
| `PF_ELEVATION` | Switches altitude display behavior to AGL when greater than zero. |
| `PF_OPENAIP_LAYER` + `PF_OPENAIPKEY` | Enables OpenAIP overlays on heatmap. |

## 6. Full Reference

Need exact parameter-level detail for defaults, allowed values, and behavior?

- `docs/wiki/Advanced-Configuration-Reference.md`
