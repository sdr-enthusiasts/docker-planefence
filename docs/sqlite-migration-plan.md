# SQLite Migration Plan (Canonical)

Last updated: 2026-06-20
Status: Active implementation plan

## Synchronization Policy (Mandatory)

This file is the canonical in-repository plan artifact for the SQLite migration work.

Rules:

1. Implementation must not proceed unless this file exists and reflects current execution intent.
2. Any change to internal planning, execution parameters, rollout constraints, risk controls, or verification criteria must be mirrored here in the same working batch.
3. If drift is detected between internal planning and this file, implementation pauses until this file is reconciled.
4. Session start/end checks must confirm this file is current before code changes continue.
5. Final acceptance requires verifying this file is up to date and complete.

## Objective

Replace gzip-serialized Bash associative-array state with an embedded SQLite backend that:

1. Runs from tmpfs-backed runtime storage for low IO latency.
2. Persists via periodic and shutdown checkpoints.
3. Preserves existing output/API contracts (JSON/CSV/query endpoints/notifications).
4. Migrates automatically from legacy records with no user interaction required.

## Current Constraints and Requirements

1. Keep container size impact minimal.
2. Optimize for Raspberry Pi 3B+ baseline, with strong behavior on Pi 4/5 and x86 Linux.
3. Keep security posture suitable for internet-exposed web endpoints.
4. No extra containers required; DB must be in-container.
5. Add optional config knobs only when defaults are safe and seamless.
6. Any new user-configurable parameters must be available in both planefence.config and the web config UI.

## Environment Boundary for Live Testing (Mandatory)

Implementation testing and debugging is restricted to:

1. Account/host/path: prod@zt-prod:/opt/pf-db/
2. Container scope: pf-db container only

Allowed:

1. File changes only under /opt/pf-db and subdirectories
2. Docker commands only for pf-db (build, run, exec, logs, stop, restart, recreate, remove)
3. General Linux diagnostics only as they pertain to pf-db development/testing

Not allowed:

1. Any other account or host
2. Any modifications outside /opt/pf-db
3. Any host-level OS changes unrelated to pf-db
4. Any actions against other containers

## Architecture

### Storage Layout

1. Runtime DB (tmpfs): /run/planefence/planefence-records.sqlite
2. Persistent checkpoint: /usr/share/planefence/persist/records/planefence-records.sqlite
3. Derived artifacts remain unchanged in behavior (JSON/CSV generated and synced as today)

### Schema Direction

1. Separate tables for Planefence and Plane-Alert records
2. Indexed hot fields (icao, timestamps, notify status, etc.)
3. JSON payload column for long-tail dynamic fields
4. Globals table for LASTPROCESSEDLINE, maxindex, HAS* flags, station metadata
5. Heatmap aggregation table
6. Day-partition column in a single long-lived DB for retention and queries
7. Row version and updated_at fields for optimistic concurrency

## SQLite Runtime and Tuning

Base pragmas:

1. journal_mode=WAL
2. synchronous=NORMAL
3. temp_store=MEMORY
4. busy_timeout configured by profile

Profiles (auto-selected by architecture and memory guardrails):

### Pi 3B+ baseline

1. cache_size=-8192 (8 MiB)
2. mmap_size=67108864 (64 MiB)
3. wal_autocheckpoint=512 pages
4. busy_timeout=8000 ms
5. external checkpoint interval=600 s

### Pi 4/5

1. cache_size=-32768 (32 MiB)
2. mmap_size=268435456 (256 MiB)
3. wal_autocheckpoint=1000 pages
4. busy_timeout=8000 ms
5. external checkpoint interval=300 s

### x86

1. cache_size=-65536 (64 MiB)
2. mmap_size=536870912 (512 MiB)
3. wal_autocheckpoint=2000 pages
4. busy_timeout=10000 ms
5. external checkpoint interval=300 s

Guardrail:

1. Downshift cache and mmap automatically under low-memory conditions.

## Concurrency Strategy (Replace Coarse Global Lock)

Current system relies on /tmp/.records.lock around read-modify-write of entire datasets.
New strategy minimizes blocking via SQLite-native concurrency:

1. Many readers + short write transactions under WAL.
2. Read-only operations use deferred read transactions.
3. Mutations use short BEGIN IMMEDIATE transactions scoped to touched rows only.
4. Optimistic CAS updates with version checks for competing field updates.
5. Bounded retry with jitter for busy/conflict cases.
6. Micro-batching for burst updates (for example notifier/screenshot status writes).
7. Remove full snapshot read-modify-write cycles from hot paths.
8. Keep /tmp/.records.lock only for migration bootstrap/legacy compatibility during transition, then remove from steady-state data path.

Observability:

1. busy retry counts
2. conflict retry counts
3. average/max write transaction duration

## Migration and Recovery

### Automated Migration

1. One-time startup migration imports retained legacy planefence-records-*.gz into SQLite.
2. Migration marker stored under persist/.internal to enforce idempotency.
3. No user action required.

### Checkpointing and Shutdown

1. Periodic checkpoint/copy from /run DB to persist records path.
2. Final checkpoint/copy on controlled shutdown path.

### Corruption Handling

1. Startup integrity checks detect corruption.
2. If corrupt/unavailable, restore from latest persistent checkpoint.
3. If needed, re-import legacy retained sources.
4. If no recoverable source, initialize clean DB and continue ingest.

## Phased Execution Plan

1. Phase 1: DB helper + schema + pragmas + profiles
2. Phase 1b: concurrency architecture and lock-transition scaffolding
3. Phase 2: pf-common storage abstraction and PFDB API layer
4. Phase 3: migrate pf-process writer path to targeted DB operations
5. Phase 4: migrate consumers (notifiers, screenshot, query scripts, maintenance scripts)
6. Phase 5: startup migration, retention, fallback/recovery hardening
7. Phase 6: config and config-UI integration for optional DB knobs
8. Phase 7: validation/perf/security hardening
9. Phase 8: environment-constrained live testing gate (prod@zt-prod:/opt/pf-db, pf-db only)

## Verification Plan

Core verification:

1. Output parity: JSON/CSV/query endpoint behavior
2. Notifier correctness: eligible/stale/status transitions
3. Migration matrix: fresh install, single-day legacy, multi-day legacy, corrupt legacy source
4. Concurrency/load: overlapping pf-process/screenshot/notifier/API reads
5. Lock-removal validation for steady-state path
6. Performance baselines: latency, CPU, RSS, write rate (Pi 3B+, Pi 4/5, x86)
7. Security fuzzing for query interfaces and request bounds

Environment-scoped verification (pf-db only):

1. Boundary compliance preflight and fail-fast checks
2. Build/recreate pf-db and health/log checks
3. Functional smoke: UI root, cgi/stream.sh, cgi/insights.sh, pf_query.php, pa_query.php
4. Upgrade migration with legacy records and marker verification
5. Crash/restart recovery drills
6. Controlled corruption drills and recovery validation
7. Retention/checkpoint IO envelope checks
8. Post-run audit capture of commands/files/container state

## Initial Implementation Gate

Before code implementation changes begin:

1. This file must remain the current canonical plan.
2. Any plan delta must be committed here first or in the same batch.

## Execution Log

### 2026-06-20

1. Created canonical repository migration plan file and enabled synchronization policy.
2. Added SQLite helper utility [rootfs/usr/share/planefence/pf-db.py](rootfs/usr/share/planefence/pf-db.py) with profile selection, schema initialization, pragma setup, and integrity-check command support.
3. Added non-breaking DB configuration scaffolding in [rootfs/usr/share/planefence/stage/persist/planefence.config.RENAME-and-EDIT-me](rootfs/usr/share/planefence/stage/persist/planefence.config.RENAME-and-EDIT-me), [rootfs/usr/share/planefence/planefence.conf](rootfs/usr/share/planefence/planefence.conf), [rootfs/usr/share/planefence/plane-alert.conf](rootfs/usr/share/planefence/plane-alert.conf), [rootfs/usr/share/planefence/prep-planefence.sh](rootfs/usr/share/planefence/prep-planefence.sh), [rootfs/usr/share/planefence/stage/persist/.internal/config-ui.schema.json](rootfs/usr/share/planefence/stage/persist/.internal/config-ui.schema.json), and [rootfs/usr/share/planefence/config_web_lib.php](rootfs/usr/share/planefence/config_web_lib.php).
4. Added startup-time SQLite initialization hook in [rootfs/usr/share/planefence/prep-planefence.sh](rootfs/usr/share/planefence/prep-planefence.sh), gated by PF_RECORDS_BACKEND=sqlite with non-fatal fallback to legacy path.
5. Implemented sqlite compatibility storage mode in [rootfs/scripts/pf-common](rootfs/scripts/pf-common), including backend auto-detection, sqlite day-snapshot load/save paths for READ_RECORDS and WRITE_RECORDS, lock bypass in sqlite mode, and runtime-to-persist checkpoint helper support.
6. Extended [rootfs/usr/share/planefence/pf-db.py](rootfs/usr/share/planefence/pf-db.py) with snapshot and migration commands: save-day, load-day, and migrate-legacy-day.
7. Added sqlite persistence lifecycle hooks in [rootfs/usr/share/planefence/prep-planefence.sh](rootfs/usr/share/planefence/prep-planefence.sh), [rootfs/usr/share/planefence/pf-run.sh](rootfs/usr/share/planefence/pf-run.sh), and [rootfs/etc/s6-overlay/scripts/planefence-finish](rootfs/etc/s6-overlay/scripts/planefence-finish) for startup restore/migration, periodic checkpoint, and shutdown checkpoint.
8. Implemented initial Phase 3 hot-path row syncing: [rootfs/usr/share/planefence/pf-db.py](rootfs/usr/share/planefence/pf-db.py) now includes `sync-hot-data` for batched PF/PA row upserts, heatmap upserts, and globals updates; [rootfs/usr/share/planefence/pf-process_sbs.sh](rootfs/usr/share/planefence/pf-process_sbs.sh) now tracks touched row sets and submits targeted sqlite updates each cycle before legacy-compatible snapshot persistence.
