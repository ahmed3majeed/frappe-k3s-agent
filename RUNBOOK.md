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

## 2026-08-22 — Reboot (apply pending kernel upgrade)

### Commands
```
sudo reboot
# ... wait for host to come back ...
uname -r
sudo ufw status verbose
ssh frappe@92.5.91.195 whoami && sudo whoami
```

### Results
- Pre-reboot kernel: `6.8.0-1054-oracle`. Rebooted to apply the kernel upgrade pending since Phase 1.
- Server came back within ~10 seconds of the reboot command.
- Post-reboot kernel: `6.8.0-1059-oracle` — upgrade applied successfully, `/var/run/reboot-required` cleared.
- **SSH access:** both `ubuntu` and `frappe` verified via fresh key-based connections post-reboot; `frappe` passwordless sudo confirmed working (`sudo whoami` → `root`).
- **UFW:** active and enabled on startup, same 4 rules intact (22, 80, 443, 6443 — tcp, v4+v6), default deny incoming.

**Server fully verified post-reboot and ready for k3s installation.**

## 2026-08-22 — k3s Installation

### Commands
```
# Open kubelet port in UFW
sudo ufw allow 10250/tcp comment "k3s kubelet"

# Install k3s (latest stable channel, Traefik left enabled — default)
curl -sfL https://get.k3s.io | sh -

# Configure kubectl for frappe
mkdir -p /home/frappe/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /home/frappe/.kube/config
sudo chown frappe:frappe /home/frappe/.kube/config
chmod 600 /home/frappe/.kube/config
echo "export KUBECONFIG=/home/frappe/.kube/config" >> /home/frappe/.bashrc
```

### Results
- **UFW:** added `10250/tcp` (k3s kubelet), both v4/v6 — now 22, 80, 443, 6443, 10250 all allowed, default deny incoming otherwise.
- **k3s installed:** version `v1.36.3+k3s1` (stable channel), arm64 binary, installed as user `frappe` (install script auto-escalated via `sudo`). Systemd unit `k3s.service` created, enabled, and started automatically.
- **Traefik:** left enabled (no `--disable traefik` flag used) — running as the cluster Ingress Controller per requirements.
- **kubectl:** `/usr/local/bin/kubectl` symlinked to the k3s binary by the installer. Kubeconfig copied from `/etc/rancher/k3s/k3s.yaml` to `/home/frappe/.kube/config` (chmod 600, owned by frappe), and `KUBECONFIG` exported in `frappe`'s `.bashrc`.

### Verification

**1. k3s service:**
```
$ sudo systemctl is-active k3s
active
$ sudo systemctl is-enabled k3s
enabled
```

**2. Node status:**
```
$ kubectl get nodes -o wide
NAME   STATUS   ROLES           AGE   VERSION        INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION              CONTAINER-RUNTIME
test   Ready    control-plane   46s   v1.36.3+k3s1   10.0.0.37     <none>        Ubuntu 22.04.5 LTS   6.8.0-1059-oracle (arm64)   containerd://2.3.2-k3s2
```

**3. System pods (kube-system):**
```
NAME                                      READY   STATUS      RESTARTS      AGE
coredns-54996dc9b4-f75gb                  1/1     Running     0             40s
helm-install-traefik-crd-vsd8r            0/1     Completed   0             35s
helm-install-traefik-s8wnl                0/1     Completed   1 (29s ago)   35s
local-path-provisioner-58d557dc48-675gn   1/1     Running     0             40s
metrics-server-6dc596dfb8-q9qsh           1/1     Running     0             38s
svclb-traefik-de36e471-mxmr8              2/2     Running     0             26s
traefik-59b7647586-ql68n                  1/1     Running     0             27s
```
All 4 required components confirmed Running: **coredns**, **traefik**, **local-path-provisioner**, **metrics-server**. (`helm-install-traefik-*` jobs show `Completed` — expected, they are one-shot jobs that install the Traefik Helm chart and exit 0 after success.)

**4. Version:**
```
$ kubectl version
Client Version: v1.36.3+k3s1
Kustomize Version: v5.8.1
Server Version: v1.36.3+k3s1
```

**k3s installation complete and fully verified.** Traefik is live as the Ingress Controller, ready for workload deployment.

## 2026-08-22 — Shared Infrastructure Namespace (frappe-system)

### Step 1: Create Namespace
```
$ kubectl create namespace frappe-system
namespace/frappe-system created
```
Verified: `kubectl get namespace frappe-system` → `Active`.

### Step 2: Install Helm
```
$ curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
Downloading https://get.helm.sh/helm-v3.21.4-linux-arm64.tar.gz
Verifying checksum... Done.
helm installed into /usr/local/bin/helm
```
`helm version` → `v3.21.4` (checksum verified by the install script before install).

### Step 3: Add Bitnami repo
```
$ helm repo add bitnami https://charts.bitnami.com/bitnami
"bitnami" has been added to your repositories
$ helm repo update
Successfully got an update from the "bitnami" chart repository
```

## 2026-08-22 — Step 4: Install MariaDB — FAILED (diagnosed, fix pending confirmation)

### Version resolution
Requested `--version 20.x.x` does not correspond to MariaDB app version 10.11 (chart 20.x installs MariaDB 11.4.x). Confirmed with user: prioritize the **MariaDB 10.11** requirement. Resolved chart version: **12.2.9** (app version 10.11.4), the latest Bitnami chart still on that MariaDB line.

### Command
```
helm install mariadb bitnami/mariadb \
  --namespace frappe-system \
  --values /home/frappe/mariadb-values.yaml \
  --version 12.2.9 \
  --wait --timeout 5m
```
(`mariadb-values.yaml` written per spec: 10Gi persistence, utf8mb4 charset/collation, 256M innodb_buffer_pool_size, slow_query_log=1, database/user `frappe`. Credentials intentionally omitted from this document — see note below.)

### Error
```
Error: INSTALLATION FAILED: context deadline exceeded
```

### Root cause (diagnosed via `kubectl describe pod`)
```
Warning  Failed  kubelet  Failed to pull image "docker.io/bitnami/mariadb:10.11.4-debian-11-r46":
  rpc error: code = NotFound desc = ... not found
```
Pod stuck in `ImagePullBackOff`. Confirmed directly against Docker Hub's API:
- `docker.io/bitnami/mariadb:10.11.4-debian-11-r46` → **HTTP 404** (removed)
- `docker.io/bitnamilegacy/mariadb:10.11.4-debian-11-r46` → **HTTP 200** (exists)

This matches Bitnami's 2025 catalog restructuring: older pinned image tags for non-latest chart versions were moved out of the free `bitnami` Docker Hub org into `bitnamilegacy`, while the Helm chart index itself was left unchanged (still references the old, now-missing tag). This affects any Bitnami chart pinned to an older app version, not just this one.

### Cleanup
```
$ helm uninstall mariadb -n frappe-system
release "mariadb" uninstalled
```
Namespace left clean; PVC/pod from the failed attempt removed. No workaround applied yet — awaiting confirmation on the fix below before retrying.

**Proposed fix:** override the image registry to `bitnamilegacy` (same tag, same chart, same values) via `--set image.repository=bitnamilegacy/mariadb`, or pin an image on a chart version whose tag Bitnami still serves from the free `bitnami` org.

**Note on credentials:** the values file (`/home/frappe/mariadb-values.yaml`, root/user passwords) is intentionally not reproduced verbatim in this document, since this repository is public on GitHub and this file lives only on the server (mode 600).

## 2026-08-22 — Step 4: Install MariaDB — Attempt 2 (official image on Bitnami chart) — FAILED

### Command
```
helm install mariadb bitnami/mariadb \
  --namespace frappe-system \
  --values /home/frappe/mariadb-values.yaml \
  --version 12.2.9 \
  --set image.registry=docker.io \
  --set image.repository=library/mariadb \
  --set image.tag=10.11 \
  --wait --timeout 2m
```

### Error
```
Error: INSTALLATION FAILED: context deadline exceeded
```
Pod status: `CrashLoopBackOff`. Image pulled successfully this time (`docker.io/library/mariadb:10.11`, confirms the official image itself is fine), but the container crashes on every start:
```
2026-08-22 20:46:00 0 [Warning] Can't create test file '/var/lib/mysql/mariadb-0.lower-test' (Errcode: 13 "Permission denied")
2026-08-22 20:46:00 0 [ERROR] mariadbd: Can't create/write to file './ddl_recovery.log' (Errcode: 13 "Permission denied")
2026-08-22 20:46:00 0 [ERROR] DDL_LOG: Failed to create ddl log file: ./ddl_recovery.log
2026-08-22 20:46:00 0 [ERROR] Aborting
```

### Root cause
The Bitnami `mariadb` chart is built around Bitnami's own container conventions: a specific non-root UID via `securityContext`, a `/bitnami/mariadb`-style data path, and Bitnami-specific entrypoint/init scripts. The official `docker.io/library/mariadb` image expects to own `/var/lib/mysql` under its own user (root-managed `docker-entrypoint.sh`, different init flow). Simply overriding `image.*` on the Bitnami chart mixes incompatible conventions — the official image's process can't write to the volume because the Bitnami chart's pod security context sets the wrong filesystem ownership/UID for it. This is not a fixable config tweak on the Bitnami chart; the official image needs to be deployed with its own manifest (StatefulSet/Deployment), not through the Bitnami chart.

### Cleanup
```
$ helm uninstall mariadb -n frappe-system
release "mariadb" uninstalled
```
Namespace left clean again. Stopping per instructions to confirm the path forward before continuing — flagged to user with concrete evidence (logs above) that "official image + Bitnami chart" is not a viable combination, recommending a native Kubernetes manifest (StatefulSet + Service + PVC + Secret) using `mariadb:10.11` instead.

## 2026-08-22 — Step 4: Install MariaDB — Attempt 3 (native manifests, official image) — SUCCESS

Per user decision: dropped the Bitnami Helm chart entirely and deployed MariaDB 10.11 with plain Kubernetes manifests using the official `mariadb:10.11` image, preserving the same configuration values from the original spec (10Gi persistence, `frappe` db/user, custom my.cnf tuning).

### Manifests
Written to `/home/frappe/manifests/mariadb/` (kept off the git repo — the Secret holds real credentials and this repo is public):
- `secret.yaml` — `mariadb-secret` (root-password, password). Mode 600.
- `configmap.yaml` — `mariadb-config`, mounted at `/etc/mysql/conf.d/custom.cnf`:
  ```
  [mysqld]
  max_allowed_packet=128M
  character-set-server=utf8mb4
  collation-server=utf8mb4_unicode_ci
  innodb_buffer_pool_size=256M
  slow_query_log=1
  ```
- `statefulset.yaml` — 1 replica, image `mariadb:10.11`, env `MARIADB_ROOT_PASSWORD`/`MARIADB_DATABASE`/`MARIADB_USER`/`MARIADB_PASSWORD` sourced from the Secret, data volume at `/var/lib/mysql` via a 10Gi `volumeClaimTemplate` (`local-path` storage class), readiness/liveness probes via `mysqladmin ping`.
- `service.yaml` — headless ClusterIP service `mariadb` on port 3306 (DNS: `mariadb.frappe-system.svc.cluster.local`, matches the original spec's service naming expectation).

### Commands
```
kubectl apply -f /home/frappe/manifests/mariadb/secret.yaml
kubectl apply -f /home/frappe/manifests/mariadb/configmap.yaml
kubectl apply -f /home/frappe/manifests/mariadb/service.yaml
kubectl apply -f /home/frappe/manifests/mariadb/statefulset.yaml
kubectl rollout status statefulset/mariadb -n frappe-system --timeout=180s
```

### Result
```
secret/mariadb-secret created
configmap/mariadb-config created
service/mariadb created
statefulset.apps/mariadb created
partitioned roll out complete: 1 new pods have been updated...

$ kubectl get pods -n frappe-system
NAME        READY   STATUS    RESTARTS   AGE
mariadb-0   1/1     Running   0          20s

$ kubectl get pvc -n frappe-system
NAME             STATUS   CAPACITY   ACCESS MODES   STORAGECLASS
data-mariadb-0   Bound    10Gi       RWO            local-path

$ kubectl get svc -n frappe-system
NAME      TYPE        CLUSTER-IP   PORT(S)
mariadb   ClusterIP   None         3306/TCP
```
MariaDB 10.11 is up and healthy. Connection test deferred to the Step 6 verification pass.

## 2026-08-22 — Step 5: Install Redis (3 instances)

Installed via `bitnami/redis` Helm chart (no version pinned in spec, resolved to latest available: chart `28.0.10`, app version `8.10.1` — this chart line is on the currently-maintained free tier, unlike the older pinned MariaDB tag from Step 4, so no image availability issue here). Each instance: auth disabled, no persistence, standalone (0 replicas), distinct port for the master service.

### Commands
```
helm install redis-cache bitnami/redis \
  --namespace frappe-system \
  --set auth.enabled=false \
  --set master.persistence.enabled=false \
  --set replica.replicaCount=0 \
  --set master.service.ports.redis=6379 \
  --wait --timeout 3m

helm install redis-queue bitnami/redis \
  --namespace frappe-system \
  --set auth.enabled=false \
  --set master.persistence.enabled=false \
  --set replica.replicaCount=0 \
  --set master.service.ports.redis=6380 \
  --wait --timeout 3m

helm install redis-socketio bitnami/redis \
  --namespace frappe-system \
  --set auth.enabled=false \
  --set master.persistence.enabled=false \
  --set replica.replicaCount=0 \
  --set master.service.ports.redis=6381 \
  --wait --timeout 3m
```

### Result
All three deployed successfully (`STATUS: deployed`). Chart emitted standard warnings (rolling `:latest` tags on sub-images, no resource limits set) — informational only, not errors.

```
$ helm list -n frappe-system
NAME            NAMESPACE       REVISION   STATUS     CHART           APP VERSION
redis-cache     frappe-system   1          deployed   redis-28.0.10   8.10.1
redis-queue     frappe-system   1          deployed   redis-28.0.10   8.10.1
redis-socketio  frappe-system   1          deployed   redis-28.0.10   8.10.1

$ kubectl get pods -n frappe-system
NAME                      READY   STATUS    RESTARTS   AGE
mariadb-0                 1/1     Running   0          2m43s
redis-cache-master-0      1/1     Running   0          107s
redis-queue-master-0      1/1     Running   0          68s
redis-socketio-master-0   1/1     Running   0          30s
```

Service DNS names for connection testing:
- `redis-cache-master.frappe-system.svc.cluster.local:6379`
- `redis-queue-master.frappe-system.svc.cluster.local:6380`
- `redis-socketio-master.frappe-system.svc.cluster.local:6381`

## 2026-08-22 — Step 6: Verify Everything

### MariaDB connection test
Note: used the official `mariadb:10.11` image for the test client instead of `bitnami/mariadb:10.11` — the latter's specific pinned tags are gone from the free Bitnami org (see Step 4 failures above), and this image matches what was actually deployed.
```
$ kubectl run mariadb-test --rm --restart=Never --attach \
  --image=mariadb:10.11 --namespace frappe-system \
  -- mysql -h mariadb.frappe-system.svc.cluster.local -u root -p***REDACTED*** -e "SHOW DATABASES;"

Database
frappe
information_schema
mysql
performance_schema
sys
pod "mariadb-test" deleted from frappe-system namespace
```
`frappe` database confirmed present.

### Redis connection tests
```
$ kubectl run redis-test-cache ... -- redis-cli -h redis-cache-master.frappe-system.svc.cluster.local -p 6379 ping
PONG

$ kubectl run redis-test-queue ... -- redis-cli -h redis-queue-master.frappe-system.svc.cluster.local -p 6380 ping
PONG

$ kubectl run redis-test-socketio ... -- redis-cli -h redis-socketio-master.frappe-system.svc.cluster.local -p 6381 ping
PONG
```
All three Redis instances respond correctly on their designated ports.

### Summary: pods in frappe-system

| Pod | Ready | Status | Restarts | Role |
|---|---|---|---|---|
| mariadb-0 | 1/1 | Running | 0 | Shared MariaDB 10.11 (native manifest, official image) |
| redis-cache-master-0 | 1/1 | Running | 0 | Redis cache, port 6379 |
| redis-queue-master-0 | 1/1 | Running | 0 | Redis queue, port 6380 |
| redis-socketio-master-0 | 1/1 | Running | 0 | Redis socketio, port 6381 |

**frappe-system namespace is fully verified and ready to back Frappe site deployments.**

### Summary of deviations from the original spec
1. **MariaDB Helm version** `20.x.x` → resolved to chart `12.2.9` (MariaDB 10.11.4), per explicit confirmation to prioritize the 10.11 requirement.
2. **MariaDB delivery mechanism** Bitnami chart → dropped entirely in favor of native Kubernetes manifests with the official `mariadb:10.11` image, after two chart-based attempts failed (missing free-tier image tag, then incompatible container conventions when overriding just the image). Per explicit user decision.
3. **Credentials** never committed to this public repo in plaintext — real values live only in `/home/frappe/mariadb-values.yaml` (chmod 600, unused after the pivot) and `/home/frappe/manifests/mariadb/secret.yaml` (chmod 600) on the server, and in the in-cluster `mariadb-secret` Kubernetes Secret.

## 2026-08-22 — First Frappe Bench Pod (frappe-v15)

### Step 1: Namespace
```
$ kubectl create namespace frappe-v15
namespace/frappe-v15 created
```

### Step 2: Create bench pod
```
$ kubectl run bench-v15 \
  --image=frappe/bench:latest \
  --namespace=frappe-v15 \
  --restart=Never \
  --env="MARIADB_HOST=mariadb.frappe-system.svc.cluster.local" \
  -- sleep infinity
pod/bench-v15 created
```

### Step 3: Wait for Ready
```
$ kubectl wait --for=condition=Ready pod/bench-v15 -n frappe-v15 --timeout=120s
pod/bench-v15 condition met
```
`kubectl get pod bench-v15` → `1/1 Running`.

### Step 4: Verify bench available
```
$ kubectl exec -n frappe-v15 bench-v15 -- bench --version
5.31.0
```

### Step 5: Configure bench hosts — FAILED

```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "
  bench set-mariadb-host mariadb.frappe-system.svc.cluster.local
  ...
"
WARN: Command not being executed in bench directory
ERROR: [Errno 2] No such file or directory: './sites/common_site_config.json'
FileNotFoundError: [Errno 2] No such file or directory: './sites/common_site_config.json'
command terminated with exit code 1
```
(same error repeated for all four `bench set-*-host` calls)

### Root cause
`frappe/bench:latest` is a bare toolchain image — it ships the `bench` CLI, Python, Node, and their dependency stacks, but **no initialized bench project**. Confirmed via `find`/`ls`: `/home/frappe` contains only `.bench` (the CLI's own package metadata), no `frappe-bench`/`sites` directory. `bench set-*-host` writes into `./sites/common_site_config.json`, which only exists after `bench init` has created a bench directory. Steps 5–7 as specified assume that directory already exists and skip `bench init` entirely.

**Stopping here per instructions** — need a decision on the `bench init` invocation (bench directory name, Frappe branch/version to fetch — namespace is `frappe-v15` suggesting `version-15`, and whether to init in the pod's home dir or a mounted volume so it survives pod restarts) before continuing to a corrected Step 5.

## 2026-08-22 — Bench Pod Fix: PVC + bench init

Per user direction: use Frappe branch `version-15` (matches the `frappe-v15` namespace), and back the bench pod with a PVC so work survives pod restarts (this test pod would otherwise lose all bench state on any restart).

### Recreated pod with persistent storage
```
kubectl delete pod bench-v15 -n frappe-v15
```
New manifests written to `/home/frappe/manifests/frappe-v15/`:
- `bench-pvc.yaml` — `bench-v15-data`, 10Gi, `local-path` storage class.
- `bench-pod.yaml` — same pod as before, plus the PVC mounted at `/home/frappe/bench-data` (not directly at `frappe-bench` — see below), `workingDir` set there.

```
$ kubectl apply -f bench-pvc.yaml
persistentvolumeclaim/bench-v15-data created
$ kubectl apply -f bench-pod.yaml
pod/bench-v15 created
$ kubectl wait --for=condition=Ready pod/bench-v15 -n frappe-v15 --timeout=120s
pod/bench-v15 condition met
```

### bench init — attempt 1: FAILED (mount path)
```
$ kubectl exec ... -- bash -c "cd /home/frappe && bench init frappe-bench --frappe-branch version-15"
ERROR: Bench instance already exists at frappe-bench
```
Cause: the PVC was originally mounted directly at `/home/frappe/frappe-bench`, so the target directory already existed (empty, but present) when `bench init` ran — `bench init` requires the target path to not exist yet, since it creates it itself. **Fix:** mount the PVC one level up, at `/home/frappe/bench-data`, and run `bench init frappe-bench` from inside that directory so the `frappe-bench` subdirectory doesn't pre-exist.

### bench init — attempt 2: FAILED (redis-server missing)
```
$ kubectl exec ... -- bash -c "cd /home/frappe/bench-data && bench init frappe-bench --frappe-branch version-15"
/bin/sh: 1: redis-server: not found
subprocess.CalledProcessError: Command 'redis-server --version' returned non-zero exit status 127.
ERROR: There was a problem while creating frappe-bench
Do you want to rollback these changes? [y/N]: Aborted!
```
Cause: by default `bench init` tries to generate a local Redis config, which shells out to a local `redis-server` binary to check its version — not present in this image, and irrelevant anyway since we're pointing at the external `frappe-system` Redis instances. Partial `frappe-bench` directory (apps/, config/, env/, logs/, sites/) was left behind since the rollback prompt defaulted to No in non-interactive exec; removed it (`rm -rf`) before retrying.

**Fix:** added `--skip-redis-config-generation` (implied by the overall design — bench is meant to use the external Redis services, not a local one).

### bench init — attempt 3: SUCCESS
```
$ kubectl exec ... -- bash -c "cd /home/frappe/bench-data && bench init frappe-bench --frappe-branch version-15 --skip-redis-config-generation"
...
SUCCESS: Bench frappe-bench initialized
```
(Frappe framework cloned from `version-15`, Python venv created via `uv`, JS assets built. Some benign `WARN Cannot connect to redis_cache to update assets_json` lines during the asset build — expected, since Redis config wasn't generated in this bench and the asset step doesn't need it to succeed.)

### Step 5: Configure bench hosts — SUCCESS
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "
cd /home/frappe/bench-data/frappe-bench
bench set-mariadb-host mariadb.frappe-system.svc.cluster.local
bench set-redis-cache-host redis-cache-master.frappe-system.svc.cluster.local:6379
bench set-redis-queue-host redis-queue-master.frappe-system.svc.cluster.local:6380
bench set-redis-socketio-host redis-socketio-master.frappe-system.svc.cluster.local:6381
cat sites/common_site_config.json
"
{
 "db_host": "mariadb.frappe-system.svc.cluster.local",
 "redis_cache": "redis-cache-master.frappe-system.svc.cluster.local:6379",
 "redis_queue": "redis-queue-master.frappe-system.svc.cluster.local:6380",
 "redis_socketio": "redis-socketio-master.frappe-system.svc.cluster.local:6381",
 ...
}
```
All four infrastructure hosts confirmed correctly written to `common_site_config.json`.

## 2026-08-22 — Step 6 (retry) & Step 7: new-site + verification — SUCCESS

### Redis URL scheme fix
```
$ kubectl exec ... -- bash -c "cd .../frappe-bench && bench new-site test.local --no-mariadb-socket --db-host ... --mariadb-root-username root --mariadb-root-password *** --admin-password ***"
...
ValueError: Redis URL must specify one of the following schemes (redis://, rediss://, unix://)
```
Cause: `bench set-redis-*-host` (Step 5, as literally specified) writes a bare `host:port` value, but this Frappe version's Redis client requires a full URL with scheme. **Fix:** re-ran `bench set-redis-cache-host` / `-queue-host` / `-socketio-host` with `redis://` prefixed onto each host:port value. Re-verified `common_site_config.json` — all three now read `redis://<host>.frappe-system.svc.cluster.local:<port>`.

### Step 6: bench new-site test.local — SUCCESS
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "
cd /home/frappe/bench-data/frappe-bench
bench new-site test.local \
  --no-mariadb-socket \
  --db-host mariadb.frappe-system.svc.cluster.local \
  --mariadb-root-username root \
  --mariadb-root-password *** \
  --admin-password ***
"
--no-mariadb-socket is DEPRECATED; use --mariadb-user-host-login-scope='%' (wildcard) or --mariadb-user-host-login-scope=<myhostscope>, instead.
Warning: MariaDB version ['10.11', '18'] is more than 10.8 which is not yet tested with Frappe Framework.

Installing frappe...
Updating DocTypes for frappe        : [========================================] 100%
Updating Dashboard for frappe
*** Scheduler is disabled ***
```
Two informational warnings, not errors: `--no-mariadb-socket` is deprecated in favor of `--mariadb-user-host-login-scope` (still functioned correctly here); and Frappe hasn't been tested against MariaDB >10.8 yet (informational compatibility notice — worked fine in practice for a base site install).

### Step 7: verify site — SUCCESS
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "cd .../frappe-bench && bench --site test.local list-apps"
frappe 15.118.0 version-15
```

**`test.local` created successfully on frappe-v15, backed by the shared `frappe-system` MariaDB + Redis infrastructure.** Bench data (frappe-bench directory, site files, DB config) persists on the `bench-v15-data` PVC across pod restarts.

### Summary of deviations from the original spec (this task)
1. **Pod → Pod + PVC:** added a PersistentVolumeClaim (`bench-v15-data`, 10Gi) so bench state survives restarts; per user decision.
2. **`bench init` added:** the original steps assumed an already-initialized bench directory; `frappe/bench:latest` only ships the CLI. Added `bench init frappe-bench --frappe-branch version-15 --skip-redis-config-generation` before Step 5, with the PVC mounted one directory above `frappe-bench` (init requires the target path not to pre-exist).
3. **Redis host format:** `bench set-redis-*-host` values needed a `redis://` scheme prefix; bare `host:port` (as literally specified) caused `bench new-site` to fail on Redis connection setup.

## 2026-08-23 — Tier A Command Tests (test.local, frappe-v15)

All commands run via `kubectl exec -n frappe-v15 bench-v15`, `cd /home/frappe/bench-data/frappe-bench` first.

### A2: install-app — ⚡ Pass with modification
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "
  cd /home/frappe/bench-data/frappe-bench &&
  bench --site test.local install-app frappe --force
"
...
Installing frappe...
Updating DocTypes for frappe        : [========================================] 100%
Traceback (most recent call last):
  ...
  File ".../getpass.py", line 183, in _raw_input
    raise EOFError
builtins.EOFError:
command terminated with exit code 1
```
**Failure cause:** `--force` on an app already installed on the site triggers an interactive Administrator-password reset prompt (`Set Administrator password:` / `Re-enter Administrator password:`). There's no non-interactive flag for this (`--help` shows only `--force`). A plain `kubectl exec` has no stdin, so `getpass` hits EOF immediately.

**Modification:** used `kubectl exec -i` with the password piped twice via stdin:
```
$ printf "admin123\nadmin123\n" | kubectl exec -i -n frappe-v15 bench-v15 -- bash -c "
  cd /home/frappe/bench-data/frappe-bench &&
  bench --site test.local install-app frappe --force
"
...
Updating DocTypes for frappe        : [========================================] 100%
Warning: Password input may be echoed.
Set Administrator password:
Warning: Password input may be echoed.
Re-enter Administrator password:

Updating Dashboard for frappe
```
Result: exit 0, succeeded.

### A4: migrate — ✅ Pass
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "cd .../frappe-bench && bench --site test.local migrate"
Migrating test.local
Updating DocTypes for frappe        : [========================================] 100%
Updating Dashboard for frappe
Executing `after_migrate` hooks...

Queued rebuilding of search index for test.local
```
Exit 0, no modifications needed.

### A6: backup — ✅ Pass
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "cd .../frappe-bench && bench --site test.local backup --with-files --verbose"
set -o pipefail; /usr/bin/mariadb-dump --user=*** --host=mariadb.frappe-system.svc.cluster.local --port=3306 --password=********** ... | gzip >> ./test.local/private/backups/20260823_024659-test_local-database.sql.gz

Backup Summary for test.local at 2026-08-23 02:46:59
Config  : .../20260823_024659-test_local-site_config_backup.json  149.0B
Database: .../20260823_024659-test_local-database.sql.gz          254.0KiB
Public  : .../20260823_024659-test_local-files.tar                10.0KiB
Private : .../20260823_024659-test_local-private-files.tar        10.0KiB
Backup for Site test.local has been successfully completed with files
```
Exit 0, no modifications needed. (Bench's own output already redacts the DB password.)

### A9: add-user — ✅ Pass
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "
  cd .../frappe-bench &&
  bench --site test.local add-user testuser@test.com --first-name Test --last-name User --password ***REDACTED***
"
(no output)
EXIT: 0
```
Command is silent on success — verified independently:
```
$ bench --site test.local execute frappe.client.get_list --kwargs '{"doctype": "User", "filters": {"name": "testuser@test.com"}}'
[{"name": "testuser@test.com"}]
```
User confirmed created.

### A7: maintenance-mode on — ✅ Pass
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "cd .../frappe-bench && bench --site test.local set-maintenance-mode on"
(no output)
EXIT: 0
```
Verified via `sites/test.local/site_config.json`: `"maintenance_mode": 1`.

### A8: maintenance-mode off — ✅ Pass
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "cd .../frappe-bench && bench --site test.local set-maintenance-mode off"
(no output)
EXIT: 0
```
Verified via `site_config.json`: `"maintenance_mode": 0`.

### A11: clear-cache — ✅ Pass
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "cd .../frappe-bench && bench --site test.local clear-cache"
(no output)
EXIT: 0
```

### A12: list-apps — ✅ Pass
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "cd .../frappe-bench && bench --site test.local list-apps"

frappe 15.118.0 version-15
```

### Tier A Summary

| ID | Command | Result | Notes |
|---|---|---|---|
| A2 | install-app --force | ⚡ Pass with modification | Needed `kubectl exec -i` + piped Administrator password (twice) — no non-interactive flag exists for the reset prompt |
| A4 | migrate | ✅ Pass | — |
| A6 | backup --with-files --verbose | ✅ Pass | — |
| A9 | add-user | ✅ Pass | Silent on success; verified via `frappe.client.get_list` |
| A7 | set-maintenance-mode on | ✅ Pass | Silent on success; verified via `site_config.json` |
| A8 | set-maintenance-mode off | ✅ Pass | Silent on success; verified via `site_config.json` |
| A11 | clear-cache | ✅ Pass | — |
| A12 | list-apps | ✅ Pass | — |

**7/8 passed cleanly, 1/8 passed with a required modification (A2).**

## Decision Log

### D1: MariaDB deployment method
Question: How to deploy MariaDB 10.11 on k3s?
Options considered:
  - Bitnami Helm chart 12.2.9 → FAILED (image removed from free registry)
  - Bitnami chart + official image override → FAILED (incompatible conventions)
  - Native K8s manifests with official mariadb:10.11 image → ✅ CHOSEN
Reason: Bitnami moved old tags to bitnamilegacy in 2025 restructuring.
        Native manifests give full control and no registry dependency.

### D2: Storage for bench pod
Question: Ephemeral or persistent storage for bench pod?
Options considered:
  - Ephemeral (no PVC) → bench init takes 10min, lost on restart
  - PVC (10Gi) → ✅ CHOSEN
Reason: bench init clones repos and installs deps — too expensive to repeat.
        PVC matches production pattern anyway.

### D3: Redis host format
Question: What format does Frappe expect for Redis hosts?
Options considered:
  - host:port (bare) → FAILED (ValueError: Redis URL must specify scheme)
  - redis://host:port → ✅ CHOSEN
Reason: Frappe v15 Redis client requires full URL scheme.
        All bench set-redis-*-host commands must use redis:// prefix.

### D4: bench init flags
Question: What flags does bench init need in k3s environment?
Options considered:
  - bench init frappe-bench → FAILED (redis-server not found in image)
  - bench init frappe-bench --skip-redis-config-generation → ✅ CHOSEN
Reason: External Redis is used — no local redis-server binary exists in pod.
        This flag is REQUIRED for all future bench init calls in k3s.

### D5: MariaDB socket flag (deprecated)
Question: How to allow remote MariaDB connections?
Options considered:
  - --no-mariadb-socket → Works but DEPRECATED in Frappe v15
  - --mariadb-user-host-login-scope='%' → ✅ RECOMMENDED going forward
Reason: --no-mariadb-socket still works but shows deprecation warning.
        Future bench new-site calls should use the new flag.

### D6: bench init target directory placement
Question: Where should the PVC be mounted relative to the bench directory?
Options considered:
  - Mount PVC directly at .../frappe-bench → FAILED ("Bench instance already exists")
  - Mount PVC one level up, bench init creates frappe-bench inside it → ✅ CHOSEN
Reason: bench init requires its target directory to not already exist, since it
        creates it itself. Mounting the PVC at the parent directory leaves the
        target path free for bench init to create, while still persisting
        everything underneath it.

### D7: install-app --force on an already-installed app
Question: How to run bench install-app --force non-interactively via kubectl exec?
Options considered:
  - kubectl exec (no stdin) → FAILED (EOFError on Administrator password prompt)
  - kubectl exec -i with password piped twice via stdin → ✅ CHOSEN
Reason: --force triggers an Administrator password reset with no CLI flag to
        skip or supply it; kubectl exec -i plus a piped answer is the only
        non-interactive workaround. Applies to any future --force install-app
        or similar interactive-prompt bench command run via automation.

## 2026-08-23 — Tier B Command Tests (test.local, frappe-v15)

All commands run via `kubectl exec -n frappe-v15 bench-v15 -- bash -c "cd /home/frappe/bench-data/frappe-bench && <command>"` unless noted.

### B1: uninstall-app — ✅ Pass (fails by design)
```
$ bench --site test.local uninstall-app frappe --no-backup --yes --force
You cannot remove or uninstall the app `frappe`
command terminated with exit code 1
```
Expected: `frappe` is the framework itself — the only app on this site — and Frappe explicitly blocks uninstalling it. Marked **Pass** because the command behaved exactly as documented/intended (a guardrail, not a bug).

### B3: add-system-manager — ✅ Pass
```
$ bench --site test.local add-system-manager sysmanager@test.com --password ***REDACTED***
(no output) — EXIT: 0
```
Silent on success; verified via `bench --site test.local execute frappe.get_roles --args '["sysmanager@test.com"]'` → role list includes `"System Manager"`.

### B4/B5/B6: scheduler pause/resume/enable — ✅ Pass
```
$ bench --site test.local scheduler pause
Scheduler is paused for site test.local
$ bench --site test.local scheduler resume
Scheduler is resumed for site test.local
$ bench --site test.local scheduler enable
Scheduler is enabled for site test.local
```
All three exit 0 with clear confirmation messages.

### B7: set-admin-password — ✅ Pass
```
$ bench --site test.local set-admin-password ***REDACTED***
(no output) — EXIT: 0
```

### B9: execute (get installed apps) — ✅ Pass
```
$ bench --site test.local execute frappe.get_installed_apps
["frappe"]
```

### B11: build-search-index — ⚡ Pass with caveat
```
$ bench --site test.local build-search-index
Building search index for test.local
Retrieving Routes                   : [=                                       ] 3%
EXIT: 0
```
No search-index files found under `sites/test.local/` afterward. `bench doctor` (B19, run later) revealed why: this command **enqueues** a background RQ job (`build_index_for_all_routes`, queue `long`) rather than running synchronously — and confirmed via `bench doctor`: `Workers online: 0`, with that exact job sitting in the backlog. **Modification/caveat: this command only queues work; it needs a running `bench worker` process (not present in this bare test pod) to actually execute.** Not a bug in the command — expected behavior for a pod that only runs `sleep infinity` with no worker processes.

### B14: build (all assets) — ✅ Pass
```
$ bench build
... esbuild bundle output ...
 DONE  Total Build Time: 15.316s
Compiling translations for frappe
... (34 locale .mo files, all up to date) ...
```
Exit 0.

### B15: build --app frappe — ✅ Pass
Same as B14, scoped to the frappe app only. Exit 0, translations compiled.

### B16: setup requirements — ✅ Pass
```
$ bench setup requirements
$ uv pip install --quiet --upgrade pip ...
Installing 1 applications...
Installing frappe
$ uv pip install --quiet -e .../apps/frappe ...
$ yarn install --check-files
success Already up-to-date.
```

### B17: setup requirements --python — ✅ Pass
```
$ bench setup requirements --python
Installing python dependencies for frappe
$ uv pip install --quiet --upgrade-package frappe -e ./apps/frappe ...
```

### B18: setup requirements --node — ✅ Pass
```
$ bench setup requirements --node
Installing node dependencies for frappe
$ yarn install --check-files
success Already up-to-date.
```

### B19: doctor — ✅ Pass (diagnostic; surfaced real findings)
```
$ bench doctor
-----Checking scheduler status-----
Workers online: 0
-----None Jobs-----
Queue: default
Number of Jobs:  4
Methods:
frappe.core.doctype.user.user.create_contact : 4
------------
Queue: long
Number of Jobs:  1
Methods:
<function build_index_for_all_routes at 0x...> : 1
------------
```
Ran successfully and correctly reported the actual state of this pod: no background workers running (expected — the pod only runs `sleep infinity`), 4 queued `create_contact` jobs (side effects of `add-user`/`add-system-manager`), and the 1 queued search-index job from B11. Confirms this is a bench-CLI-only test pod, not a full runtime — background/queued work needs a separate worker deployment to actually process.

### B2: reinstall site — ⚡ Pass with modification
```
$ bench --site test.local reinstall --yes --mariadb-root-username root --mariadb-root-password ***REDACTED***
Warning: MariaDB version ['10.11', '18'] is more than 10.8 which is not yet tested with Frappe Framework.
Installing frappe...
Updating DocTypes for frappe        : [========================================] 100%Warning: Password input may be echoed.
Set Administrator password:
Aborted!
command terminated with exit code 1
```
**Failure cause:** `--yes` only skips the initial "are you sure" confirmation — it does **not** cover the Administrator password prompt when `--admin-password` isn't supplied. No stdin available, so it hit EOF and aborted (same class of issue as A2, but here `bench reinstall --help` confirms an official `--admin-password` flag exists).

**Modification:** added `--admin-password admin123` directly to the command (cleaner than piping stdin, since the flag exists):
```
$ bench --site test.local reinstall --yes --mariadb-root-username root --mariadb-root-password ***REDACTED*** --admin-password ***REDACTED***
...
Updating DocTypes for frappe        : [========================================] 100%
Updating Dashboard for frappe
App frappe already installed
*** Scheduler is disabled ***
```
Exit 0. Verified the site was genuinely wiped and recreated: `testuser@test.com` (added in Tier A) no longer exists post-reinstall.

### Tier B Summary

| ID | Command | Result | Notes |
|---|---|---|---|
| B1 | uninstall-app frappe | ✅ Pass | Fails by design — frappe is the only/core app |
| B3 | add-system-manager | ✅ Pass | Silent success; verified via `get_roles` |
| B4 | scheduler pause | ✅ Pass | — |
| B5 | scheduler resume | ✅ Pass | — |
| B6 | scheduler enable | ✅ Pass | — |
| B7 | set-admin-password | ✅ Pass | Silent success |
| B9 | execute get_installed_apps | ✅ Pass | — |
| B11 | build-search-index | ⚡ Pass with caveat | Only enqueues a background job; needs a worker process to actually run (none in this pod) |
| B14 | build (all assets) | ✅ Pass | — |
| B15 | build --app frappe | ✅ Pass | — |
| B16 | setup requirements | ✅ Pass | — |
| B17 | setup requirements --python | ✅ Pass | — |
| B18 | setup requirements --node | ✅ Pass | — |
| B19 | doctor | ✅ Pass | Confirmed no workers online + the B11 queue backlog |
| B2 | reinstall site | ⚡ Pass with modification | `--yes` doesn't cover the admin-password prompt; added `--admin-password` flag |

**13/15 passed cleanly, 2/15 passed with a modification/caveat (B2, B11).**

## Decision Log (additions)

### D8: bench reinstall admin password
Question: How to run bench reinstall non-interactively when no admin password is given?
Options considered:
  - --yes only → FAILED (still prompts for Administrator password, no stdin, aborts)
  - --admin-password flag → ✅ CHOSEN
Reason: --yes only skips the destructive-action confirmation, not the password
        setup step. --admin-password is a documented flag on `bench reinstall`
        (unlike install-app --force, which has no equivalent) — cleaner than
        piping stdin. Applies to any future automated `bench reinstall` call.

### D9: build-search-index is asynchronous
Question: Does build-search-index index synchronously or in the background?
Finding: It enqueues a job (build_index_for_all_routes) on the "long" RQ queue
         rather than running inline — confirmed via `bench doctor` showing
         0 workers online and that exact job sitting unprocessed.
Implication: In a bare bench-CLI pod (no worker processes), this command will
             always appear to finish instantly without actually indexing
             anything. A real deployment needs a running worker (e.g. a
             `bench worker` Deployment) for this — and other queued jobs like
             contact creation — to actually execute.

## 2026-08-23 — Tier C: Kubernetes-Native Operations

All commands run on the server as `frappe`, `KUBECONFIG=/home/frappe/.kube/config`.

**Pre-check finding:** `frappe-system` has **no Deployments at all** — the Bitnami redis chart deploys `redis-cache-master`/`redis-cache-replicas` (and same for queue/socketio) as **StatefulSets**, even with persistence disabled (Bitnami's chart always uses a StatefulSet for the Redis master, for stable network identity). This meant every command in the C2–C5 spec (`deployment redis-cache`) needed correcting to `statefulset redis-cache-master` before it could work — confirmed via `kubectl get deployments/statefulsets -n frappe-system` and `kubectl get all | grep redis-cache` first.

### C1: create namespace — ✅ Pass
```
$ kubectl create namespace frappe-test-bench
namespace/frappe-test-bench created
```

### C2: rolling restart — ⚡ Pass with modification
```
$ kubectl rollout restart deployment redis-cache -n frappe-system
Error from server (NotFound): deployments.apps "redis-cache" not found
```
**Corrected:**
```
$ kubectl rollout restart statefulset redis-cache-master -n frappe-system
statefulset.apps/redis-cache-master restarted
$ kubectl rollout status statefulset redis-cache-master -n frappe-system --timeout=60s
statefulset rolling update complete 1 pods at revision redis-cache-master-5b89d6db85...
```

### C3: scale down — ⚡ Pass with modification
```
$ kubectl scale deployment redis-cache -n frappe-system --replicas=0
Error from server (NotFound): deployments.apps "redis-cache" not found
```
**Corrected:**
```
$ kubectl scale statefulset redis-cache-master -n frappe-system --replicas=0
statefulset.apps/redis-cache-master scaled
$ kubectl get pods -n frappe-system | grep redis-cache
redis-cache-master-0   1/1   Terminating   0   30s
```
Confirmed fully scaled to 0 shortly after (`grep redis-cache` → no results).

### C4: scale up — ⚡ Pass with modification
```
$ kubectl scale deployment redis-cache -n frappe-system --replicas=1
Error from server (NotFound): deployments.apps "redis-cache" not found
```
**Corrected:**
```
$ kubectl scale statefulset redis-cache-master -n frappe-system --replicas=1
statefulset.apps/redis-cache-master scaled
$ kubectl rollout status statefulset redis-cache-master -n frappe-system --timeout=60s
statefulset rolling update complete 1 pods at revision redis-cache-master-5b89d6db85...
```

### C5: patch resources — ⚡ Pass with modification
Container name in the spec is `redis` — matches what was given, only the resource type/name needed correcting.
```
$ kubectl patch deployment redis-cache -n frappe-system --patch '...'
Error from server (NotFound): deployments.apps "redis-cache" not found
```
**Corrected:**
```
$ kubectl patch statefulset redis-cache-master -n frappe-system --patch '{"spec":{"template":{"spec":{"containers":[{"name":"redis","resources":{"requests":{"memory":"64Mi","cpu":"50m"},"limits":{"memory":"128Mi","cpu":"100m"}}}]}}}}'
statefulset.apps/redis-cache-master patched
$ kubectl rollout status statefulset redis-cache-master -n frappe-system --timeout=60s
statefulset rolling update complete 1 pods at revision redis-cache-master-7d6d6d48fb...
```
Verified applied: `kubectl get pod ... -o jsonpath='{.spec.containers[0].resources}'` →
```
{"limits":{"cpu":"100m","ephemeral-storage":"2Gi","memory":"128Mi"},"requests":{"cpu":"50m","ephemeral-storage":"50Mi","memory":"64Mi"}}
```
(`ephemeral-storage` values come from the chart's default `resourcesPreset`, not this patch — CPU/memory match exactly what was requested.)

### C6: delete namespace — ✅ Pass
```
$ kubectl delete namespace frappe-test-bench
namespace "frappe-test-bench" deleted
$ kubectl get namespace frappe-test-bench
Error from server (NotFound): namespaces "frappe-test-bench" not found
Namespace deleted
```

### C7: create Ingress — ⚡ Pass with caveat
```
$ kubectl apply -f - <<EOF ... EOF
ingress.networking.k8s.io/test-site-ingress created
Warning: annotation "kubernetes.io/ingress.class" is deprecated, please use 'spec.ingressClassName' instead
$ kubectl get ingress -n frappe-v15
NAME                CLASS    HOSTS        ADDRESS     PORTS   AGE
test-site-ingress   <none>   test.local   10.0.0.37   80      0s
```
**Unexpected findings:**
1. `CLASS` shows `<none>` because the legacy `kubernetes.io/ingress.class` annotation doesn't populate `spec.ingressClassName` (hence the deprecation warning) — but `kubectl get ingressclass` confirms `traefik` is the **default** IngressClass in this cluster, so Traefik still picks it up (`Address: 10.0.0.37` confirms it was processed).
2. `kubectl describe ingress` shows the backend as `bench-v15:8000 (<error: services "bench-v15" not found>)` — **the `bench-v15` pod was created directly with no Service in front of it** (back when it was first created for the Tier A/B tests), so this Ingress resource creates fine but is not actually functional yet. A Service would need to be added first for real traffic to reach it.

### C8: delete Ingress — ✅ Pass
```
$ kubectl delete ingress test-site-ingress -n frappe-v15
ingress.networking.k8s.io "test-site-ingress" deleted from frappe-v15 namespace
$ kubectl get ingress -n frappe-v15
No resources found in frappe-v15 namespace.
```

### C9: maintenance-mode annotation — ⚡ Pass with caveat
```
$ kubectl apply -f - <<EOF ... EOF
ingress.networking.k8s.io/test-maintenance-ingress created
$ kubectl get ingress -n frappe-v15 -o yaml | grep -A5 annotations
    annotations:
      kubernetes.io/ingress.class: traefik
      traefik.ingress.kubernetes.io/router.middlewares: |
        frappe-v15-maintenance@kubernetescrd
```
Annotation applied and readable as expected. **Unexpected findings:**
1. The YAML `>` folded-scalar style used for the middleware annotation value adds a trailing newline (visible as `frappe-v15-maintenance@kubernetescrd\n` in `last-applied-configuration`) — cosmetically harmless here, but worth using `|-` or a plain scalar instead in real manifests to avoid a stray newline in an annotation value some parsers might not trim.
2. No Traefik `Middleware` custom resource named `maintenance` exists yet in `frappe-v15` — this annotation references a middleware that doesn't exist, so it would have no actual effect until that CRD is created. Ingress object creation itself doesn't validate that referenced Middleware CRDs exist.

Cleaned up: `kubectl delete ingress test-maintenance-ingress -n frappe-v15` → deleted, confirmed via `kubectl get ingress -n frappe-v15` → no resources.

### Tier C Summary

| ID | Operation | Result | Notes |
|---|---|---|---|
| C1 | create namespace | ✅ Pass | — |
| C2 | rolling restart | ⚡ Pass with modification | `deployment redis-cache` → `statefulset redis-cache-master` |
| C3 | scale down | ⚡ Pass with modification | Same resource-type/name correction |
| C4 | scale up | ⚡ Pass with modification | Same resource-type/name correction |
| C5 | patch resources | ⚡ Pass with modification | Same correction; values verified applied |
| C6 | delete namespace | ✅ Pass | — |
| C7 | create Ingress | ⚡ Pass with caveat | Created fine, but backend Service `bench-v15` doesn't exist |
| C8 | delete Ingress | ✅ Pass | — |
| C9 | maintenance annotation | ⚡ Pass with caveat | Applied fine, but referenced Middleware CRD doesn't exist; YAML folding added trailing newline |

**4/9 passed cleanly, 5/9 passed with a required modification or a caveat worth flagging.** The dominant theme: `frappe-system`'s Redis/MariaDB workloads are StatefulSets, not Deployments (Bitnami chart default), and `frappe-v15`'s bench pod has no Service/Ingress-wiring yet — both are useful groundwork findings for whatever manifests get built next for a real bench deployment.

## Decision Log (additions)

### D10: Redis/MariaDB workload type in frappe-system
Question: Are the shared infra workloads Deployments or StatefulSets?
Finding: All of them (mariadb, redis-cache/queue/socketio master+replicas) are
         StatefulSets — Bitnami's redis chart always uses a StatefulSet for
         the master pod, even with persistence disabled and 0 replicas.
Implication: Any kubectl automation targeting these by name must use
             `statefulset <name>-master`, not `deployment <name>`, and the
             resource name has a `-master` suffix, not the bare release name.

### D11: bench-v15 has no Service yet
Finding: The bench-v15 test pod (created in the Tier A/B setup) was never
         given a Kubernetes Service. An Ingress pointing at it is created
         successfully but non-functional (`<error: services "bench-v15" not
         found>`) until a Service is added.
Implication: A real bench Deployment will need its own Service (and
             Deployment, replacing the bare test Pod) before Ingress/Traefik
             wiring can actually route traffic to it.

## 2026-08-23 — Tier D: Direct MariaDB Operations (D1-D5)

All commands run against `mariadb.frappe-system.svc.cluster.local` via ephemeral `kubectl run --rm -i` pods using `mariadb:10.11`.

### D1: create temp user — ✅ Pass
```
$ kubectl run mariadb-test -n frappe-system --image=mariadb:10.11 --restart=Never --rm -i -- mysql -h mariadb.frappe-system.svc.cluster.local -u root -p*** -e "CREATE USER 'temp_test_user'@'%' IDENTIFIED BY ***; GRANT ALL PRIVILEGES ON *.* TO 'temp_test_user'@'%'; FLUSH PRIVILEGES; SELECT User, Host FROM mysql.user WHERE User='temp_test_user';"
User	Host
temp_test_user	%
```
**Note:** this grants `ALL PRIVILEGES ON *.*` — root-equivalent access from any host (`%`). Fine for a short-lived test user immediately dropped in D2, but worth flagging: not a pattern to reuse for any longer-lived credential.

### D2: drop temp user — ✅ Pass
```
$ kubectl run mariadb-test2 ... -e "DROP USER 'temp_test_user'@'%'; FLUSH PRIVILEGES; SELECT User FROM mysql.user WHERE User='temp_test_user';"
warning: couldn't attach to pod/mariadb-test2, falling back to streaming logs: ...
pod "mariadb-test2" deleted from frappe-system namespace
```
`kubectl run --rm -i` occasionally can't attach in time when the pod finishes very fast (benign race, not a real failure) — so the SELECT output wasn't visible here. Verified independently with a follow-up pod:
```
$ kubectl run mariadb-test2b ... -e "SELECT User, Host FROM mysql.user WHERE User='temp_test_user';"
(no rows)
```
Confirmed dropped.

### D3: database size — ✅ Pass
```
$ kubectl run mariadb-test3 ... -e "SELECT table_schema AS 'Database', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)' FROM information_schema.tables GROUP BY table_schema ORDER BY SUM(data_length + index_length) DESC;"
Database	Size (MB)
mysql	12.44
_9354d31722f40d9e	11.93
information_schema	0.20
sys	0.03
performance_schema	0.00
```
Confirms the actual site database name is `_9354d31722f40d9e` (Frappe's auto-generated hash), not `test_local`.

### D4: list tables — ⚡ Pass with modification
```
$ kubectl run mariadb-test4 ... -e "USE test_local; SHOW TABLES;" 2>/dev/null || mysql -h ... -e "SHOW DATABASES;"
ERROR 1049 (42000) at line 1: Unknown database 'test_local'
pod "mariadb-test4" deleted from frappe-system namespace
bash: line 13: mysql: command not found
```
**Two issues, both anticipated and confirmed before running:**
1. `test_local` isn't a real database — the site is named `test.local` but its MariaDB database is the generated hash `_9354d31722f40d9e` (see D3).
2. The `||` fallback isn't actually inside the pod — `kubectl run ... -- mysql ...` is one complete command; the `2>/dev/null || mysql ...` after it runs as plain shell on the **operator's own shell** (this SSH session on the k3s node), which has no `mysql` client installed (`command not found`). A fallback meant to run inside a container needs to be part of the pod's command (e.g. `sh -c "... || ..."` passed to `--`), not appended outside the `kubectl run` invocation.

**Corrected:** used the real database name directly, in one pod:
```
$ kubectl run mariadb-test4b ... -e "USE _9354d31722f40d9e; SHOW TABLES;"
Tables_in__9354d31722f40d9e
__Auth
__UserSettings
__global_search
tabAbout Us Team Member
tabAccess Log
... (full Frappe framework table set)
```

### D5: optimize tables — ⚡ Pass with modification
```
$ kubectl run mariadb-test5 ... -e "SELECT CONCAT('OPTIMIZE TABLE ', table_schema, '.', table_name, ';') FROM information_schema.tables WHERE table_schema = 'test_local' LIMIT 5;"
(no rows) — EXIT: 0
```
Exit 0, but empty result — same `test_local` vs. actual db name issue as D4, not an error in itself.

**Corrected:**
```
$ kubectl run mariadb-test5b ... -e "... WHERE table_schema = '_9354d31722f40d9e' LIMIT 5;"
CONCAT('OPTIMIZE TABLE ', table_schema, '.', table_name, ';')
OPTIMIZE TABLE _9354d31722f40d9e.tabPackage Release;
OPTIMIZE TABLE _9354d31722f40d9e.tabEmail Group;
OPTIMIZE TABLE _9354d31722f40d9e.tabList Filter;
OPTIMIZE TABLE _9354d31722f40d9e.tabActivity Log;
OPTIMIZE TABLE _9354d31722f40d9e.tabDynamic Link;
```
(Generates the OPTIMIZE statements; doesn't execute them — matches what was actually asked for.)

### Tier D (D1-D5) Summary

| ID | Operation | Result | Notes |
|---|---|---|---|
| D1 | create temp user | ✅ Pass | Grants ALL PRIVILEGES ON *.* — appropriate only for short-lived test creds |
| D2 | drop temp user | ✅ Pass | `kubectl run` attach race hid output; verified independently |
| D3 | database size | ✅ Pass | Revealed real db name `_9354d31722f40d9e` |
| D4 | list tables | ⚡ Pass with modification | Wrong db name assumption + shell `||` fallback runs outside the pod |
| D5 | optimize tables (dry) | ⚡ Pass with modification | Same wrong db name assumption |

### D6: HOLD — command as given cannot do what it says

```
kubectl run mariadb-test6 -n frappe-system --image=mariadb:10.11 --restart=Never --rm -i -- mysql -h mariadb.frappe-system.svc.cluster.local -u root
```

Not run. Three problems, independent of each other:
1. No `-p<password>` — `root` has a password set (confirmed throughout this project), so this would fail auth (or hang waiting on an interactive password prompt with no tty attached).
2. No `-e "<query>"` — nothing to execute.
3. **No `DROP DATABASE` statement anywhere** — despite the step title "Drop a test database," the command as given cannot drop anything.

Dropping a database is irreversible and this MariaDB instance holds the real `_9354d31722f40d9e` (test.local) database alongside `mysql`/`sys`/`information_schema`. Rather than guess a target and write the DROP statement myself, stopping here to confirm the exact database name intended before running anything for D6.

## 2026-08-23 — Tier D: D6 (resolved with user confirmation)

Per user decision: created a throwaway database, dropped it, and verified — rather than guessing a target on real shared infrastructure.

### D6: drop a test database — ✅ Pass (redesigned)
```
$ kubectl run mariadb-test6a ... -e "CREATE DATABASE test_drop_db; SHOW DATABASES LIKE 'test_drop_db';"
Database (test_drop_db)
test_drop_db
```
```
$ kubectl run mariadb-test6 -n frappe-system --image=mariadb:10.11 --restart=Never --rm -i -- mysql -h mariadb.frappe-system.svc.cluster.local -u root -p*** -e "DROP DATABASE test_drop_db;"
EXIT: 0
```
```
$ kubectl run mariadb-test6b ... -e "SHOW DATABASES LIKE 'test_drop_db';"
(no rows) — EXIT: 0
```
Confirmed: database created, verified present, dropped, verified absent. No real data (`mysql`, `sys`, `information_schema`, or the `_9354d31722f40d9e` site database) was touched.

### Tier D Final Summary

| ID | Operation | Result | Notes |
|---|---|---|---|
| D1 | create temp user | ✅ Pass | ALL PRIVILEGES ON *.* — fine for short-lived test creds only |
| D2 | drop temp user | ✅ Pass | Attach race hid output; verified independently |
| D3 | database size | ✅ Pass | Revealed real db name `_9354d31722f40d9e` |
| D4 | list tables | ⚡ Pass with modification | Wrong db name + shell `\|\|` fallback ran outside the pod |
| D5 | optimize tables (dry) | ⚡ Pass with modification | Same wrong db name assumption |
| D6 | drop a test database | ✅ Pass (redesigned) | Original command had no DROP statement, no password, no target db — redesigned as create→verify→drop→verify on a disposable database, per user confirmation |

**5/6 passed cleanly (or with a straightforward correction), 1/6 required stopping to get explicit direction before running anything destructive.**
