# Copilot instructions for docker-planefence

## Big picture architecture
- This project is a containerized Bash-first pipeline, not a framework app. Runtime orchestration is `s6-overlay` services under `rootfs/etc/s6-overlay/s6-rc.d/`.
- Primary flow: SBS input (`socket30003`) -> record processing (`pf-process_sbs.sh`) -> daily JSON/CSV outputs -> web UI + notifier fan-out.
- `socket30003` writes rolling capture files to `/run/socket30003/dump1090-*-YYMMDD.txt`; `planefence` service consumes those files on each loop.
- `pf-run.sh` executes `pf-process_sbs.sh`, runs notifier scripts (`notifiers/send*.sh`), and periodically syncs runtime artifacts from `/run/planefence` to `/usr/share/planefence/html`.
- Frontend is a single large HTML app (`rootfs/usr/share/planefence/stage/html/index.html`) that switches between `planefence` and `plane-alert` modes and consumes CGI data endpoints.

## Service and data boundaries
- UI data endpoints are CGI wrappers in `stage/html/cgi/` calling shell scripts:
  - `stream.sh` -> NDJSON stream/snapshot from `/usr/share/planefence/stream.sh`
  - `insights.sh` -> aggregated insights JSON from `/usr/share/planefence/insights.sh`
- Legacy query APIs are PHP wrappers (`pf_query.php`, `pa_query.php`) that shell out to `pf_query.sh` / `pa_query.sh` and filter in-memory records.
- Record state is shell-serialized associative arrays (`records`, `pa_records`) managed via `READ_RECORDS`/`WRITE_RECORDS` in `rootfs/scripts/pf-common`.
- Locking convention is file-based (`/tmp/.records.lock`); preserve it when touching read/write paths.

## Configuration conventions (project-specific)
- `planefence.config` in `/usr/share/planefence/persist` is source of truth; `prep-planefence.sh` maps env/config into `planefence.conf` and `plane-alert.conf` via `configure_*` helpers.
- Runtime HTML is copied from `rootfs/usr/share/planefence/stage/html` at container start. **Edit `stage/` files, not `/usr/share/planefence/html` runtime targets.**
- Feature toggles use helper semantics from `pf-common` (`chk_enabled`/`chk_disabled`) and often accept multiple legacy variable names; keep backward compatibility.
- Plane-Alert defaults differ from Planefence in history/date behavior (for example `all` date handling in stream mode).

## Key integration points
- External services used directly in scripts include ADS-B route/type lookups, OpenSkyDB, Mastodon verification, and optional screenshot service.
- Notifier pipeline is script-discovery based (`notifiers/send*.sh`); adding a notifier means adding `send_*.sh` with failure-tolerant behavior.
- `insights.sh` includes multi-layer caching (`/tmp/insights-cache-*` + persisted `.internal/insights-cache`) and timezone recovery logic from s6/lighttpd env.

## Developer workflows
- **User override:** if instructions here conflict with operator instructions, operator instructions take precedence.
- Do **not** build or run a local test container on the development machine.
- All implementation testing must use remote `planefence-dev` as defined below.
- For release/publish, use `./buildnow.sh [branch]` as part of `run the pipeline`.
- Minimum smoke test after deploy/recreate: container up (`docker compose ps`/`docker ps`), healthy logs (`docker logs`), and endpoint checks (`https://kx1t.com/planefence-dev`, `cgi/stream.sh`, `cgi/insights.sh`).

## Live environment access policy (explicitly allowed)
- For live testing, AI agents may SSH to `prod@prod`; if unreachable, fallback to `prod@zt-prod`.
- Target deployment is container `planefence-dev`, defined on host in `/opt/adsb/docker-compose.yml`.
- Allowed host/container actions for `planefence-dev` only:
  - `docker compose pull` for updated image
  - `docker compose stop|start|restart|up --force-recreate`
  - `docker compose ps` / `docker ps` status checks
  - `docker logs` for `planefence-dev`
  - `docker exec` shell access
  - test-only code insertion directly in container via `docker exec`
- Allowed UX endpoint testing: `https://kx1t.com/planefence-dev` via `curl`, `wget`, or temporary test scripts.

## Forbidden actions (unless explicitly approved)
- Do not build/test local containers on the development machine (for example `docker build`, `docker compose up` locally for validation).
- Do not run deployment or test operations against containers/environments other than `planefence-dev`.
- Do not SSH to hosts/accounts other than `prod@prod` and `prod@zt-prod`.
- Do not perform host-level/admin changes unrelated to `planefence-dev` lifecycle/testing.
- Do not assume standing permission: if an action is outside the explicit allowlist above, ask first.

## Permission boundaries
- For any system/account other than the above, request explicit one-time human approval before execution.
- One-time approval applies to a single execution unless the human explicitly extends it to the full session.

## Shared operator terms
- `quick-deploy`: inject changed code directly into running `planefence-dev` and test there.
- `run the pipeline`: save all changes, commit and push to branch `pf-restruct`, run `buildnow.sh` to rebuild/push image, SSH to `prod@prod` (or `prod@zt-prod` fallback), pull image, recreate `planefence-dev`, then run smoke tests (minimum: container up and healthy).

## Allowed command examples (for deterministic execution)
- `quick-deploy` example sequence (on target host):
  1. `cd /opt/adsb`
  2. `docker compose ps planefence-dev`
  3. `docker exec -it planefence-dev bash`
  4. Inject/edit test code in-container (`docker exec ... sh -lc '...'`)
  5. `docker logs --tail 200 planefence-dev`
  6. `curl -fsS https://kx1t.com/planefence-dev`
- `run the pipeline` example sequence:
  1. Local repo: save changes, `git add`, `git commit`, `git push origin pf-restruct`
  2. Local repo: `./buildnow.sh pf-restruct`
  3. Remote host (`prod@prod`, fallback `prod@zt-prod`): `cd /opt/adsb`
  4. `docker compose pull planefence-dev`
  5. `docker compose up -d --force-recreate planefence-dev`
  6. `docker compose ps planefence-dev` (or `docker ps`)
  7. `docker logs --tail 200 planefence-dev`
  8. Smoke test endpoints: `curl -fsS https://kx1t.com/planefence-dev`, `curl -fsS https://kx1t.com/planefence-dev/cgi/stream.sh`, `curl -fsS https://kx1t.com/planefence-dev/cgi/insights.sh`

## Editing guidelines for AI agents
- Prefer surgical edits in shell scripts; preserve existing quoting, `sed` delimiter style (`|`/`~`), and bash compatibility patterns.
- When changing data schema/fields, update both producer and consumer paths: `pf-process_sbs.sh` -> `stream.sh`/`insights.sh` -> `stage/html/index.html` render/export code.
- Keep mode parity (`planefence` vs `plane-alert`): most features are dual-path and must be updated in both branches.
- Do not remove migration/compat code in startup scripts unless explicitly requested; many users upgrade in place with old configs.