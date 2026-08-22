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
