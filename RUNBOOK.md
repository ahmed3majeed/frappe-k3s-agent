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
