# Configuration Guide

Primary source file:
`rootfs/usr/share/planefence/stage/persist/planefence.config.RENAME-and-EDIT-me`

## Reading This Reference

- `Required`: `Yes` means you should set it for normal operation.
- `Default/Behavior`: values and behavior are taken from template comments.
- Unless noted, parameters are optional.

## Required Station and Data Source

| Parameter | Description | Default/Behavior | Required |
| --- | --- | --- | --- |
| `FEEDER_LAT` | Station latitude (decimal; north positive, south negative). | Template example: `90.12345`. | Yes |
| `FEEDER_LONG` | Station longitude (decimal; east positive, west negative). | Template example: `-70.12345`. | Yes |
| `PF_SOCK30003HOST` | Hostname of SBS-30003 source (`ultrafeeder`, `dump1090[-fa]`, `readsb`, `tar1090`). | Template example: `ultrafeeder`. | Yes |
| `PF_SOCK30003PORT` | TCP port of SBS source. | `30003`. | Yes |
| `PF_MAXDIST` | Fence radius from station center, in `PF_DISTUNIT`. | Template example: `2.0`. | Yes |
| `PF_MAXALT` | Maximum altitude in fence, in `PF_ALTUNIT`. | Template example: `5000`. | Yes |

## General Parameters

| Parameter | Description | Default/Behavior | Required |
| --- | --- | --- | --- |
| `GENERATE_CSV` | Enable daily CSV export for Planefence/Plane-Alert. | `OFF` disables, `ON` enables. | No |
| `PF_INTERVAL` | Poll interval in seconds for new planes. | Template: `45`; recommended minimum `30`. | No |
| `PF_DISTUNIT` | Distance unit. | Allowed: `kilometer`, `nauticalmile`, `mile`, `meter`. Template: `nauticalmile`. | No |
| `PF_ALTUNIT` | Altitude unit. | Allowed: `meter`, `feet`. Template: `feet`. | No |
| `PF_SPEEDUNIT` | Speed unit. | Allowed: `kilometerph`, `knotph`, `mileph`. Template: `knotph`. | No |
| `PF_FUDGELOC` | Coordinate rounding for privacy. | `0` whole deg, `1` 0.1 deg, `2` 0.01 deg, `3` 0.001 deg; other non-empty behaves like `3`. | No |
| `PF_CHECKROUTE` | Enrich PF table with route info via adsb.im API. | If omitted, default behavior is ON unless explicitly disabled. | No |
| `PF_TRACKSERVICE` | Tracking map service for Planefence links. | Must be tar1090-style deep-link target. Template: `globe.adsbexchange.com`. | No |
| `PF_ELEVATION` | Station elevation above MSL in `PF_ALTUNIT`. | If `> 0`, PF reports AGL instead of MSL. Template: `0`. | No |
| `OPENSKYDB_DOWNLOAD` | Control OpenSky DB download/update. | Empty uses normal download behavior; set `disabled` to prevent downloads. | No |

## Web Page Parameters

| Parameter | Description | Default/Behavior | Required |
| --- | --- | --- | --- |
| `PF_HTTP_PORT` | HTTP port used inside container. | If omitted, `80`. Template: `80`. | No |
| `PF_NAME` | Short station label shown in page title. | Template: `"MY"`. | No |
| `PF_TABLESIZE` | Default PF rows per page. | Options: `10`, `25`, `50`, `100`, `all`; default noted as `50`. | No |
| `PF_MAPURL` | URL for station map link. | Full or relative URL. | No |
| `PF_MAPZOOM` | OpenStreetMap heatmap zoom level. | Template: `7`. | No |
| `PF_SHOWIMAGES` | Show planespotters images in UI/notifications. | Default true behavior; set `0/off/false/no` to disable. | No |
| `PF_OPENAIP_LAYER` | Show OpenAIP heatmap overlay. | `ON` enables layer. | No |
| `PF_OPENAIPKEY` | OpenAIP API key for overlay. | Required only if OpenAIP layer is enabled. | No |

## Planefence Parameters

| Parameter | Description | Default/Behavior | Required |
| --- | --- | --- | --- |
| `PLANEFENCE` | Enable Planefence feature/page. | If omitted, default behavior is enabled. | No |
| `PF_MOTD` | Message displayed at top of PF page. | Supports simple HTML. | No |
| `PF_DELETEAFTER` | Retention days for logs and JSON/CSV files. | Empty uses default `14`; `0` keeps forever. | No |
| `PF_NOISECAPT` | Base URL of NoiseCapt container. | Empty disables integration. | No |
| `PF_CHECKREMOTEDB` | Use remote helper DB for airline lookup. | Any non-empty value enables; empty disables. | No |
| `PF_IGNOREDUPES` | Show only first ICAO+flight combo per day. | Enabled when set to `yes/on/true/1/enabled`. | No |
| `PF_COLLAPSEWITHIN` | Minimum seconds between observations to create separate entries. | Closer observations are collapsed. Template: `300`. | No |

## Plane-Alert Parameters

| Parameter | Description | Default/Behavior | Required |
| --- | --- | --- | --- |
| `PLANEALERT` | Enable Plane-Alert feature/page. | Template: `enabled`. | No |
| `PA_TABLESIZE` | Default Plane-Alert rows per page. | Template: `50`. | No |
| `PA_MOTD` | Message displayed at top of Plane-Alert page. | Supports simple HTML. | No |
| `PF_PARANGE` | Plane-Alert radius in `PF_DISTUNIT`. | Empty means any aircraft reported by station. | No |
| `PF_PA_SQUAWKS` | Squawk codes that trigger Plane-Alert. | Comma-separated; supports `x` wildcard per digit. Empty disables squawk triggers. | No |
| `PF_ALERTLIST` | List inputs for Plane-Alert watch data. | Up to 10 comma-separated file names (config dir) or URLs. Concatenated list replaces built-in `plane-alert-db.txt`. | No |
| `PF_ALERTHEADER` | Header/field interpretation for alert file columns. | Field syntax: `Text`, `$Text`, `#Text`, `#$Text`; include `ICAO Type` column for silhouettes. | No |
| `PA_HISTTIME` | Days Plane-Alert entries remain visible. | Template: `14`. | No |
| `PA_SILHOUETTES_LINK` | URL for silhouette pack updates. | Empty/omitted uses default URL; `OFF` disables updates. | No |
| `PA_TRACKSERVICE` | Tracking map service for Plane-Alert links. | Template: `globe.adsbexchange.com`. | No |
| `PA_EXCLUSIONS` | Filters that suppress Plane-Alert notifications/UI entries. | Comma-separated ICAO type, ADS-B hex, or text; case-insensitive; URLs/images not searched. Empty disables filtering. | No |
| `PA_SHOW_STALE_PAGE` | Keep old `/plane-alert` page instead of redirecting to new page. | Truthy values enable stale page; empty/default behavior is redirect to new page. | No |
| `PA_COLLECT_CANDIDATES` | Enable auto-collection of Plane-Alert candidates from socket30003 data. | `ON/true/enabled/1/yes` enables; `OFF/false/disabled/0/no/empty` disables. | No |
| `PA_COLLECT_CANDIDATES_FILTER_FILE` | Alternate filter filename in config directory. | Empty uses `pa-candidates-filter.txt`. | No |
| `PA_COLLECT_CANDIDATES_LOG` | Optional candidate-match log file. | Empty disables this logging. | No |

## Global Notification Parameters

| Parameter | Description | Default/Behavior | Required |
| --- | --- | --- | --- |
| `NOTIF_DATEFORMAT` | Date/time format used in notifications and tables. | Linux `date` format; template: `"%F %T %Z"`. | No |
| `PF_NOTIFEVERY` | Send notification for every qualifying PF occurrence. | Template: `false`. | No |
| `PF_NOTIF_MINTIME` | Minimum delay (seconds) before PF notification. | Interpretation depends on `PF_NOTIF_BEHAVIOR`. | No |
| `PF_NOTIF_BEHAVIOR` | Timing basis for PF notification delay. | `pre`: from first observation; `post`: from last observation; default behavior if omitted is `post`. | No |
| `PF_ATTRIB` | Attribution text appended to PF notifications. | Template value provided. | No |
| `PA_ATTRIB` | Attribution text appended to PA notifications. | Template value provided. | No |
| `PF_SCREENSHOTURL` | Screenshot service base URL. | Default behavior expects `http://screenshot:5042` if not overridden. | No |
| `PF_SCREENSHOT_TIMEOUT` | Maximum wait for screenshot generation. | Template: `45` seconds. | No |

## Discord Parameters

| Parameter | Description | Default/Behavior | Required |
| --- | --- | --- | --- |
| `PA_DISCORD` | Enable Discord notifications for Plane-Alert. | `ON` enables. Template: `OFF`. | No |
| `PF_DISCORD` | Enable Discord notifications for Planefence. | `ON` enables. Template: `OFF`. | No |
| `PA_DISCORD_WEBHOOKS` | Comma-separated Discord webhook URLs for Plane-Alert. | Empty disables posting for PA. | No |
| `PF_DISCORD_WEBHOOKS` | Comma-separated Discord webhook URLs for Planefence. | Empty disables posting for PF. | No |
| `DISCORD_FEEDER_NAME` | Friendly feeder name in Discord messages. | Can use markdown link format shown in template comments. | No |
| `DISCORD_MEDIA` | Media mode for Discord posts. | Options: empty, `screenshot`, `photo`, `photo+screenshot`, `screenshot+photo`; template: `screenshot+photo`. | No |
| `PA_DISCORD_COLOR` | Embed highlight color for PA. | Names, hex, or decimal RGB accepted; template: `0xf2e718`. | No |
| `PF_DISCORD_COLOR` | Embed highlight color for PF. | Names, hex, or decimal RGB accepted; template: `0xf2e718`. | No |

## Mastodon Parameters

| Parameter | Description | Default/Behavior | Required |
| --- | --- | --- | --- |
| `PF_MASTODON` | Enable Mastodon notifications for Planefence. | Template: `OFF`. | No |
| `PA_MASTODON` | Enable Mastodon notifications for Plane-Alert. | Template: `OFF`. | No |
| `MASTODON_SERVER` | Mastodon server hostname (without protocol). | Template: `airwaves.social`. | No |
| `MASTODON_ACCESS_TOKEN` | Mastodon app access token. | Empty disables posting authentication. | No |
| `PF_MASTODON_VISIBILITY` | PF post visibility. | Values include `public`, `unlisted`, `private`; template: `unlisted`. | No |
| `PA_MASTODON_VISIBILITY` | PA post visibility. | Values include `public`, `unlisted`, `private`; template: `unlisted`. | No |
| `PA_MASTODON_MAXIMGS` | Max images per PA Mastodon post. | Template: `1`. | No |
| `MASTODON_RETENTION_TIME` | Retention window used by Mastodon posting logic. | Template: `7`. | No |

## MQTT Parameters (Planefence)

| Parameter | Description | Default/Behavior | Required |
| --- | --- | --- | --- |
| `PF_MQTT_URL` | Broker URL or host (`mqtt://` or `mqtts://`). | If omitted/empty, MQTT disabled. | No |
| `PF_MQTT_PORT` | Broker TCP port. | Default behavior is `1883` if not set. | No |
| `PF_MQTT_TLS` | Toggle TLS usage. | Set to enable TLS; unset for plaintext. | No |
| `PF_MQTT_CAFILE` | CA certificate path for self-signed broker certs. | Empty means no custom CA file. | No |
| `PF_MQTT_TLS_INSECURE` | Disable certificate verification. | `true` disables verification; default behavior `false`. | No |
| `PF_MQTT_CLIENT_ID` | MQTT client identifier. | Default behavior uses container hostname. | No |
| `PF_MQTT_TOPIC` | MQTT topic. | Default behavior uses `<hostname>/planefence`. | No |
| `PF_MQTT_DATETIME_FORMAT` | Datetime format for MQTT payload. | Default behavior `%s`. | No |
| `PF_MQTT_QOS` | MQTT QoS level. | Default behavior `0`. | No |
| `PF_MQTT_FIELDS` | Limit payload fields. | Empty means send all fields. | No |
| `PF_MQTT_USERNAME` | MQTT username. | Optional basic auth. | No |
| `PF_MQTT_PASSWORD` | MQTT password. | Optional basic auth. | No |

## MQTT Parameters (Plane-Alert)

| Parameter | Description | Default/Behavior | Required |
| --- | --- | --- | --- |
| `PA_MQTT_URL` | Broker URL or host (`mqtt://` or `mqtts://`). | If omitted/empty, MQTT disabled. | No |
| `PA_MQTT_PORT` | Broker TCP port. | Default behavior is `1883` if not set. | No |
| `PA_MQTT_TLS` | Toggle TLS usage. | Set to enable TLS; unset for plaintext. | No |
| `PA_MQTT_CAFILE` | CA certificate path for self-signed broker certs. | Empty means no custom CA file. | No |
| `PA_MQTT_TLS_INSECURE` | Disable certificate verification. | `true` disables verification; default behavior `false`. | No |
| `PA_MQTT_CLIENT_ID` | MQTT client identifier. | Default behavior uses container hostname. | No |
| `PA_MQTT_TOPIC` | MQTT topic. | Default behavior uses `<hostname>/plane-alert`. | No |
| `PA_MQTT_DATETIME_FORMAT` | Datetime format for MQTT payload. | Default behavior `%s`. | No |
| `PA_MQTT_QOS` | MQTT QoS level. | Default behavior `0`. | No |
| `PA_MQTT_FIELDS` | Limit payload fields. | Empty means send all fields. | No |
| `PA_MQTT_USERNAME` | MQTT username. | Optional basic auth. | No |
| `PA_MQTT_PASSWORD` | MQTT password. | Optional basic auth. | No |

## RSS Parameters

| Parameter | Description | Default/Behavior | Required |
| --- | --- | --- | --- |
| `PF_RSS_SITELINK` | Base site URL for PF RSS links/validation. | Empty disables PF RSS. | No |
| `PF_RSS_FAVICONLINK` | Favicon URL for PF RSS feed metadata. | Optional. | No |
| `PA_RSS_SITELINK` | Base site URL for PA RSS links/validation. | Empty disables PA RSS. | No |
| `PA_RSS_FAVICONLINK` | Favicon URL for PA RSS feed metadata. | Optional. | No |

## BlueSky Parameters

| Parameter | Description | Default/Behavior | Required |
| --- | --- | --- | --- |
| `BLUESKY_APP_PASSWORD` | BlueSky app password (`aaaa-bbbb-cccc-dddd` format). | Required only if BlueSky posting is enabled. | No |
| `BLUESKY_HANDLE` | BlueSky handle value after `@`. | Required only if BlueSky posting is enabled. | No |
| `PF_BLUESKY_ENABLED` | Enable PF BlueSky notifications. | Truthy values (`on/enabled/1/yes`) enable. | No |
| `PA_BLUESKY_ENABLED` | Enable PA BlueSky notifications. | Truthy values (`on/enabled/1/yes`) enable. | No |

## Telegram Parameters

| Parameter | Description | Default/Behavior | Required |
| --- | --- | --- | --- |
| `TELEGRAM_BOT_TOKEN` | Bot token used by Telegram notifications. | Optional global value for PF/PA unless overridden by prefixed values. | No |
| `PF_TELEGRAM_CHAT_ID` | PF target chat/channel ID (numeric or `@channel`). | Optional; needed when PF Telegram enabled. | No |
| `PA_TELEGRAM_CHAT_ID` | PA target chat/channel ID (numeric or `@channel`). | Optional; needed when PA Telegram enabled. | No |
| `PF_TELEGRAM_ENABLED` | Enable PF Telegram notifications. | Truthy values (`on/enabled/1/yes/true`) enable. Template: `false`. | No |
| `PA_TELEGRAM_ENABLED` | Enable PA Telegram notifications. | Truthy values (`on/enabled/1/yes/true`) enable. Template: `false`. | No |
| `PF_TELEGRAM_CHAT_TYPE` | PF chat type behavior. | `dm/private/user` sends direct messages; template `normal`. | No |
| `PA_TELEGRAM_CHAT_TYPE` | PA chat type behavior. | `dm/private/user` sends direct messages; template `normal`. | No |

## Configuration Workflow

1. Start the container once to generate config files.
2. Edit `planefence.config.RENAME-and-EDIT-me`.
3. Rename to `planefence.config`.
4. Recreate the service/container.
5. Validate via logs and web UI.
