# Troubleshooting

This page is distilled from the `README.md` troubleshooting section.

## Quick Checks

- Verify `docker-compose.yml` service settings.
- Verify `planefence.config` values, especially feeder host/port.
- Check logs:

```bash
docker logs -f planefence
```

Some startup warnings are expected initially.

## Web UI Checks

- Planefence page is expected at `http://<host>:8088`
- Plane-Alert page is expected at `http://<host>:8088/plane-alert`

## Cannot Reach SBS Source on Port 30003

If you see an error like `We cannot reach {host} on port 30003`, check:

- `PF_SOCK30003HOST` points to the right container, host, or IP
- SBS output is enabled in your feeder stack
- If feeder and Planefence are in different stacks, ensure required port exposure/routing

Notes from `README.md`:

- Non-containerized `dump1090`/`readsb`/`tar1090`: add `--net-sbs-port 30003`
- `readsb-protobuf`: set `READSB_NET_SBS_OUTPUT_PORT=30003`
- `ultrafeeder`: SBS generally available, and MLAT forwarding can be enabled with `READSB_FORWARD_MLAT_SBS=true`

## Exclusion Rule Validation

When using `PA_EXCLUSIONS`, verify behavior in logs after edits to ensure filters match intended planes only.
