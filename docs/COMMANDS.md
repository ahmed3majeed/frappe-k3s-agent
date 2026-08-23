# Frappe Agent — Verified Command Reference (Docker → Kubernetes)

Complete verification pass of every command the original Docker-based Frappe Agent runs, confirming whether the Kubernetes/k3s equivalent works as-is, needs a modification, or fails outright. Built from `commands-master-list.md` across Tiers A–D and Groups A/B/C of this pass.

**Environment:** k3s v1.36.3+k3s1, pod `bench-v15` (namespace `frappe-v15`), bench dir `/home/frappe/bench-data/frappe-bench/`, site `test.local`, MariaDB at `mariadb.frappe-system.svc.cluster.local`, Redis (cache/queue/socketio) in `frappe-system`.

**Scope note on Parts D–J below:** those commands (Docker container/image ops, supervisorctl, nginx/systemctl, host-metric commands, streaming-backup internals) are Docker/Swarm/host-specific by construction — the master list itself designates them "documented, no test needed." Reproducing 66 near-identical "not tested" blocks would add bulk without adding information, so they're presented as translation tables instead, cross-referenced to the master list's own Groups D–J. Every command that *was* actually run against the live cluster (Parts A–C) uses the full per-command block below, as requested.

Full raw output for every test lives in `RUNBOOK.md`, dated 2026-08-23 (Master Command List: GROUP A/B/C sections). This file is the condensed reference; RUNBOOK.md is the log.

---

## PART A — bench CLI commands (via `kubectl exec`)

---

### bench new-site
**Original Agent uses:** `docker exec {container} bench new-site --no-mariadb-socket --mariadb-user-host-login-scope='%' --db-host {host} --mariadb-root-username {u} --mariadb-root-password {p} --admin-password {ap} {site}`
**K8s equivalent:** `kubectl exec {pod} -- bench new-site ... {site}`
**Status:** ✅ Pass
**Modification:** None for the create itself, but `--no-mariadb-socket` is deprecated in Frappe v15 in favor of `--mariadb-user-host-login-scope='%'`.
**Verified by:** Original `test.local` site creation (Tier A), plus `drop-test.local` created the same way for the drop-site test (Group A supplementary).

---

### install-app --force
**Original Agent uses:** `docker exec {container} bench --site {s} install-app {app} --force`
**K8s equivalent:** `kubectl exec {pod} -- bash -c "cd {bench_dir} && bench --site {s} install-app {app} --force"`
**Status:** ⚡ Modified
**Modification:** On an app already installed, `--force` triggers an interactive Administrator-password reset prompt with no flag to suppress it. Requires `kubectl exec -i` with the password piped twice via stdin (`printf "pass\npass\n" | kubectl exec -i ...`).
**Verified by:** Tier A2 (frappe --force); Group A install-app erpnext (fresh install, no prompt since not previously installed).

---

### install-app (fallback, no --force)
**Original Agent uses:** `docker exec {container} bench --site {s} install-app {app}` (pre-v14 fallback path)
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** `App frappe already installed`, exit 0.

---

### uninstall-app
**Original Agent uses:** `docker exec {container} bench --site {s} uninstall-app {app} --no-backup --yes --force`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None. Note: blocked with `You cannot remove or uninstall the app 'frappe'` when it's the site's only/core app — this is correct guardrail behavior, not a bug.
**Verified by:** Tier B1 (blocked on frappe, by design); Group A supplementary (real removal of erpnext — many tables dropped, `Uninstalled App erpnext from Site test.local`).

---

### migrate (+ --skip-search-index, --skip-failing)
**Original Agent uses:** `docker exec {container} bench --site {s} migrate [--skip-search-index] [--skip-failing]`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Tier A4 (base); Group A backfill (`--skip-search-index` → no reindex message; `--skip-failing` → search index still queued, confirming the flag only affects patch-failure handling).

---

### backup (--with-files --verbose, --backup-path, --compress)
**Original Agent uses:** `docker exec {container} bench --site {s} backup --with-files --verbose`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Tier A6 (`Backup for Site test.local has been successfully completed with files`); reused as source data for restore tests (Group A).

---

### restore (db only)
**Original Agent uses:** `docker exec {container} bench --site {s} restore --mariadb-root-username {u} --mariadb-root-password {p} --admin-password {ap} {db_file}`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** `Site test.local has been restored`, exit 0. Note: relative backup file paths resolve fine via bench's own fallback directory search even when the cwd doesn't match the path prefix.

---

### restore (with public + private files)
**Original Agent uses:** `docker exec {container} bench --site {s} restore --with-public-files {pub} --with-private-files {priv} {db_file}`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None. Real flag names (`--with-public-files`/`--with-private-files`) confirmed via `--help`, matching the master list.
**Verified by:** `Site test.local has been restored with files`, exit 0.

---

### reinstall
**Original Agent uses:** `docker exec {container} bench --site {s} reinstall --yes --mariadb-root-username {u} --mariadb-root-password {p} --admin-password {ap}`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ⚡ Modified
**Modification:** `--yes` only skips the destructive-action confirmation, not the Administrator password setup step — without `--admin-password`, it still hits an interactive prompt and aborts (no stdin). Must supply `--admin-password` explicitly.
**Verified by:** Tier B2. Post-reinstall check confirmed prior test data (`testuser@test.com`) was wiped, proving the site was genuinely rebuilt.

---

### add-system-manager
**Original Agent uses:** `docker exec {container} bench --site {s} add-system-manager {email} --first-name {fn} --last-name {ln} --password {p}`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None. Silent on success — verify independently via `execute frappe.get_roles`.
**Verified by:** Tier B3 — role list for the new user includes `System Manager`.

---

### execute frappe.get_installed_apps
**Original Agent uses:** `docker exec {container} bench --site {s} execute frappe.get_installed_apps`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Tier B9 — `["frappe"]`.

---

### execute frappe.client.get_list --kwargs / frappe.get_roles --args
**Original Agent uses:** N/A in site.py directly — this is the Agent's own general-purpose way of querying site data
**K8s equivalent:** `kubectl exec {pod} -- bash -c "... bench --site {s} execute {method} --kwargs '{json}'"`
**Status:** ✅ Pass
**Modification:** None. Extensively used throughout this entire testing effort (dozens of calls) as the primary verification mechanism for other commands.
**Verified by:** Every Tier A–D verification step that used it, plus one final clean record in Group A.

---

### build-search-index
**Original Agent uses:** `docker exec {container} bench --site {s} build-search-index`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ⚡ Modified
**Modification:** This command only **enqueues** a background RQ job (`build_index_for_all_routes`, queue `long`) — it does not index synchronously. Confirmed via `bench doctor`: 0 workers online, job sitting unprocessed. A real deployment needs a running `bench worker` process for this to actually do anything.
**Verified by:** Tier B11 + B19 (`bench doctor` queue backlog).

---

### rebuild-global-search
**Original Agent uses:** `docker exec {container} bench --site {s} rebuild-global-search`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None — unlike `build-search-index`, this one runs **synchronously to completion** (progress bar to 100%), no worker needed.
**Verified by:** Group A backfill (was falsely marked "already tested" in the source master list; actually run here for the first time).

---

### doctor
**Original Agent uses:** `docker exec {container} bench doctor` (global, no `--site`)
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Tier B19 — surfaced real, useful findings (0 workers online, queued jobs backlog).

---

### bench build (+ --app, --apps)
**Original Agent uses:** N/A directly in site.py (build is a bench-init-time / asset-management operation)
**K8s equivalent:** `kubectl exec {pod} -- bash -c "cd {bench_dir} && bench build [--app {app}] [--apps {a1,a2}]"`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Tier B14 (all assets), B15 (`--app frappe`), Group A supplementary (`--apps frappe,erpnext`, multi-app variant).

---

### bench setup requirements (+ --node, --python)
**Original Agent uses:** N/A directly in site.py
**K8s equivalent:** `kubectl exec {pod} -- bash -c "cd {bench_dir} && bench setup requirements [--node|--python]"`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Tier B16/B17/B18.

---

### clear-cache / clear-website-cache
**Original Agent uses:** `docker exec {container} bench --site {s} clear-cache` / `clear-website-cache`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None. Both silent on success.
**Verified by:** Tier A11 (`clear-cache`); Group A (`clear-website-cache`).

---

### list-apps (+ -f json)
**Original Agent uses:** `docker exec {container} bench --site {s} list-apps [-f json]`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Tier A12 (plain); Group A (`-f json` → `{"test.local": ["frappe"]}`).

---

### set-maintenance-mode on / off
**Original Agent uses:** `docker exec {container} bench --site {s} set-maintenance-mode on|off`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None. Silent on success — verify via `site_config.json`'s `maintenance_mode` key.
**Verified by:** Tier A7/A8.

---

### set-admin-password
**Original Agent uses:** `docker exec {container} bench --site {s} set-admin-password {password}` (plaintext argv — flagged in master list as a pre-existing exposure concern that carries over to `kubectl exec` the same way)
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None functionally, but inherits the plaintext-argv exposure noted in the source analysis — same risk profile under `kubectl exec` as under `docker exec`.
**Verified by:** Tier B7.

---

### scheduler pause / resume / enable
**Original Agent uses:** `docker exec {container} bench --site {s} scheduler pause|resume|enable`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None. All three print clear confirmation messages.
**Verified by:** Tier B4/B5/B6.

---

### update-site-plan
**Original Agent uses:** `docker exec {container} bench --site {s} update-site-plan {plan}`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ❌ Fail
**Modification:** N/A — `Error: No such command 'update-site-plan'.` This command doesn't exist in base Frappe v15's bench CLI. Likely specific to the `press` app (Frappe Cloud's own app) which isn't installed in this environment.
**Verified by:** Group A — direct test, exit code 2.

---

### execute frappe.desk.page.setup_wizard.setup_wizard.setup_complete
**Original Agent uses:** `docker exec {container} bench --site {s} execute frappe.desk.page.setup_wizard.setup_wizard.setup_complete --kwargs {json}`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ⚡ Modified
**Modification:** Empty `{}` kwargs fails (`TypeError: missing 1 required positional argument: 'args'`) — needs a populated `{"args": {language, country, timezone, currency, full_name, email, company_name, company_abbr, domains}}` payload. Also: complex nested JSON with spaces breaks inline `bash -c "..."` shell quoting — use a script file + `kubectl cp` instead.
**Verified by:** Group A — `{"status": "ok"}` after fix.

---

### console (via stdin)
**Original Agent uses:** `docker exec -i {container} bench --site {s} console` (script piped via stdin)
**K8s equivalent:** `echo "<script>" | kubectl exec -i {pod} -- bash -c "cd {bench_dir} && bench --site {s} console"`
**Status:** ✅ Pass
**Modification:** None — works exactly as the master list's suggested format.
**Verified by:** Group A — printed `['frappe']` for a piped `print(frappe.get_installed_apps())`, exited cleanly on stdin EOF.

---

### ready-for-migration
**Original Agent uses:** `docker exec {container} bench --site {s} ready-for-migration` (polled up to 300s)
**K8s equivalent:** same, via `kubectl exec`, polled
**Status:** ✅ Pass
**Modification:** None. Correctly reports `NOT READY for migration: site test.local has pending background jobs` (exit 1) when the job queue has a backlog — ties directly to the `build-search-index`/`doctor` findings (no worker running).
**Verified by:** Group A.

---

### remove-from-installed-apps
**Original Agent uses:** `docker exec {container} bench --site {s} remove-from-installed-apps {app}`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None. Same core-app guardrail as `uninstall-app` — blocks removing `frappe` (`You cannot remove or uninstall the app frappe`), site left fully intact.
**Verified by:** Group A.

---

### execute frappe.utils.get_site_info
**Original Agent uses:** `docker exec {container} bench --site {s} execute frappe.utils.get_site_info`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Group A — full site info JSON returned.

---

### describe-database-table
**Original Agent uses:** `docker exec {container} bench --site {s} describe-database-table --doctype {doctype} [--column {col} ...]`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Group A — full schema JSON for `User`.

---

### add-database-index
**Original Agent uses:** `docker exec {container} bench --site {s} add-database-index --doctype {doctype} --column {col}`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Group A — exit 0 on `User`/`email`.

---

### browse --user
**Original Agent uses:** `docker exec {container} bench --site {s} browse --user {user}` (session-id extraction fallback)
**K8s equivalent:** same, via `kubectl exec`
**Status:** ⚡ Modified
**Modification:** Prints a `Login URL: http://{site}:8000/app?sid={session_id}` line exactly as needed for `sid` extraction — but then also attempts to launch a browser (`xdg-open`), which fails harmlessly in this headless container (no browser binaries present). The Agent should just parse the `sid` from stdout and ignore/suppress the xdg-open errors; doesn't affect exit code (0).
**Verified by:** Group A.

---

### drop-site
**Original Agent uses:** N/A directly in site.py, but a documented bench operation the Agent needs
**K8s equivalent:** `kubectl exec {pod} -- bash -c "cd {bench_dir} && bench drop-site --no-backup --force --root-login {u} --root-password {p} --archived-sites-path archived {site}"`
**Status:** ✅ Pass
**Modification:** None. Tested exclusively on a disposable `drop-test.local` (created via `bench new-site` first) — never on `test.local`.
**Verified by:** Group A — `Dropping site database and user`, `Moving site to archive under sites/archived`; `test.local` confirmed unaffected afterward.

---

### bench restart / bench restart --web
**Original Agent uses:** Docker/supervisor equivalent — `supervisorctl restart {bench}-web:`/`{bench}-workers:` (see Part D–J)
**K8s equivalent:** N/A as a bench command — should map directly to `kubectl rollout restart deployment/{bench}-web` / `-worker` instead (this bench subcommand itself is not the right K8s primitive)
**Status:** ⚡ Modified (no-op in this environment)
**Modification:** Exit 0, but no visible effect — this bare CLI pod has no `config/supervisor.conf` and no `supervisorctl` binary (only an inert `Procfile` from `bench init`, never activated since `bench start` was never run). **Confirms the master list's own conclusion (Group F): don't rely on `bench restart` in K8s at all — manage the K8s Deployment directly instead.**
**Verified by:** Group A.

---

### git apply / git apply --reverse (via "bench git apply")
**Original Agent uses:** presumably `docker exec {container} git apply {patch}` inside the app directory
**K8s equivalent:** `kubectl exec {pod} -- bash -c "cd {app_path} && git apply {patch}"`
**Status:** ❌ Fail (as `bench git apply`) / ✅ Pass (as plain `git apply`)
**Modification:** **`bench git apply` is not a real bench subcommand** (`Error: No such command 'git'.`) — likely a description artifact in the source material. The actual working form is plain `git apply`/`git apply --reverse`, run directly in the app directory (not prefixed with `bench`). See Part B for the verified plain-git version.
**Verified by:** Group A (failure of the `bench`-prefixed form) + Group B (success of the plain form, round-tripped: apply → confirmed change present → reverse → confirmed clean).

---

## PART B — git commands (via `kubectl exec`, inside the bench pod's `apps/frappe`)

All of the following ran successfully with **zero modifications** except where noted. State was: shallow `--depth 1` clone, remote `upstream`, branch `version-15`, clean working tree, single commit `9b8d265` at test start.

---

### git rev-parse HEAD (+ -C variant)
**K8s equivalent:** `kubectl exec {pod} -- bash -c "cd {app_path} && git rev-parse HEAD"` (or `git -C {app_path} rev-parse HEAD` from any cwd)
**Status:** ✅ Pass
**Modification:** None. `-C` variant confirmed to work without a prior `cd`.
**Verified by:** Group B.

---

### git remote get-url / add / remove
**K8s equivalent:** same pattern, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Group B — added `test-remote`, confirmed via `git remote -v`, removed cleanly.

---

### git fetch --depth N {remote} {ref}
**K8s equivalent:** same pattern, via `kubectl exec` (or `git -C {path} fetch ...` with a full URL instead of a named remote — also confirmed working)
**Status:** ⚡ Modified
**Modification:** **Fetching by commit hash requires the full 40-character SHA.** An abbreviated hash (`16d483c`) fails: `fatal: couldn't find remote ref 16d483c`. The full SHA (`16d483c2095d57a080c664dba3e19a0421739719`) works. Fetching by branch name (`--depth 2 upstream version-15`) also works fine regardless. **The real Agent must always resolve/pass the full SHA when fetching by commit, never an abbreviated one.**
**Verified by:** Group B — reproduced the failure, then confirmed the fix.

---

### git diff --name-only {old} {new} (+ pathspec filters, + -C variant)
**K8s equivalent:** same pattern, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None. Both the base form and pathspec-filtered forms (`-- '*.vue' '*.js'`, `-- requirements.txt pyproject.toml`) work correctly, including via `-C`.
**Verified by:** Group B — real diff (`frappe/__init__.py`) between two fetched commits; empty (correct) results for pathspec filters that didn't match.

---

### git reset --hard {hash} (+ -C variant)
**K8s equivalent:** same pattern, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Group B — used current HEAD (safe no-op by design of the test).

---

### git clean -fd (+ -C variant)
**K8s equivalent:** same pattern, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None. Previewed with `-n` first both times (empty — nothing to clean), consistent with the working tree being clean throughout.
**Verified by:** Group B.

---

### git checkout {hash} / git checkout {branch} (+ -C variant)
**K8s equivalent:** same pattern, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None. Checking out a bare commit hash correctly produces a detached HEAD; checking back out to `version-15` afterward correctly reports "up to date with 'upstream/version-15'".
**Verified by:** Group B.

---

### git init / remote add origin / config credential.helper / fetch --depth 1 origin {hash} / checkout -B {branch}
**K8s equivalent:** same 5-command sequence, via `kubectl exec`, in a fresh directory
**Status:** ✅ Pass
**Modification:** None. This is the full "clone at a specific commit without a normal `git clone`" sequence — tested end-to-end in an isolated scratch directory (not the real app checkout) to avoid disturbing live state.
**Verified by:** Group B — resulting branch correctly points at the target commit (`git log --oneline -1` matches, `git branch --show-current` → `version-15`).

---

## PART C — SQL commands (via ephemeral `mysql` client pods)

All queries run via `kubectl run --image=mariadb:10.11 ... -- mysql -h mariadb.frappe-system.svc.cluster.local -u root -p{password} -e "{sql}"`. Note: fast-completing `--rm -i` pods occasionally race the log-attach (benign) — switched to `--restart=Never` (no `--rm`) + `kubectl logs` + manual delete for reliable output capture partway through.

---

### User account lifecycle (CREATE OR REPLACE USER, GRANT, SHOW GRANTS, REVOKE, RENAME, DROP)
**K8s equivalent:** ephemeral SQL pod, as above
**Status:** ✅ Pass
**Modification:** None. Full sequence: create → grant ALL WITH GRANT OPTION → confirm via SHOW GRANTS → revoke → confirm reduced to USAGE → grant SELECT (read-only) → confirm added → rename → confirm new name → drop → confirm gone.
**Verified by:** Group C — every step's before/after state independently confirmed via follow-up `SHOW GRANTS`/`mysql.user` queries.

---

### Database lifecycle (CREATE OR REPLACE DATABASE, GRANT on db, DROP DATABASE/USER IF EXISTS)
**K8s equivalent:** ephemeral SQL pod
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Group C — `test_replace_db` created, confirmed, dropped; associated user confirmed gone.

---

### information_schema.TABLES (table sizes)
**K8s equivalent:** ephemeral SQL pod
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Group C + Tier D3 (real database name discovery: `_9354d31722f40d9e`, not the assumed `test_local`).

---

### information_schema.COLUMNS / STATISTICS (schema + index introspection)
**K8s equivalent:** ephemeral SQL pod
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Group C — real column list and index list for `tabUser`.

---

### information_schema.INDEX_STATISTICS (index usage tracking)
**K8s equivalent:** ephemeral SQL pod
**Status:** ⚡ Caveat
**Modification:** Query is valid but always returns empty on this instance — MariaDB's `userstat` feature (index-usage tracking) is off by default and would need to be enabled server-side (`userstat=ON`) for this to ever return data.
**Verified by:** Group C.

---

### EXPLAIN {query}
**K8s equivalent:** ephemeral SQL pod
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Group C — real query plan for `tabUser` lookup.

---

### ANALYZE TABLE {table} PERSISTENT FOR ALL
**K8s equivalent:** ephemeral SQL pod
**Status:** ✅ Pass
**Modification:** None. Per-column "statistics not collected" warnings for TEXT/BLOB-like columns are informational, not errors.
**Verified by:** Group C — status OK.

---

### mysql.column_stats
**K8s equivalent:** ephemeral SQL pod
**Status:** ✅ Pass
**Modification:** Only returns data after `ANALYZE TABLE ... PERSISTENT FOR ALL` has been run on the target table first (sequence-dependent).
**Verified by:** Group C.

---

### CHECK TABLE / REPAIR TABLE
**K8s equivalent:** ephemeral SQL pod
**Status:** ✅ Pass
**Modification:** None. `CHECK TABLE` → status OK. `REPAIR TABLE` on an InnoDB table correctly returns a note (`"the storage engine ... doesn't support repair"`) rather than erroring — REPAIR is MyISAM-only, and MariaDB handles this gracefully.
**Verified by:** Group C.

---

### SHOW FULL PROCESSLIST / KILL {pid}
**K8s equivalent:** ephemeral SQL pod
**Status:** ✅ Pass
**Modification:** None. Tested safely by creating a disposable `SELECT SLEEP(60)` connection in its own pod first, then killing that specific connection's thread ID from a separate pod — no real/production connection was touched.
**Verified by:** Group C — killed connection's own log shows `ERROR 2013: Lost connection to server during query`, confirming the KILL worked.

---

### SELECT 1 / SHOW DATABASES / FLUSH TABLES
**K8s equivalent:** ephemeral SQL pod
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Group C + Tier D (SHOW DATABASES exercised repeatedly throughout).

---

### CREATE DATABASE IF NOT EXISTS press_meta
**K8s equivalent:** ephemeral SQL pod
**Status:** ✅ Pass
**Modification:** None. Created, confirmed, dropped (not left behind as permanent infra without being asked).
**Verified by:** Group C.

---

### SELECT @@GLOBAL.gtid_binlog_pos
**K8s equivalent:** ephemeral SQL pod
**Status:** ✅ Pass
**Modification:** None — returns empty (no GTID history, since replication was never configured on this instance), which is a valid, non-error result.
**Verified by:** Group C.

---

### SHOW VARIABLES / SELECT @@GLOBAL.{variable}
**K8s equivalent:** ephemeral SQL pod
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** Group C — 655 total variables; `@@GLOBAL.version` → `10.11.18-MariaDB-ubu2204-log`.

---

### SET GLOBAL server_audit_file_rotate_now = 1
**K8s equivalent:** ephemeral SQL pod
**Status:** ❌ Fail
**Modification:** N/A — `ERROR 1193: Unknown system variable 'server_audit_file_rotate_now'`. The `server_audit` plugin isn't loaded on this MariaDB instance. Not a K8s issue; would need the plugin installed/enabled server-side (outside this scope).
**Verified by:** Group C.

---

### performance_schema.events_statements_summary_by_digest
**K8s equivalent:** ephemeral SQL pod
**Status:** ⚡ Caveat
**Modification:** Query is valid but returns 0 rows — `performance_schema` is `OFF` by default on this instance (confirmed via `SHOW VARIABLES`). Enabling it requires a server restart with a config change; out of scope for this pass, but the query itself works fine once enabled.
**Verified by:** Group C.

---

### information_schema.INNODB_TRX / INNODB_LOCKS (locks report)
**K8s equivalent:** ephemeral SQL pod
**Status:** ⚡ Modified
**Modification:** **`INNODB_LOCKS` doesn't exist in MariaDB** — it's a MySQL-only table. MariaDB's equivalent is `information_schema.INNODB_LOCK_WAITS`. Used that instead. `INNODB_TRX` itself works fine on both.
**Verified by:** Group C — both empty (no active transactions/lock waits at test time), valid results.

---

### PURGE BINARY LOGS TO '{binlog}'
**K8s equivalent:** ephemeral SQL pod
**Status:** ✅ Pass
**Modification:** None — even with `log_bin` `OFF` on this instance, MariaDB treats this as a safe no-op rather than erroring.
**Verified by:** Group C.

---

### Replication commands (STOP/START SLAVE, CHANGE MASTER TO, SHOW SLAVE STATUS)
**K8s equivalent:** ephemeral SQL pod, against a dedicated replica instance
**Status:** ⏭️ Skipped
**Modification:** N/A — needs a second, dedicated replica MariaDB instance to test meaningfully. Not built for this pass (matches the master list's own Group J designation).
**Verified by:** N/A.

---

## PART D–J — Docker/System → Kubernetes translations (documented only, not executed)

These are Docker/Swarm/supervisor/nginx/host-metric commands the original Agent runs that have **no meaningful equivalent to test on a live k3s cluster** — they're either not applicable at all in K8s (`docker commit`, `supervisorctl reread`), or their K8s equivalent is a completely different primitive (a Deployment manifest instead of `docker run`) that doesn't correspond to "running the same command differently." Tables below are carried over from `commands-master-list.md`'s own Groups D–J, which already documents them accurately.

### Group D — Docker container operations → kubectl
| Original Command | K8s Equivalent |
|---|---|
| `docker exec -w {dir} {container} {cmd}` | `kubectl exec -n {ns} {pod} -- bash -c "cd {dir} && {cmd}"` |
| `docker service ps -f desired-state=Running {service}` | `kubectl get pods -n {ns} -l app={bench} -o jsonpath=...` |
| `docker run -d --init -u frappe ... --name {name} {image}` | `kubectl apply -f deployment.yaml` |
| `docker stack deploy --compose-file docker-compose.yml {name}` | `kubectl apply -f manifests/` |
| `docker stop {name}` | `kubectl scale deployment/{bench} --replicas=0` |
| `docker rm {name} --force` | `kubectl delete deployment/{bench}` |
| `docker start {name}` | `kubectl scale deployment/{bench} --replicas=1` |
| `docker stack rm {name}` | `kubectl delete namespace {ns}` |
| `docker update --memory ... --cpus ... {name}` | `kubectl patch deployment/{bench} -p '{resources...}'` |
| `docker ps -aqf "name={name}"` | `kubectl get pods -n {ns} -l app={bench} -o name` |
| `docker commit {container} {image}` | Rebuild image via CI/Kaniko (no direct equivalent) |
| `docker top {name} \| grep gunicorn` | `kubectl exec {pod} -- ps aux \| grep gunicorn` |
| `docker ps -a \| grep {bench}` | `kubectl get pods -n {ns} -l bench={name}` |
| `docker ps --format '{{.Names}}'` | `kubectl get pods -A -l role=bench -o name` |

**Note (from this pass's own findings, Part A):** `frappe-system`'s Redis/MariaDB workloads are actually **StatefulSets**, not Deployments (Bitnami chart default) — any real translation script must resolve the correct resource kind and name (`statefulset/{name}-master`, not `deployment/{name}`) before applying the table above.

### Group E — Docker image operations → K8s
| Original Command | K8s Equivalent |
|---|---|
| `docker login -u {u} -p {p} {url}` | `kubectl create secret docker-registry regcred ...` |
| `docker pull {image}` | Handled by kubelet automatically |
| `docker push {image}` | CI pipeline / Kaniko Job |
| `docker rmi {image} --force` | Kubelet image GC (automatic) |
| `docker manifest inspect {tag}` | `crane manifest {tag}` or registry API call |
| `docker image ls --format ...` | `kubectl get nodes -o ...` + `crictl images` |
| `docker system prune -af` | Kubelet GC (`--image-gc-high-threshold`) |
| `docker system df -v` | Prometheus node-exporter metrics |
| `docker buildx build --platform {p} ...` | Kaniko Job / BuildKit Pod |
| `docker run --rm --net none -v ... cp -LR config/` | initContainer with emptyDir volume |
| `docker run -d --name {c} {image} tail -f /dev/null` | `kubectl run {name} --image={image} -- sleep infinity` |
| `docker exec {c} bash -c {cmd}` | `kubectl exec {pod} -- bash -c {cmd}` |
| `docker commit --change='CMD...' {c} {image}` | Rebuild from Dockerfile (no equivalent) |
| `docker rm -f {container}` | `kubectl delete pod {pod}` |

### Group F — supervisorctl → K8s
| Original Command | K8s Equivalent |
|---|---|
| `supervisorctl reread` / `update` | N/A — K8s manages processes |
| `supervisorctl start frappe-bench-web:` | `kubectl scale deployment/{bench}-web --replicas=1` |
| `supervisorctl stop frappe-bench-web:` | `kubectl scale deployment/{bench}-web --replicas=0` |
| `supervisorctl restart frappe-bench-workers:` | `kubectl rollout restart deployment/{bench}-worker` |
| `supervisorctl start/stop code-server:` | `kubectl apply -f` / `kubectl delete deployment/code-server` |
| `supervisorctl {cmd} {target}` | `kubectl rollout restart / scale deployment/{target}` |
| `sudo supervisorctl restart agent:redis` | `kubectl rollout restart deployment/redis` (or `statefulset/`, see note above) |
| `sudo supervisorctl restart agent:web` | `kubectl rollout restart deployment/agent-web` |
| `sudo supervisorctl stop/start agent:worker-{i}` | `kubectl scale deployment/agent-worker --replicas={n}` |

**Confirmed by this pass (Part A):** `bench restart`/`bench restart --web` are effectively no-ops without a running supervisor process — this table's approach (managing the K8s Deployment directly) is the only real mechanism.

### Group G — NGINX/systemctl → Traefik
| Original Command | K8s Equivalent |
|---|---|
| `sudo systemctl reload nginx` | Automatic — Traefik watches IngressRoute changes |
| `sudo systemctl status nginx` | `kubectl get pods -n kube-system -l app=traefik` |
| `sudo nginx -t` | Traefik validates config automatically |
| Write to `nginx_directory/hosts/{site}.conf` | `kubectl apply -f ingressroute.yaml` |
| Write to `nginx_directory/upstreams/{bench}.conf` | `kubectl apply -f service.yaml` |
| `NginxReloadManager.request_reload()` | Automatic — Traefik reconciles on IngressRoute change |

**Related finding from this pass (Tier C):** a test Ingress creates fine even referencing a nonexistent backend Service — K8s doesn't validate that at admission time, so "created successfully" ≠ "actually routing traffic."

### Group H — System/host commands → K8s
| Original Command | K8s Equivalent |
|---|---|
| `free -t -m` | Metrics Server / Prometheus node-exporter |
| `cat /proc/stat` (CPU stats) | cAdvisor / Prometheus |
| `ps --pid 2 --ppid 2 --deselect u` | `kubectl top pods` |
| `df -B1 {path}` | PVC capacity metrics |
| `du -sB1`/`du -sh`/`ncdu {path}` | Job Pod with PVC mounted |
| `mv {bench_dir} {archived_dir}` | PVC snapshot / rename |
| `git reset/clean/fetch/checkout` (agent self-update) | `kubectl set image deployment/agent ...` |
| `pip install -e repo` (agent self-update) | Rebuild agent image + rollout |

### Group I — Streaming backup operations → K8s (complex, deferred)
| Original Command | K8s Equivalent |
|---|---|
| `make -C {LIB_DIR} OUT={path}` (bypass_unlink.so) | Pre-build in bench image |
| `bash -c 'exec 3> {fifo}...'` (streaming shim) | Sidecar container pattern |
| `pkill -f {timestamp}` (kill orphaned backup) | `kubectl exec {pod} -- pkill -f {ts}` |
| `mkdir -p {backup_dir}` / `mkfifo {file}` (in container) | emptyDir volume, shared between containers |
| `rclone rcat/deletefile/lsjson ...` | Sidecar with rclone + emptyDir, or agent-side S3 API calls |
| `{mysqldump} \| gzip` / `gunzip \| mysql` (table restore) | Job Pod with DB access |

**All of Group I requires a fundamentally different design in K8s** (agent and bench container aren't guaranteed to share a filesystem or node) — this isn't a 1:1 command swap, it's an architecture change (sidecar + shared volume, or skip the local-FIFO relay entirely and upload from inside the bench pod).

---

## Summary

| Part | Tested | ✅ Pass | ⚡ Modified/Caveat | ❌ Fail | ⏭️ Skipped/Deferred |
|---|---|---|---|---|---|
| A — bench CLI | 33 | 24 | 7 | 2 | 0 |
| B — git (in-pod) | 21 | 20 | 1 | 0 | 0 |
| C — SQL | 32 | 27 | 4 | 1 | 4 (replication) |
| D–J — Docker/system translations | 0 (documented only) | — | — | — | — |
| **Total tested** | **86** | **71** | **12** | **3** | **4** |

Full raw command output for everything above: `RUNBOOK.md`, dated 2026-08-22/23, sections "Tier A/B/C/D" and "Master Command List: GROUP A/B/C".

---

## Phase 2: K8s Bench Lifecycle

Full end-to-end verification of the K8s-native operations that replace what the original Docker-based Agent did with `docker run`/`docker stop`/`docker rm`/nginx-reload/`git pull`+`supervisorctl`. Built and torn down a complete bench (`bench-test`, namespace `frappe-test`, site `k8s-test.local`) as proper Deployment+Service+IngressRoute resources — not a bare Pod like the Phase 1 `bench-v15` setup — since that's what a real bench actually needs in production. All manifests saved to `k3s/`. `frappe-v15`/`bench-v15` were never touched.

---

### GROUP K — Full bench lifecycle (Namespace → PVC → Deployment → Service → IngressRoute → bench init → site)

---

### K1–K2: Namespace + PVC
**Original Agent uses:** `docker run -d --name {bench} {image} ...` (implicit: Docker creates its own storage/network on first run)
**K8s equivalent:** `kubectl create namespace {ns}`; `kubectl apply -f k3s/bench-pvc.yaml`
**Status:** ✅ Pass
**Modification:** None. PVC shows `Pending` until a pod claims it (`local-path` storage class uses `WaitForFirstConsumer` binding) — expected, not an error.
**Verified by:** `kubectl get pvc` → `Bound` once the Deployment (K3) picked it up.

---

### K3: Deployment
**Original Agent uses:** `docker run -d --init -u frappe ... --name {name} {image}`
**K8s equivalent:** `kubectl apply -f k3s/bench-deployment.yaml`
**Status:** ✅ Pass
**Modification:** None. PVC mounted directly at `/home/frappe/bench-data` (one level above where `bench init` creates `frappe-bench`) — correct from the start, avoiding the mount-path issue discovered the hard way in Phase 1's bare-Pod setup.
**Verified by:** `kubectl wait --for=condition=Available` succeeded; pod `Running`.

---

### K4: Service
**Original Agent uses:** N/A (Docker's own bridge network + published ports)
**K8s equivalent:** `kubectl apply -f k3s/bench-service.yaml`
**Status:** ✅ Pass
**Modification:** None. Exposes both 8000 (web) and 9000 (socketio).
**Verified by:** `kubectl get svc` → ClusterIP with both ports listed.

---

### K5: IngressRoute
**Original Agent uses:** write to `nginx_directory/hosts/{site}.conf` + `nginx -s reload`
**K8s equivalent:** `kubectl apply -f k3s/bench-ingressroute.yaml` (Traefik CRD, `apiVersion: traefik.io/v1alpha1`)
**Status:** ✅ Pass
**Modification:** None. Pre-verified the CRD/apiVersion actually exists in this cluster before writing the manifest (`kubectl api-resources | grep traefik`) — confirmed `traefik.io/v1alpha1` for both `IngressRoute` and `Middleware`.
**Verified by:** `kubectl describe ingressroute` — correctly wired to the real `bench-test` Service (unlike a dangling test Ingress from Phase 1 Tier C7, which pointed at a nonexistent backend).

---

### K6: bench init
**Original Agent uses:** implicit at image-build time in Docker (bench pre-baked into the image)
**K8s equivalent:** `kubectl exec {pod} -- bash -c "cd {bench_dir} && bench init frappe-bench --frappe-branch version-15 --skip-redis-config-generation"`
**Status:** ✅ Pass
**Modification:** None needed this time — both fixes discovered in Phase 1 (correct PVC mount depth, `--skip-redis-config-generation` flag) were designed in from the start.
**Verified by:** `SUCCESS: Bench frappe-bench initialized`.

---

### K7: Configure infrastructure hosts
**Original Agent uses:** writes directly into `common_site_config.json` inside the bind-mounted bench directory
**K8s equivalent:** `bench set-mariadb-host` / `set-redis-cache-host` / `set-redis-queue-host` / `set-redis-socketio-host`, via `kubectl exec`
**Status:** ✅ Pass
**Modification:** None — used the `redis://` URL scheme from the start (learned from Phase 1 Tier A, where the bare `host:port` format failed `bench new-site`).
**Verified by:** `cat sites/common_site_config.json` — all four hosts correct.

---

### K8–K9: Create site + verify
**Original Agent uses:** `docker exec {container} bench new-site ...`
**K8s equivalent:** `kubectl exec {pod} -- bash -c "cd {bench_dir} && bench new-site k8s-test.local ..."`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** `bench --site k8s-test.local list-apps` → `frappe 15.118.0 version-15`.

---

## GROUP L — Bench restart and scaling

---

### L1: Rolling restart
**Original Agent uses:** `supervisorctl restart frappe-bench-workers:` (or similar target)
**K8s equivalent:** `kubectl rollout restart deployment/{bench}`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** New pod name confirmed (`...-696bf5f95f-zhtp6` replacing `...-69f6bdfc87-fpvf4`).

---

### L2: Scale down
**Original Agent uses:** `docker stop {name}`
**K8s equivalent:** `kubectl scale deployment/{bench} --replicas=0`
**Status:** ✅ Pass
**Modification:** None. Pods briefly show `Terminating` past a quick check — grace-period timing, not a stuck state.
**Verified by:** `kubectl get pods` → `No resources found` shortly after.

---

### L3: Scale up (+ data persistence)
**Original Agent uses:** `docker start {name}`
**K8s equivalent:** `kubectl scale deployment/{bench} --replicas=1`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** New pod `Running`; `bench --site k8s-test.local list-apps` still returns correctly — bench data survived the scale-to-0/scale-to-1 cycle via the PVC.

---

### L4: Patch resource limits
**Original Agent uses:** `docker update --memory ... --cpus ... {name}`
**K8s equivalent:** `kubectl patch deployment/{bench} -p '{resources...}'`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** `kubectl describe pod | grep -A4 Limits` → exact requested values (`cpu: 500m, memory: 1Gi` limits; `cpu: 250m, memory: 512Mi` requests).

---

## GROUP M — Domain and routing management

---

### M1–M2: Add domain(s)
**Original Agent uses:** write to `nginx_directory/hosts/{site}.conf`
**K8s equivalent:** `kubectl apply -f` an `IngressRoute` manifest
**Status:** ✅ Pass
**Modification:** None functionally. Note: M1 used the same host as the existing K5 IngressRoute — Traefik doesn't reject duplicate host matches at admission time (each IngressRoute becomes its own router); removed at M3 before it could cause routing ambiguity. M2 used a genuinely distinct host (`custom-domain.local`) and worked cleanly.
**Verified by:** `kubectl get ingressroute` listing both new resources.

---

### M3: Remove domain
**Original Agent uses:** delete the site's nginx conf file + reload
**K8s equivalent:** `kubectl delete ingressroute {name}`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** `kubectl get ingressroute` — target gone, others untouched.

---

### M4: Maintenance mode middleware
**Original Agent uses:** nginx-level redirect config
**K8s equivalent:** `kubectl apply -f` a Traefik `Middleware` manifest (`redirectRegex`)
**Status:** ✅ Pass
**Modification:** None. (Resource creation only was in scope — actually attaching it to a route via the `router.middlewares` annotation was already exercised in Phase 1 Tier C9.)
**Verified by:** `kubectl describe middleware` — spec matches exactly.

---

## GROUP N — Bench archive and cleanup

---

### N1: Archive (keep data, remove compute/routing)
**Original Agent uses:** `docker rm {name} --force` (bind-mounted data survives on the host)
**K8s equivalent:** `kubectl scale --replicas=0` + `kubectl delete deployment/service/ingressroute` (PVC left alone)
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** `kubectl get pvc` → still `Bound`, 10Gi, after Deployment/Service/IngressRoutes all deleted.

---

### N2: Restore from archived PVC
**Original Agent uses:** N/A — Docker bind mounts don't have an equivalent "archive" concept; this is a K8s-native capability
**K8s equivalent:** `kubectl apply -f k3s/bench-deployment.yaml` (same PVC claim name)
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** New pod's `sites/` directory contains the full original site (`k8s-test.local`, `apps.json`, `apps.txt`, `assets`, `common_site_config.json`); `bench --site k8s-test.local list-apps` still returns `frappe 15.118.0 version-15` — zero data loss across the archive/restore cycle.

---

### N3: Full cleanup
**Original Agent uses:** `docker stack rm {name}`
**K8s equivalent:** `kubectl delete namespace {ns}`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** `kubectl get namespace frappe-test` → `NotFound`. Confirmed `frappe-v15`/`bench-v15` (the protected test bench) untouched throughout.

---

## GROUP O — Agent self-update concept

---

### O1: Image update + rollout
**Original Agent uses:** `git reset --hard && git fetch && git merge && supervisorctl restart agent:*`
**K8s equivalent:** `kubectl set image deployment/{agent} {container}={new-image}:{tag}` + rollout wait
**Status:** ✅ Pass
**Modification:** None. First run (as literally specified) hit the documented fallback branch, since `bench-test`/`frappe-test` had already been deleted in Group N. To get real evidence rather than just the fallback message, additionally demonstrated the live mechanism on a disposable `demo-agent` deployment.
**Verified by:** Image confirmed changed (`busybox:1.36` → `busybox:1.35`), `kubectl rollout status` → `successfully rolled out`. **Conclusion: Agent self-update in K8s is purely an image update + rollout — no `git pull`, no `supervisorctl restart`. The new code ships as a pre-built image; the rollout mechanism K8s already provides handles the swap.**

---

## Phase 2 Summary

| Group | Steps | ✅ Pass | ⚡ Modified | ❌ Fail |
|---|---|---|---|---|
| K — Full bench lifecycle | 9 | 9 | 0 | 0 |
| L — Restart/scaling | 4 | 4 | 0 | 0 |
| M — Domain/routing | 4 | 4 | 0 | 0 |
| N — Archive/cleanup | 3 | 3 | 0 | 0 |
| O — Self-update concept | 1 | 1 | 0 | 0 |
| **Total** | **21** | **21** | **0** | **0** |

**21/21 clean — every operation worked as designed with zero modifications needed.** This is a direct consequence of Phase 1's findings: every hard-won lesson (PVC mount depth, `--skip-redis-config-generation`, `redis://` scheme, real Traefik CRD versions) was already known and built correctly into these manifests from the start, rather than discovered through trial and error here. The `k3s/` manifests in this repo are the verified templates the real Custom Agent can build on directly.

Manifests: `k3s/bench-pvc.yaml`, `k3s/bench-deployment.yaml`, `k3s/bench-service.yaml`, `k3s/bench-ingressroute.yaml`, `k3s/ingressroute-custom-domain.yaml`, `k3s/middleware-maintenance.yaml`.

Full raw output for every Phase 2 test: `RUNBOOK.md`, dated 2026-08-23, "Phase 2, GROUP K/L/M/N/O" sections.

---

## ⚠️ Known Gotchas

### Traefik duplicate Host() — no error on conflict
**Finding:** Traefik does not reject duplicate `Host()` matches across two different `IngressRoute` resources. Creating a second `IngressRoute` for a host that's already routed by another `IngressRoute` succeeds silently — both are accepted as separate routers, with no validation error and no admission-time warning.

**Where this showed up:** Phase 2, Group M1 — created `k8s-test-domain` with `Host(`k8s-test.local`)`, the same host already routed by the `bench-test` IngressRoute from Group K5. Both existed simultaneously until `k8s-test-domain` was deliberately removed at M3.

**Why it matters for the Custom Agent:** if a bench/domain-management code path ever creates an `IngressRoute` without first checking whether that host is already routed elsewhere, you get two competing routers pointed at (potentially different) backends — a real bug with no error to catch it.

**Implementation rule:**
- Prefer `kubectl apply` (upsert by resource name) over `kubectl create`, so re-running the same domain-add operation updates the existing route instead of creating a duplicate.
- For a genuinely new domain, check existing `IngressRoute`s' `Host()` matches first (`kubectl get ingressroute -A -o yaml` / a label-based lookup) before creating a new one, so the Agent can reject or warn on a real conflict instead of silently doubling up.

See `RUNBOOK.md`, Decision Log **D12**, for the full record.

---

## GROUP D — Uncertain Commands (pip editable installs, run-patch, performance_schema)

---

### pip install -e {app_path}
**Original Agent uses:** `docker exec {container} {venv}/bin/pip install -e {app_path}` (app dependency reinstall)
**K8s equivalent:** `kubectl exec {pod} -- bash -c "{venv}/bin/pip install -e {app_path}"`
**Status:** ✅ Pass
**Modification:** None.
**Verified by:** `pip list --editable` and `pip show -f frappe | grep Editable` both confirm `Editable project location: .../apps/frappe` — genuinely editable, not just re-copied.

---

### python -m pip install -e {app_path}
**Original Agent uses:** same operation, alternate invocation form used in some code paths
**K8s equivalent:** `kubectl exec {pod} -- bash -c "{venv}/bin/python -m pip install -e {app_path}"`
**Status:** ✅ Pass
**Modification:** None — identical outcome to the plain `pip install -e` form.
**Verified by:** Same editable-install checks as above.

---

### bench run-patch
**Original Agent uses:** `docker exec {container} bench --site {s} run-patch {patch_module_path}`
**K8s equivalent:** same, via `kubectl exec`
**Status:** ⚡ Modified
**Modification:** The example patch name given (`frappe.patches.v14_0.update_workspace2_for_rename`) doesn't exist — `ModuleNotFoundError`. The real module (confirmed via `find` in the patches directory) is `frappe.patches.v14_0.update_workspace2`, no `_for_rename` suffix.
**Verified by:** `Executing frappe.patches.v14_0.update_workspace2 in test.local (...) — Success: Done in 0.587s`.

---

### performance_schema queries (slow query analysis)
**Original Agent uses:** `mysql -h {host} -e "SELECT ... FROM performance_schema.events_statements_summary_by_digest ..."`, run on the agent host
**K8s equivalent:** ephemeral SQL pod, same query
**Status:** ⚡ Needs config change
**Modification:** `performance_schema` is `OFF`/`0` by default on this MariaDB instance (`SELECT @@performance_schema;` → `0`) — confirmed identically in Phase 1 Group C. The query itself is valid and doesn't error while disabled, it just returns 0 rows. Enabling requires `[mysqld] performance_schema=ON` in server config plus a restart — a server-level change, not something the Agent can toggle per-query.
**Verified by:** `SELECT @@performance_schema;` → `0`; digest query mechanics already confirmed working in Phase 1 Group C.

---

### GROUP D Summary

| Result | Count |
|---|---|
| ✅ Pass | 2 |
| ⚡ Modified/needs config | 2 |
| ❌ Fail | 0 |
| **Total** | **4** |
