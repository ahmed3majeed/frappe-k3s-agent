# Frappe Dependency Matrix
# Verified versions from actual test environments on k3s (ARM64)
# Last updated: 2026-08-23

---

## Support Status

| Version | Status | Notes |
|---------|--------|-------|
| v13 | ❌ Not supported | node-sass incompatible with Node 24+ V8 ABI (D36) |
| v14 | ✅ Supported | Requires Python 3.11 workaround (D32) |
| v15 | ✅ Supported | Full support — reference version |
| v16 | ✅ Supported | Latest — recommended for new deployments |

---

## v14 — Verified Dependency Versions

| Dependency | Actual version | Minimum | Recommended | Notes |
|------------|---------------|---------|-------------|-------|
| Frappe | 14.101.1 | 14.x | latest v14 | |
| Python (venv) | 3.11.2 | 3.10 | 3.11 | 3.12+ breaks pypika (D32) |
| Python (system) | 3.11.2 | 3.11 | 3.11 | Must use `--python /usr/bin/python3.11` |
| pip | 26.2.1 | 20 | latest | |
| Node.js | v24.13.0 | 16 | 18 | Node 24 works but exceeds v14 design — it's simply the shared image's Node install |
| yarn | 1.22.22 | 1.12 | latest | |
| bench CLI | 5.31.0 | any | latest | |
| MariaDB | 10.11.18-MariaDB | 10.6.6 | 10.11 | |
| Redis | 8.10.1 | 6 | 8 | |
| wkhtmltopdf | 0.12.6.1 | 0.12.6 | 0.12.6 (patched qt) | Must be patched qt version |
| OS (container) | Debian 12 (bookworm) | — | — | `frappe/bench:latest` is Debian-based, not Ubuntu — verified via `/etc/os-release`, not assumed |

### bench init (v14):
```bash
# Pre-requisite (run inside pod first):
apt-get install -y python3.11-dev

bench init frappe-bench \
  --frappe-branch version-14 \
  --python /usr/bin/python3.11 \
  --skip-redis-config-generation
```

### bench new-site (v14):
```bash
bench new-site <site-name> \
  --no-mariadb-socket \
  --db-host <mariadb-host> \
  --mariadb-root-username root \
  --mariadb-root-password <pass> \
  --admin-password <pass>
```

### Known v14-specific behaviors:
- backup uses `mysqldump` (not `mariadb-dump`) — D35
- list-apps shows full version info only AFTER migrate runs — D34
- `--mariadb-user-host-login-scope` flag does NOT exist — use `--no-mariadb-socket` — D33

---

## v15 — Verified Dependency Versions

| Dependency | Actual version | Minimum | Recommended | Notes |
|------------|---------------|---------|-------------|-------|
| Frappe | 15.118.0 | 15.x | latest v15 | |
| Python (venv) | 3.14.2 | 3.11 | 3.12+ | v15's `pyproject.toml` caps at `<3.15`; image ships 3.14 |
| pip | 26.2.1 | 20 | latest | |
| Node.js | v24.13.0 | 18 | 20+ | |
| yarn | 1.22.22 | 1.12 | latest | |
| bench CLI | 5.31.0 | any | latest | |
| MariaDB | 10.11.18-MariaDB | 10.6.6 | 10.11 | Shows deprecation warning if >10.8 |
| Redis | 8.10.1 | 6 | 8 | |
| wkhtmltopdf | 0.12.6.1 | 0.12.6 | 0.12.6 (patched qt) | |
| OS (container) | Debian 12 (bookworm) | — | — | |

### bench init (v15):
```bash
bench init frappe-bench \
  --frappe-branch version-15 \
  --skip-redis-config-generation
```

### bench new-site (v15):
```bash
bench new-site <site-name> \
  --mariadb-user-host-login-scope='%' \
  --db-host <mariadb-host> \
  --mariadb-root-username root \
  --mariadb-root-password <pass> \
  --admin-password <pass>
```

### Known v15-specific behaviors:
- MariaDB deprecation warning if version > 10.8 (informational only)
- backup uses relative paths in Backup Summary
- run-patch prints explicit success message

---

## v16 — Verified Dependency Versions

| Dependency | Actual version | Minimum | Recommended | Notes |
|------------|---------------|---------|-------------|-------|
| Frappe | 16.31.0 | 16.x | latest v16 | |
| Python (venv) | 3.14.2 | 3.14 | 3.14 | v16's `pyproject.toml` requires `>=3.14,<3.15` — first version to *require* 3.14, not just allow it |
| pip | 26.2.1 | 25.3 | latest | |
| Node.js | v24.13.0 | 24 | 24+ | matches official `engines.node: ">=24"` exactly |
| yarn | 1.22.22 | 1.22 | latest | |
| bench CLI | 5.31.0 | any | latest | |
| MariaDB | 10.11.18-MariaDB | 11.8 (official docs) | 11.8 | **tested environment runs below the official minimum (10.11.18 < 11.8) and still works, with no warning printed** — consistent with D26 |
| Redis | 8.10.1 | 6 | 8 | |
| wkhtmltopdf | 0.12.6.1 | 0.12.6 | 0.12.6 (patched qt) | |
| OS (container) | Debian 12 (bookworm) | — | — | |

### bench init (v16):
```bash
bench init frappe-bench \
  --frappe-branch version-16 \
  --skip-redis-config-generation
```

### bench new-site (v16):
```bash
bench new-site <site-name> \
  --mariadb-user-host-login-scope='%' \
  --db-host <mariadb-host> \
  --mariadb-root-username root \
  --mariadb-root-password <pass> \
  --admin-password <pass>
```

### Known v16-specific behaviors:
- bench new-site adds 2 new steps: Workspace Sidebars + Desktop Icons — D26
- migrate adds cleanup steps + enqueues delete_dynamic_links — D27
- backup uses absolute paths in Backup Summary — D28
- drop-site archives to archived/sites/ not sites/archived/ — D29
- run-patch is SILENT on success (check exit code not output) — D30

---

## Version Comparison: Key Behavioral Differences

| Behavior | v13 | v14 | v15 | v16 |
|----------|-----|-----|-----|-----|
| Support status | ❌ | ✅* | ✅ | ✅ |
| Python | 3.7+ | 3.11 only | 3.11+ | 3.14 required |
| Node.js | 14 | 16+ (24 as-installed) | 18+ (24 as-installed) | 24 required |
| MariaDB socket flag | N/A | --no-mariadb-socket | --mariadb-user-host-login-scope='%' | --mariadb-user-host-login-scope='%' |
| backup dump tool | N/A | mysqldump | mariadb-dump | mariadb-dump |
| backup path format | N/A | relative | relative | absolute |
| migrate extra steps | N/A | no | no | yes |
| run-patch output | N/A | verbose | verbose | silent |
| new-site extra steps | N/A | no | no | yes |
| drop-site archive path | N/A | sites/archived/ | sites/archived/ | archived/sites/ |

*v14 requires workaround: python3.11-dev + --python flag

---

## Custom Agent Implementation Rules

When provisioning a new bench, the Custom Agent MUST:

### 1. Select correct bench init command per version:
```python
def get_bench_init_command(frappe_version, bench_name):
    base = f"bench init {bench_name} --skip-redis-config-generation"
    if frappe_version == "v14":
        return f"apt-get install -y python3.11-dev && {base} --frappe-branch version-14 --python /usr/bin/python3.11"
    elif frappe_version == "v15":
        return f"{base} --frappe-branch version-15"
    elif frappe_version == "v16":
        return f"{base} --frappe-branch version-16"
    else:
        raise ValueError(f"Unsupported version: {frappe_version}")
```

### 2. Select correct bench new-site flags per version:
```python
def get_new_site_flags(frappe_version):
    if frappe_version == "v14":
        return "--no-mariadb-socket"
    else:  # v15, v16
        return "--mariadb-user-host-login-scope='%'"
```

### 3. Parse backup output correctly per version:
```python
def parse_backup_path(output, frappe_version):
    if frappe_version == "v16":
        # Absolute paths in output
        import re
        return re.findall(r'/home/frappe/.*\.sql\.gz', output)
    else:
        # Relative paths — combine with bench dir
        import re
        return re.findall(r'sites/.*\.sql\.gz', output)
```

### 4. Check run-patch result by exit code only:
```python
# WRONG — breaks on v16 (D30)
if "Success: Done" in output:
    mark_success()

# CORRECT — works on all versions
if exit_code == 0:
    mark_success()
```

### 5. Set appropriate timeouts:
```python
TIMEOUTS = {
    "v14": {"migrate": 120, "bench_init": 900},
    "v15": {"migrate": 120, "bench_init": 900},
    "v16": {"migrate": 300, "bench_init": 900},  # v16 migrate takes longer
}
```

### 6. Don't assume the container OS:
The bench image (`frappe/bench:latest`) is Debian 12 (bookworm) across v14/v15/v16 — not Ubuntu. Any OS-specific package logic (e.g. `apt` package names, patch availability) should target Debian, not Ubuntu.
