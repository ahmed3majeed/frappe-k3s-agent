# Frappe Version Matrix

Environment baselines for each Frappe version tested against this k3s cluster, built to compare what actually differs between versions when setting up a bench end-to-end.

---

## Frappe v15

- **bench:** 5.31.0
- **Python:** 3.14.2
- **Node.js:** v24.13.0 (not explicitly re-checked for v15 with a bare `node --version` — inferred identical to v16's, since both benches use the exact same `frappe/bench:latest` image, unpinned)
- **MariaDB:** 10.11.18-MariaDB (native manifests, `frappe-system` namespace)
- **Redis:** cache/queue/socketio — 3 separate Bitnami-chart instances in `frappe-system`, each reporting v8.10.1 at install time
- **Frappe version:** 15.118.0, branch `version-15`
- **bench new-site flags:** originally used the now-deprecated `--no-mariadb-socket`; later switched to `--mariadb-user-host-login-scope='%'` (see Decision Log D5)
- **Deployment shape:** originally a bare `kind: Pod` (`bench-v15`), not a Deployment — a Phase 1 holdover later found to be a real limitation (Decision Log D16: won't auto-restart on deletion)
- **Notes:**
  - Every `bench new-site`/`reinstall`/`restore` call printed: `Warning: MariaDB version ['10.11', '18'] is more than 10.8 which is not yet tested with Frappe Framework.`
  - `bench new-site` output ends at `Updating Dashboard for frappe` / `*** Scheduler is disabled ***` — no "Workspace Sidebars"/"Desktop Icons" steps (see v16 below).

---

## Frappe v16

- **bench:** 5.31.0 (same bench CLI version as v15 — bench itself is independent of the Frappe app version it manages, since it's the same `frappe/bench:latest` image either way)
- **Python:** 3.14.2
- **Node.js:** v24.13.0
- **MariaDB:** 10.11 (reused from `frappe-system` — same instance v15 uses, not a separate one)
- **Redis:** 8 (dedicated `redis-v16` Deployment in the `frappe-v16` namespace — see "Redis setup correction" below)
- **Frappe version:** 16.31.0, branch `version-16`
- **bench new-site flags:** used `--mariadb-user-host-login-scope='%'` from the start (no deprecated-flag detour needed this time — the lesson from v15/D5 was already known)
- **Deployment shape:** built correctly as a Deployment (`bench-v16`, `k3s/bench-v16-deployment.yaml`) from the start, matching the Phase 2 Group K pattern — not a bare Pod
- **Notes:**
  - **No MariaDB version warning at all** — `bench new-site` for v16 printed no `"MariaDB version ... is more than 10.8"` message, unlike every single v15 site operation. Either v16 raised its tested-version threshold, or dropped this specific check.
  - `bench new-site` output includes two extra steps not present in v15: `Creating Workspace Sidebars` and `Creating Desktop Icons`, before `Updating Dashboard for frappe`.
  - `bench init --frappe-branch version-16` succeeded without incident — confirms the `version-16` branch genuinely exists on `frappe/frappe` (not just a hypothetical/future placeholder).

---

## Important correction: the task's stated Redis-compatibility premise was wrong

The setup instructions for this environment stated: *"Redis 6/7 in frappe-system (NOT compatible with v16 — needs Redis 8)."* This is **factually incorrect** — verified directly:
```
$ kubectl exec -n frappe-system redis-cache-master-0 -- redis-server --version
Redis server v=8.10.1 ...
```
The existing `frappe-system` Redis instances have been v8.10.1 since Phase 1 (the Bitnami chart's `latest`-tracking default at install time already resolved to Redis 8). **They were already v16-compatible.**

A dedicated `redis-v16` instance was still built anyway, since the setup's *other* stated reason — namespace isolation, so v16 testing can't accidentally disturb v15's cache/queue state — is valid on its own merits, independent of the (incorrect) version-compatibility claim.

## Redis setup correction: one process per port, not one process on three ports

The originally-specified `k3s/redis-v16.yaml` ran a **single** `redis:8-alpine` container declaring three `containerPort`s (6379/6380/6381) under one Service. This doesn't work: a single `redis-server` process only binds to the one port it's configured with (default 6379) — declaring additional `containerPort` entries in a pod spec is just metadata, it doesn't make the process listen anywhere else. Confirmed directly:
```
$ redis-cli -p 6379 ping   → PONG
$ redis-cli -p 6380 ping   → Could not connect to Redis at 127.0.0.1:6380: Connection refused
$ redis-cli -p 6381 ping   → Could not connect to Redis at 127.0.0.1:6381: Connection refused
```
**Fixed** by running three separate `redis-server` processes as sidecar containers within the same pod (`redis-cache`, `redis-queue`, `redis-socketio`), each with its own `--port` flag — preserving the single-Deployment/single-Service design the task wanted, while actually working. This matches how `frappe-system`'s three Redis instances are set up too (three fully separate processes, one port each), just consolidated into one pod instead of three separate Deployments. All three ports verified responding via the Service DNS name afterward.

---

## Summary: what's actually different between v15 and v16 (this environment)

| Aspect | v15 | v16 |
|---|---|---|
| bench / Python / Node | 5.31.0 / 3.14.2 / v24.13.0 | identical (same image) |
| Frappe version | 15.118.0 | 16.31.0 |
| MariaDB version warning on new-site | Always printed | Never printed |
| new-site extra steps | none | Workspace Sidebars, Desktop Icons |
| MariaDB instance | `frappe-system` (shared) | `frappe-system` (same, shared) |
| Redis instance | `frappe-system` (shared, 3 Bitnami instances) | dedicated `redis-v16` (isolated, 3 sidecar containers) |
| Bench resource type | bare Pod (legacy, Phase 1) | Deployment (correct, from the start) |
