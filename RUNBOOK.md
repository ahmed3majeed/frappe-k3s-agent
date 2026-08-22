# Runbook

Step-by-step documentation of everything executed on the server.
This file is updated automatically as work progresses.

## 2026-08-22 — Server access verification
- Verified SSH access to 92.5.91.195 as user `ubuntu`.
- Collected system info: aarch64 (ARM64), Ubuntu 22.04 (Oracle Cloud), 4 vCPUs, 23Gi RAM, 146G disk (144G free).

## 2026-08-22 — GitHub SSH key setup
- Generated ed25519 key on server: `/home/ubuntu/.ssh/github_frappe_agent` (comment: frappe-k3s-agent, no passphrase).
- Public key added to GitHub account `ahmed3majeed` (done manually by user).
- Created `/home/ubuntu/.ssh/config` with a `Host github.com` entry pointing to the new key.
- Verified with `ssh -T git@github.com` → "Hi ahmed3majeed! You've successfully authenticated, but GitHub does not provide shell access." (exit code 1 is expected for -T).

## 2026-08-22 — Repository creation
- Created public repo `ahmed3majeed/frappe-k3s-agent` via the GitHub REST API (`POST /user/repos`), authenticated with a short-lived Personal Access Token (ghp_***REDACTED***).
- API call was run on the local operator machine only — the PAT was never copied to or stored on this server.
- Response: HTTP 201, `html_url: https://github.com/ahmed3majeed/frappe-k3s-agent`, `ssh_url: git@github.com:ahmed3majeed/frappe-k3s-agent.git`, default branch `main`.
- Initialized local repo at `/home/ubuntu/frappe-k3s-agent`, added README.md, CHANGELOG.md, RUNBOOK.md.
- Pushed to GitHub over SSH using the `github_frappe_agent` deploy key configured above (no token involved in the push).

## 2026-08-22 — Phase 1: System Update

### Commands
```
sudo apt update
sudo apt upgrade -y
sudo apt install -y curl wget git vim htop unzip \
  build-essential apt-transport-https \
  ca-certificates gnupg2 software-properties-common \
  net-tools ufw
```

### Results
- `apt update`: package lists refreshed, 74 packages had upgrades available.
- `apt upgrade -y`: all 74 packages upgraded successfully.
  - **Note:** a kernel upgrade is pending — running kernel is `6.8.0-1054-oracle`, expected `6.8.0-1059-oracle` after upgrade. A reboot is required to load the new kernel; not performed automatically (would cause downtime). Flagged for a scheduled maintenance window.
- `apt install -y <essential packages>`: all requested packages already present/installed cleanly (no changes needed beyond the upgrade above).

### Installed versions
| Package | Version |
|---|---|
| curl | 7.81.0 |
| wget | GNU Wget 1.21.2 |
| git | 2.34.1 |
| vim | VIM 8.2 (2019 Dec 12) |
| htop | 3.0.5 |
| unzip | UnZip 6.00 |
| build-essential (gcc) | 11.4.0 (Ubuntu 11.4.0-1ubuntu1~22.04.3) |
| build-essential (make) | GNU Make 4.3 |
| apt-transport-https | 2.4.14 |
| ca-certificates | 20260601~22.04.1 |
| gnupg2 | GnuPG 2.2.27 |
| software-properties-common | 0.99.22.9 |
| net-tools | 1.60+git20181103.0eebece-1ubuntu5.4 |
| ufw | 0.36.1 |

## 2026-08-22 — Phase 2: Create Dedicated User

### Commands
```
sudo useradd -m -d /home/frappe -s /bin/bash frappe
sudo usermod -aG sudo frappe
sudo mkdir -p /home/frappe/.ssh
sudo cp /home/ubuntu/.ssh/authorized_keys /home/frappe/.ssh/authorized_keys
sudo chown -R frappe:frappe /home/frappe/.ssh
sudo chmod 700 /home/frappe/.ssh
sudo chmod 600 /home/frappe/.ssh/authorized_keys
echo "frappe ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/frappe
sudo chmod 440 /etc/sudoers.d/frappe
sudo visudo -c -f /etc/sudoers.d/frappe
```

### Results
- User `frappe` created: `uid=1002(frappe) gid=1002(frappe) groups=1002(frappe),27(sudo)`, home `/home/frappe`, shell `/bin/bash`.
- `/home/frappe/.ssh/authorized_keys` copied from `ubuntu`'s and confirmed identical (`diff` → no output). Permissions: `.ssh` = 700, `authorized_keys` = 600, both owned by `frappe:frappe`.
- `/etc/sudoers.d/frappe` created with `frappe ALL=(ALL) NOPASSWD:ALL`, mode 440. `visudo -c` → "parsed OK".
- Verified end-to-end from the operator machine: `ssh -i ssh-key-2026-08-22.key frappe@92.5.91.195` succeeds, and `sudo whoami` returns `root` with no password prompt.

**Security note:** `frappe` now has full passwordless sudo and accepts the same key as `ubuntu`. This was requested explicitly for automation convenience; worth revisiting (e.g. scoping sudo rules, separate keys) once the k3s automation flows are defined.

## 2026-08-22 — Phase 3: Security Hardening

### Commands
```
# UFW firewall (rules added before enabling, to avoid SSH lockout)
sudo ufw allow 22/tcp comment "SSH"
sudo ufw allow 80/tcp comment "HTTP"
sudo ufw allow 443/tcp comment "HTTPS"
sudo ufw allow 6443/tcp comment "k3s API"
sudo ufw --force enable

# SSH hardening
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.20260822
sudo sed -i \
  -e "s/^#\?PermitRootLogin.*/PermitRootLogin no/" \
  -e "s/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/" \
  -e "s/^#\?PasswordAuthentication.*/PasswordAuthentication no/" \
  /etc/ssh/sshd_config
sudo sshd -t
sudo systemctl restart ssh
```

### Results
- **UFW:** enabled, default deny incoming / allow outgoing. Rules: 22/tcp (SSH), 80/tcp (HTTP), 443/tcp (HTTPS), 6443/tcp (k3s API) — all allowed for both IPv4 and IPv6.
- **Pre-check:** found `/etc/ssh/sshd_config.d/60-cloudimg-settings.conf` already sets `PasswordAuthentication no` via the cloud-init default config, included before the relevant directives in the main file — no conflict with the changes made.
- **sshd_config:** `PermitRootLogin no`, `PubkeyAuthentication yes`, `PasswordAuthentication no`. Backed up original to `/etc/ssh/sshd_config.bak.20260822` before editing. `sshd -t` passed syntax check before restart.
- **Restart:** `systemctl restart ssh` → service active.
- **Post-restart verification (fresh connections, not reused sessions):**
  - `ubuntu` login via key → succeeds.
  - `frappe` login via key + passwordless sudo → succeeds.
  - `root` login via key → correctly rejected ("Permission denied (publickey)").

## 2026-08-22 — Phase 4: Verification Summary

| Check | Result |
|---|---|
| OS version | Ubuntu 22.04.5 LTS (jammy) |
| curl | 7.81.0 |
| wget | 1.21.2 |
| git | 2.34.1 |
| vim | 8.2 |
| htop | 3.0.5 |
| unzip | 6.00 |
| build-essential (gcc/make) | gcc 11.4.0 / GNU Make 4.3 |
| apt-transport-https | 2.4.14 |
| ca-certificates | 20260601~22.04.1 |
| gnupg2 | 2.2.27 |
| software-properties-common | 0.99.22.9 |
| net-tools | 1.60+git20181103.0eebece-1ubuntu5.4 |
| ufw | 0.36.1 |
| frappe user | exists (uid 1002), groups: frappe, sudo |
| frappe sudo | `(ALL : ALL) ALL` + `(ALL) NOPASSWD: ALL` — confirmed passwordless |
| SSH: PermitRootLogin | no |
| SSH: PasswordAuthentication | no |
| SSH: PubkeyAuthentication | yes |
| UFW status | active, default deny incoming |
| UFW rules | 22, 80, 443, 6443 (tcp, v4+v6) allowed |
| Uptime | up 31 min, load average 0.07/0.22/0.11 |
| **Reboot required** | **Yes** — pending kernel upgrade (6.8.0-1054 → 6.8.0-1059-oracle) from Phase 1. Not performed automatically; recommend scheduling before installing k3s. |

**Server is ready for k3s installation**, pending the outstanding kernel reboot above.
