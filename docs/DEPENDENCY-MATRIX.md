# Frappe Dependency Matrix

## Verified versions from actual test environments

All "Verified" figures below were read directly from the running `bench-v14`, `bench-v15`, and `bench-v16` pods (and the shared `mariadb-0` / `redis-*` pods in `frappe-system`) on 2026-08-23, via `kubectl exec`. "Official minimum" figures are cross-referenced from Frappe's `pyproject.toml` (per-branch `requires-python`), `package.json` `engines.node`, and the official installation docs (docs.frappe.io). Where the two disagree, both are shown — see Notes.

---

## Support Status

| Version | Status | Notes |
|---------|--------|-------|
| v13 | ❌ Not supported | `node-sass` incompatible with Node 24+ (D36) |
| v14 | ✅ Supported | Requires Python 3.11 workaround (D32) |
| v15 | ✅ Supported | Full support |
| v16 | ✅ Supported | Full support, latest |

---

## v14 Dependencies

### Verified working configuration (from `frappe-v14` test pod, `bench-v14-69cbb96c4f-xpx4x`, site `v14-test.local`)

| Dependency | Version used (verified) | Official minimum | Recommended | Notes |
|------------|-------------------------|-------------------|-------------|-------|
| Python | **3.11.2** | 3.10 | 3.11 | 3.10 is Frappe's declared floor but untested here; 3.12+ breaks pypika (D32) — 3.11 is this project's practical floor |
| Node.js | **v24.13.0** | 18 (docs); `>=14` per `package.json` `engines` | 18–20 | Node 24 works but is far beyond what v14 needs — it's simply the image's shared Node install (see v15/v16 rows) |
| yarn | **1.22.22** | 1.12 | latest | |
| pip | **26.2.1** | 20 | latest | |
| bench CLI | **5.31.0** | any | latest | same bench CLI across v14/v15/v16 — bench itself is independent of the Frappe app version |
| Frappe | **14.101.1** (branch `version-14`) | — | — | |
| MariaDB | **10.11.18-MariaDB** (shared `frappe-system` instance) | 10.6.6 | 10.11 | |
| Redis | **8.10.1** (dedicated `redis-v14`, 3 sidecar processes) | 6 | 8 | |
| wkhtmltopdf | **0.12.6.1** (patched qt) | 0.12.6 (patched qt) | 0.12.6 (patched qt) | matches official requirement exactly |
| OS (container) | **Debian 12 (bookworm)** | — | — | the `frappe/bench:latest` image is Debian-based, **not Ubuntu** — corrects an assumption carried over from the original task brief |

### `bench init` command for v14:
```bash
bench init frappe-bench \
  --frappe-branch version-14 \
  --python /usr/bin/python3.11 \
  --skip-redis-config-generation
```

### `bench new-site` command for v14:
```bash
bench new-site <site> \
  --no-mariadb-socket \
  --db-host <mariadb-host> \
  --mariadb-root-username root \
  --mariadb-root-password <pass> \
  --admin-password <pass>
```

### Special setup steps for v14:
1. Install `python3.11-dev` before `bench init` (needed to compile `hiredis`):
   ```bash
   apt-get install -y python3.11-dev
   ```

---

## v15 Dependencies

### Verified working configuration (from `frappe-v15` test pod, `bench-v15`, site `test.local`)

| Dependency | Version used (verified) | Official minimum | Recommended | Notes |
|------------|-------------------------|-------------------|-------------|-------|
| Python | **3.14.2** | 3.10 | 3.11+ | v15's own `pyproject.toml` caps at `<3.15`; the image happened to ship 3.14, well above the 3.10 floor |
| Node.js | **v24.13.0** | 18 | 18–20 | |
| yarn | **1.22.22** | 1.12 | latest | |
| pip | **26.2.1** | 20 | latest | |
| bench CLI | **5.31.0** | any | latest | |
| Frappe | **15.118.0** (branch `version-15`) | — | — | |
| MariaDB | **10.11.18-MariaDB** (shared `frappe-system` instance) | 10.6.6 | 10.11 | prints `"MariaDB version ... is more than 10.8 which is not yet tested"` warning on every `new-site`/`reinstall`/`restore` — cosmetic only |
| Redis | **8.10.1** (shared `frappe-system` Bitnami instances) | 6 | 8 | |
| wkhtmltopdf | **0.12.6.1** (patched qt) | 0.12.6 (patched qt) | 0.12.6 (patched qt) | |
| OS (container) | **Debian 12 (bookworm)** | — | — | |

### `bench init` command for v15:
```bash
bench init frappe-bench \
  --frappe-branch version-15 \
  --skip-redis-config-generation
```

### `bench new-site` command for v15:
```bash
bench new-site <site> \
  --mariadb-user-host-login-scope='%' \
  --db-host <mariadb-host> \
  --mariadb-root-username root \
  --mariadb-root-password <pass> \
  --admin-password <pass>
```

---

## v16 Dependencies

### Verified working configuration (from `frappe-v16` test pod, `bench-v16-bfc76ddcd-zlrtl`, site `v16-test.local`)

| Dependency | Version used (verified) | Official minimum | Recommended | Notes |
|------------|-------------------------|-------------------|-------------|-------|
| Python | **3.14.2** | 3.14 (`pyproject.toml`: `>=3.14,<3.15`) | 3.14 | v16 is the first version to *require* 3.14, not just allow it |
| Node.js | **v24.13.0** | 24 (`package.json` `engines.node: ">=24"`) | 24+ | matches the official floor exactly |
| yarn | **1.22.22** | 1.22 | latest | |
| pip | **26.2.1** | 25.3 | latest | |
| bench CLI | **5.31.0** | any | latest | |
| Frappe | **16.31.0** (branch `version-16`) | — | — | |
| MariaDB | **10.11.18-MariaDB** (shared `frappe-system` instance, same as v14/v15) | **11.8 per official docs** | 11.8 | **our tested environment runs below the official minimum (10.11.18 < 11.8) yet works with no errors** — consistent with D26 (v16 prints no MariaDB version-compatibility warning at all, unlike v15). Not independently verified against 11.8; treat 10.11.18 as empirically working, not as proof 11.8 is unnecessary |
| Redis | **8.10.1** (dedicated `redis-v16`, 3 sidecar processes) | 6 | 8 | |
| wkhtmltopdf | **0.12.6.1** (patched qt) | 0.12.6 (patched qt) | 0.12.6 (patched qt) | |
| OS (container) | **Debian 12 (bookworm)** | — | — | |

### `bench init` command for v16:
```bash
bench init frappe-bench \
  --frappe-branch version-16 \
  --skip-redis-config-generation
```

### `bench new-site` command for v16:
```bash
bench new-site <site> \
  --mariadb-user-host-login-scope='%' \
  --db-host <mariadb-host> \
  --mariadb-root-username root \
  --mariadb-root-password <pass> \
  --admin-password <pass>
```

---

## Key behavioral differences between versions

| Behavior | v14 | v15 | v16 |
|----------|-----|-----|-----|
| MariaDB socket flag | `--no-mariadb-socket` (D33) | `--mariadb-user-host-login-scope='%'` | `--mariadb-user-host-login-scope='%'` |
| Backup dump tool | `mysqldump` (D35) | `mariadb-dump` | `mariadb-dump` |
| Backup path format | relative | relative | absolute (D28) |
| `migrate` extra steps | no | no | yes (D27) |
| `run-patch` output | verbose | verbose | silent on success — check exit code (D30) |
| `new-site` extra steps | no | no | yes: Workspace Sidebars, Desktop Icons (D26) |
| `drop-site` archive path | `sites/archived/` | `sites/archived/` | `archived/sites/` (D29) |
| `list-apps` version display | depends on `migrate` having run (D34) | depends on `migrate` having run (D34) | depends on `migrate` having run (D34) |
| MariaDB version warning on `new-site` | not observed | always printed | never printed |
| Python requirement | 3.11 practical floor (3.12+ breaks pypika, D32) | 3.10 official / 3.11+ tested | 3.14 required |
| Node requirement | 18+ official / 24 as-installed | 18+ official / 24 as-installed | 24 required |

Note on `list-apps`: D34 established this is a **site-lifecycle-state** issue (whether `migrate` has run), not a per-version difference — it applies identically to all three versions and is listed here for completeness, not because the versions differ.

---

## Custom Agent implementation notes

When provisioning a new bench, the Custom Agent must:

1. Check the requested Frappe version.
2. Use the correct `bench init` flags — v14 needs `--python /usr/bin/python3.11` explicitly; v15/v16 use whatever Python the image ships.
3. Use the correct `bench new-site` MariaDB flag — `--no-mariadb-socket` on v14, `--mariadb-user-host-login-scope='%'` on v15/v16 (D5, D33).
4. Set appropriate timeouts — v16's `migrate` runs extra cleanup steps and takes longer (D27).
5. Parse `backup` output correctly — v16 emits absolute paths, v14/v15 emit relative paths (D28).
6. Check the **exit code**, not output text, for `run-patch` success — v16 is silent on success (D30).
7. Don't infer app version from `list-apps` immediately after site creation on any version — it's empty until the first `migrate` runs (D34). Read `apps/{app}/{app}/__init__.py`'s `__version__` instead if a version is needed pre-migrate.
8. Don't assume the bench container is Ubuntu — it's Debian 12 (bookworm) across all tested versions; any OS-specific package logic (e.g. `apt` package names) should target Debian, not Ubuntu.
