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

---

## Tier A Command Comparison: v15 vs v16

All commands tested identically to Phase 1 Tier A, against `v16-test.local` (bench-v16, frappe-v16 namespace).

| Command | v15 | v16 | Difference |
|---|---|---|---|
| new-site | ✅ | ⚡ | 2 new steps: "Creating Workspace Sidebars", "Creating Desktop Icons"; no MariaDB deprecation warning (D26) |
| install-app --force | ⚡ needs `kubectl exec -i` + piped password (D7) | ⚡ | Worked **without** `-i` at all (pipe is self-contained inside the exec'd `bash -c`) — only one `Set Administrator password:` prompt appeared, not v15's two ("Set" + "Re-enter"). Unclear if this is a genuine UX simplification in v16 or a technique artifact of the internal-pipe approach; not re-verified with the external-`-i` technique to isolate which |
| migrate | ✅ | ⚡ | New steps not present in v15: `Removing orphan Notifications/Workspace Sidebars/Desktop Icons`, `Deleting icon Frappe Framework`, `Syncing portal menu...`, `Updating installed applications...` — see D27 |
| migrate --skip-failing | ✅ | ✅ | Same flag semantics, same new v16 steps as plain migrate |
| migrate --skip-search-index | ✅ | ✅ | Same flag semantics (correctly omits the reindex-queue message), same new v16 steps |
| backup --with-files --verbose | ✅ | ⚡ | Backup Summary lists **absolute** paths (`/home/frappe/bench-data/...`); v15 used **relative** paths (`./test.local/...`) — see D28 |
| clear-cache | ✅ | ✅ | Identical (silent success) |
| clear-website-cache | ✅ | ✅ | Identical (silent success) |
| list-apps | ✅ | ✅ | Identical format |
| list-apps -f json | ✅ | ✅ | Identical format |
| set-maintenance-mode on/off | ✅ | ✅ | Identical |
| scheduler pause/resume/enable | ✅ | ✅ | Identical confirmation messages |
| set-admin-password | ✅ | ✅ | Identical (silent success) |
| add-user | ✅ | ✅ | Identical (silent success, verified via execute) |
| add-system-manager | ✅ | ✅ | Identical (silent success) |
| build --app frappe | ✅ | ✅ | Same output shape, same ~15-18s build time |
| setup requirements | ✅ | ✅ | Identical |
| doctor | ✅ | ⚡ | New queued job type appears: `frappe.model.delete_doc.delete_dynamic_links` — a side effect of migrate's new orphan-cleanup steps (D27), not an independent behavior change. Core finding (0 workers online) unchanged |
| restore | ✅ | ✅ | Identical fallback path resolution and success behavior |
| drop-site | ✅ | ⚡ | Archived sites move to a **top-level** `frappe-bench/archived/sites/` directory in v16, vs v15's `frappe-bench/sites/archived/` (nested inside `sites/`) — see D29 |

**16/20 identical to v15, 5/20 show a real behavioral or structural difference** (new-site, install-app technique note, migrate, backup, doctor's queue contents as a migrate side-effect, and drop-site's archive location — counted as 5 distinct differences since doctor's change isn't independent of migrate's).

---

## Tier B + C Command Comparison: v15 vs v16

| Command | v15 result | v16 result | Difference |
|---|---|---|---|
| uninstall-app (2 apps) | ✅ | ✅ | Same outcome; v16 shows extra "Deleting Desktop Icons"/"Deleting Workspace Sidebars" steps (same D27 theme) |
| reinstall | ✅ | ✅ | Identical; same new lifecycle steps as A1/D26 |
| execute get_installed_apps | ✅ | ✅ | Identical |
| execute get_roles | ✅ | ✅ | Identical format (role *data* differs slightly — v16 has a "Marketing Manager" role v15 doesn't — but that's expected version drift, not a command behavior change) |
| build-search-index | ⚡ enqueue-only (D9) | ✅ | Same — still only enqueues, confirmed via `doctor` |
| rebuild-global-search | ✅ synchronous | ✅ | Same — still runs synchronously to 100% |
| build (full) | ✅ | ✅ | Same output shape, ~18-19s build time |
| setup requirements --python | ✅ | ✅ | Identical |
| setup requirements --node | ✅ | ✅ | Identical |
| ready-for-migration | ✅ | ✅ | Identical message and exit code |
| remove-from-installed-apps | ✅ guardrail | ✅ | Identical guardrail behavior |
| describe-database-table | ✅ | ✅ | Identical schema JSON shape |
| add-database-index | ✅ | ✅ | Identical |
| console (stdin) | ✅ | ✅ | Identical |
| run-patch | ✅ verbose ("Executing... Success: Done in Xs") | ⚡ | **Completely silent on success** — exit 0, zero output, even with `2>&1` captured. See D30 |
| pip install -e | ✅ | ✅ | Identical |
| Rolling restart (kubectl) | ✅ | ✅ | Identical — new pod name, site data intact |
| Scale down/up | ✅ | ✅ | Identical |
| Patch resource limits | ✅ | ✅ | Identical, values applied correctly |
| Add IngressRoute | ⚡ backend Service missing (D11) | ✅ | Same pattern — no `bench-v16` Service exists either, so IngressRoute creates fine but Traefik logs `kubernetes service not found`. Also confirms double-quote `Host("...")` syntax (used in this task, vs backtick syntax used in Phase 2) parses without error in this Traefik version |
| Remove IngressRoute | ✅ | ✅ | Identical |

**28/29 identical to v15, 1/29 shows a real behavioral difference** (run-patch verbosity).

---

## Frappe v14

- **bench:** 5.31.0 (same image as all versions)
- **Python:** required 3.11 specifically (`--python /usr/bin/python3.11`) — the image's default 3.14 fails (`pypika` depends on the removed `ast.Str` API). Also required `python3.11-dev` installed for `hiredis`'s native compilation. See D32.
- **Node.js:** v24.13.0 (image default works fine for v14 — only Python needed downgrading)
- **MariaDB:** 10.11 (shared `frappe-system` instance)
- **Redis:** 8 (dedicated `redis-v14`, 3-container pattern per D24)
- **Frappe version:** 14.101.1 — `list-apps` showed no version/branch immediately after `new-site`, but did show it correctly after the first `migrate` ran (D34, corrected — this is a site-lifecycle state, not a fixed v14 limitation)
- **bench new-site flags:** `--mariadb-user-host-login-scope` **does not exist** in v14 — must use `--no-mariadb-socket` (D33)
- **Notes:**
  - `bench init` needs the D32 workaround (Python 3.11 + dev headers) — otherwise fails outright
  - `new-site` shows two new steps not in v15/v16: `Restoring Database file...`, `Updating country info`
  - Still shows the MariaDB version deprecation warning (like v15, unlike v16)
  - `list-apps` showed bare app name only *before the first migrate* — resolved after migrate ran (D34, corrected)
  - `backup` uses `mysqldump` (not `mariadb-dump`) with an older shell-wrapping pattern, but still relative paths like v15 (D35)
  - `setup requirements` includes an `npm`/`snyk-protect` step not seen in v15/v16's plain `yarn`

## Frappe v13

- **Status: ❌ Incompatible with `frappe/bench:latest` as currently configured.**
- Python-side issues resolvable with the same D32 workaround (3.11 + dev headers)
- **Node-side: not resolvable.** `node-sass`'s native C++ addon fails to compile against Node v24.13.0's ABI — a hard compatibility wall (node-sass was deprecated industry-wide for exactly this reason). v13 officially requires Node 14; bridging that gap would need a dedicated older-Node base image, out of scope for this pass. See D36.
- No Tier A testing performed — setup never completed.
- **Practical floor for this project's current tooling: Frappe v14.** v13 and earlier are unsupported without a fundamentally different (older-Node) image.

---

## Full Command Comparison: v13 – v16

| Command | v13 | v14 | v15 | v16 | Notes |
|---|---|---|---|---|---|
| bench init | ❌ (node-sass/Node ABI, D36) | ⚡ (needs Python 3.11 + dev headers, D32) | ✅ | ✅ | v13 unsupported on this image; v14 needs a workaround |
| new-site | — (setup failed) | ⚡ (`--no-mariadb-socket` required, no login-scope flag exists, D33) | ✅ | ⚡ (2 new steps, no MariaDB warning, D26) | Socket flag is a hard version boundary, not just a deprecation |
| migrate | — | ✅ | ✅ | ⚡ (new cleanup steps, D27) | |
| migrate --skip-failing | — | ✅ | ✅ | ✅ | |
| migrate --skip-search-index | — | ✅ | ✅ | ✅ | |
| backup --with-files --verbose | — | ⚡ (`mysqldump`, older shell pattern, relative paths, D35) | ✅ | ⚡ (absolute paths, D28) | Binary name AND path format both vary by version |
| clear-cache | — | ✅ | ✅ | ✅ | |
| clear-website-cache | — | ✅ | ✅ | ✅ | |
| list-apps | — | ✅ (shows full info after first migrate, D34 corrected) | ✅ | ✅ | Pre-migrate state shows bare name on any version, not v14-specific |
| list-apps -f json | — | ✅ (same correction) | ✅ | ✅ | |
| set-maintenance-mode on/off | — | ✅ | ✅ | ✅ | |
| scheduler pause/resume/enable | — | ✅ | ✅ | ✅ | |
| set-admin-password | — | ✅ | ✅ | ✅ | |
| add-user | — | ✅ | ✅ | ✅ | |
| build-search-index | — | ✅ (enqueue-only, D9) | ✅ | ✅ | Consistent across all working versions |
| rebuild-global-search | — | ✅ (synchronous) | ✅ | ✅ | Consistent across all working versions |
| doctor | — | ⚡ (extra `update_gravatar` job, minor) | ✅ | ⚡ (extra `delete_dynamic_links` job, D27 side-effect) | Both diffs are side effects of other version-specific behavior, not doctor itself changing |
| build --app frappe | — | ✅ (~10.7s) | ✅ | ✅ (~15-18s) | |
| setup requirements | — | ⚡ (npm/snyk-protect step) | ✅ | ✅ | |
| run-patch | — | not tested | ✅ (verbose) | ⚡ (silent, D30) | |
| drop-site | — | not tested | ✅ | ⚡ (different archive path, D29) | |

**Legend:** ✅ works identically to the v15 baseline · ⚡ works but differs (see linked Decision Log entry) · ❌ fails · — not reached (setup incomplete)
