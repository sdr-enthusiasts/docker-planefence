# Installation Guide

This guide is based on `README.md` and is intended for Docker Compose deployments.

## Prerequisites

- A running ADS-B feeder station using one of: `ultrafeeder`, `tar1090`, `dump1090[-fa]`, or `readsb`
- SBS output enabled on TCP port `30003`
- Docker and Docker Compose available on the host

## 1. Create a Project Directory

If you are not adding Planefence to an existing stack:

```bash
sudo mkdir -p -m 0777 /opt/planefence
sudo chmod a+rwx /opt/planefence
cd /opt/planefence
```

Important note from `README.md`: if you are using adsb.im, place Planefence in its own directory (for example, `/opt/planefence`).

## 2. Get `docker-compose.yml`

```bash
curl -s https://raw.githubusercontent.com/sdr-enthusiasts/docker-planefence/main/docker-compose.yml > docker-compose.yml
```

## 3. First Container Start

- Update `TZ` in `docker-compose.yml`.
- Start Planefence:

```bash
docker compose up -d
```

- Watch logs:

```bash
docker logs -f planefence
```

On first start, warnings about missing `planefence.config` are expected.

## 4. Configure Planefence

Edit and rename the generated config template:

```bash
cd /opt/planefence
nano planefence-config/planefence.config.RENAME-and-EDIT-me
mv planefence-config/planefence.config.RENAME-and-EDIT-me planefence-config/planefence.config
```

Recreate the service:

```bash
docker compose up -d planefence --force-recreate
```

## 5. Optional Setup

- `planefence-ignore.txt` for filtering planes from Planefence
- `airlinecodes.txt` for custom flight-prefix-to-airline mapping
- Reverse proxy setup: see `README-nginx-rev-proxy.md`
- Screenshot support via `screenshot` service in `docker-compose.yml`
- OpenAIP layer by setting `PF_OPENAIP_LAYER=ON` with a valid `PF_OPENAIPKEY`

## Restart and Update

Restart:

```bash
pushd /opt/planefence
docker compose up -d planefence --force-recreate
popd
```

Update image:

```bash
pushd /opt/planefence
docker compose pull planefence
docker compose up -d planefence
popd
```
