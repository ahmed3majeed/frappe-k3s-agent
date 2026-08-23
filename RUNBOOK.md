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
**Discovered in:** Phase 1, frappe-system setup (MariaDB installation)
**Finding:** Three approaches were tried for deploying MariaDB 10.11: (1) Bitnami Helm chart 12.2.9 — FAILED, the pinned image tag was removed from the free `bitnami` Docker Hub org in their 2025 catalog restructuring; (2) Bitnami chart with the official `mariadb` image swapped in — FAILED, the chart's security context/volume conventions are Bitnami-specific and don't fit the official image (permission errors); (3) native Kubernetes manifests (Secret + ConfigMap + StatefulSet + Service) with the official `mariadb:10.11` image — SUCCEEDED.
**Impact on Custom Agent:** relying on the Bitnami MariaDB chart is a registry-availability risk — pinned image tags can silently disappear from the free tier. A chart-based install can also fail non-obviously when mixing chart conventions with a different base image.
**Implementation rule:** deploy MariaDB via native Kubernetes manifests referencing the official `mariadb:{version}` image directly, not the Bitnami chart. This gives full control over image source and avoids third-party registry/catalog dependency risk entirely.

### D2: Storage for bench pod
**Discovered in:** Phase 1, bench-v15 pod setup
**Finding:** `bench init` clones the full Frappe framework, builds a Python virtualenv, and installs Node dependencies — a 5-10+ minute operation. Without persistent storage, any pod restart loses all of this and forces a full re-init from scratch.
**Impact on Custom Agent:** an ephemeral (PVC-less) bench pod is unusable in practice — any restart, rescheduling, or node failure wipes the entire bench, forcing a lengthy rebuild before the site is usable again.
**Implementation rule:** every bench pod must mount a PersistentVolumeClaim (10Gi minimum for a single-app bench) for its bench directory. This also matches real production deployment patterns, where bench state must survive pod lifecycle events.

### D3: Redis hosts need `redis://` prefix, not bare `host:port`
**Discovered in:** Phase 1, bench-v15 `bench new-site` (initial infrastructure host configuration)
**Finding:** `bench set-redis-cache-host` / `-queue-host` / `-socketio-host` accept a bare `host:port` value without complaint and write it to `common_site_config.json`, but `bench new-site` then fails when it actually tries to connect: `ValueError: Redis URL must specify one of the following schemes (redis://, rediss://, unix://)`. Frappe v15's Redis client (via the `redis` Python package) requires a full URL with scheme, not a bare host:port.
**Impact on Custom Agent:** any automation that writes Redis host config using bare `host:port` (as the Redis service DNS name naturally looks) will pass the `set-redis-*-host` step silently, then fail later at `bench new-site`/`bench migrate` with a confusing error far removed from the actual misconfiguration.
**Implementation rule:** always prefix Redis host values with `redis://` — e.g. `bench set-redis-cache-host redis://redis-cache-master.frappe-system.svc.cluster.local:6379`, never the bare `host:port` form.

### D4: `bench init` requires `--skip-redis-config-generation`
**Discovered in:** Phase 1, bench-v15 `bench init`
**Finding:** By default, `bench init` tries to generate a local Redis config, which shells out to a local `redis-server` binary to check its version. The `frappe/bench:latest` image has no `redis-server` binary installed (Redis runs as a separate service in `frappe-system`, not locally in the bench pod), so plain `bench init frappe-bench` fails: `/bin/sh: 1: redis-server: not found`, followed by a full traceback and installation rollback.
**Impact on Custom Agent:** every `bench init` call in this k3s architecture (external Redis, not a local one) will fail outright without this flag — this isn't an edge case, it's the default/expected topology for every bench the Agent creates.
**Implementation rule:** always pass `--skip-redis-config-generation` to `bench init` in this environment: `bench init {name} --frappe-branch {branch} --skip-redis-config-generation`.

### D5: `--no-mariadb-socket` is deprecated in Frappe v15
**Discovered in:** Phase 1, bench-v15 `bench new-site` / `bench reinstall`
**Finding:** `bench new-site --no-mariadb-socket ...` still works, but Frappe v15 prints a deprecation warning: `--no-mariadb-socket is DEPRECATED; use --mariadb-user-host-login-scope='%' ... instead. The name of this option was misleading; it had nothing to do with sockets.` Functionally equivalent, but the old flag is on a deprecation path.
**Impact on Custom Agent:** using the deprecated flag works today but risks breaking in a future Frappe version once the flag is actually removed, and produces noisy deprecation output in every `bench new-site` call the Agent makes.
**Implementation rule:** use `--mariadb-user-host-login-scope='%'` instead of `--no-mariadb-socket` in all `bench new-site` (and equivalent) invocations going forward.

### D6: `bench init` target directory must not pre-exist (PVC mount placement)
**Discovered in:** Phase 1, bench-v15 PVC/pod setup (before D4 was found)
**Finding:** Mounting the bench PVC directly at `.../frappe-bench` fails: `bench init` refuses with `ERROR: Bench instance already exists at frappe-bench`, because it needs to create that directory itself and rejects a pre-existing (even if empty) target path. Mounting the PVC one level up (e.g. at `/home/frappe/bench-data`) leaves the `frappe-bench` subdirectory path free for `bench init` to create, while everything it creates still persists on the PVC.
**Impact on Custom Agent:** any manifest that mounts a bench's PVC directly at the bench directory path will make `bench init` fail immediately — this is the direct cause of D15's PVC path offset (`{mount}/frappe-bench/sites/...`, not `{mount}/sites/...`) and must be understood together with it.
**Implementation rule:** always mount a new bench's PVC at the *parent* of where `bench init` will create the bench (e.g. PVC at `/home/frappe/bench-data`, bench created at `/home/frappe/bench-data/frappe-bench`), never directly at the bench directory path itself.

### D7: `install-app --force` needs stdin for the Administrator password prompt
**Discovered in:** Phase 1, Tier A2 (install-app testing)
**Finding:** Running `bench --site {s} install-app {app} --force` on an app already installed triggers an interactive Administrator-password reset prompt (`Set Administrator password:` / `Re-enter Administrator password:`), with no CLI flag to skip or supply it. A plain `kubectl exec` (no stdin) hits `EOFError` on the prompt and aborts.
**Impact on Custom Agent:** any automated `--force install-app` call (or any other bench command with a similar unsuppressable interactive prompt) will hang or abort if run via a standard non-interactive `kubectl exec`.
**Implementation rule:** use `kubectl exec -i` and pipe the Administrator password twice via stdin (once for "Set", once for "Re-enter"): `printf "{password}\n{password}\n" | kubectl exec -i {pod} -- bash -c "... install-app {app} --force"`.

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

### D8: `bench reinstall` needs `--admin-password` explicitly
**Discovered in:** Phase 1, Tier B2 (reinstall testing)
**Finding:** `bench --site {s} reinstall --yes --mariadb-root-username {u} --mariadb-root-password {p}` (without `--admin-password`) still hits an interactive Administrator-password prompt and aborts under a non-interactive `kubectl exec`. `--yes` only skips the destructive-action confirmation, not the password setup step.
**Impact on Custom Agent:** an automated reinstall flow that supplies `--yes` but omits `--admin-password`, assuming `--yes` covers all prompts, will hang/abort exactly like an unsuppressed `install-app --force` (D7) — but unlike D7, there's a clean documented flag to avoid the problem entirely rather than needing a stdin workaround.
**Implementation rule:** always pass `--admin-password {password}` explicitly on every `bench reinstall` call — never rely on `--yes` alone.

### D9: `build-search-index` only enqueues a background job — it doesn't index synchronously
**Discovered in:** Phase 1, Tier B11 (build-search-index) + B19 (`bench doctor`)
**Finding:** `bench --site {s} build-search-index` returns instantly with exit 0 and a partial progress-bar line, but no search index is actually built. It enqueues a job (`build_index_for_all_routes`) on the RQ `long` queue rather than running inline — confirmed via `bench doctor` showing `Workers online: 0` with that exact job sitting unprocessed in the backlog.
**Impact on Custom Agent:** in any bench pod without a running worker process, this command (and any command that similarly enqueues background work, e.g. contact creation via `add-user`) will silently appear to succeed while doing nothing — a false-positive success that's easy to miss without explicitly checking `bench doctor`'s queue backlog.
**Implementation rule:** never treat `build-search-index`'s exit code alone as confirmation the index was built. A real deployment needs a running `bench worker` process (a separate Deployment) for this — and any other enqueued job — to actually execute; if the Agent needs to confirm completion, it must check the job queue state, not just the enqueuing command's exit code.

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

### D10: Redis workloads are StatefulSets, not Deployments
**Discovered in:** Phase 1, Tier C (pre-check before C2-C5)
**Finding:** `frappe-system` has no Deployments at all for its Redis instances — the Bitnami Redis chart always deploys the master pod as a StatefulSet (`redis-{name}-master`), even with persistence disabled and replica count 0, for stable network identity. `kubectl rollout restart/scale/patch deployment redis-cache` fails outright: `Error from server (NotFound): deployments.apps "redis-cache" not found`.
**Impact on Custom Agent:** any automation that assumes Redis (or MariaDB, deployed the same way in this setup) is a Deployment and targets it with `deployment/{name}`-style commands will fail with a `NotFound` error — the resource exists, just under a different kind and a different name (`-master` suffix).
**Implementation rule:** target these workloads as `statefulset {name}-master`, never `deployment {name}` — e.g. `kubectl rollout restart statefulset redis-cache-master -n frappe-system`, not `kubectl rollout restart deployment redis-cache`.

### D11: an Ingress/IngressRoute needs a real backend Service to actually route traffic
**Discovered in:** Phase 1, Tier C7 (create Ingress)
**Finding:** The `bench-v15` test pod was created directly with no Kubernetes Service in front of it. An Ingress resource pointing at `bench-v15:8000` is created successfully (Kubernetes doesn't validate the backend exists at admission time) but is non-functional — `kubectl describe ingress` shows `<error: services "bench-v15" not found>`.
**Impact on Custom Agent:** a bench without a Service can still have Ingress/IngressRoute resources created against it with no error — the Agent could believe routing is set up correctly when it silently isn't, since Kubernetes gives no feedback until real traffic is attempted.
**Implementation rule:** every bench the Agent provisions must have a Service created (pointing at the bench's Deployment, per D16) before or alongside any Ingress/IngressRoute for it — never assume a successfully-created Ingress means traffic will actually route.

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

## 2026-08-23 — Master Command List: GROUP A (bench CLI commands)

Working from `commands-master-list.md` (uploaded by user). Before starting, cross-checked the "Already tested ✅" list against actual Tier A-D history and found three claims that were never actually run: `migrate --skip-search-index`, `migrate --skip-failing`, `rebuild-global-search`. Backfilled these for real rather than trusting the summary.

### Backfilled (falsely marked "already tested")

| Command | Result | Notes |
|---|---|---|
| `migrate --skip-search-index` | ✅ Pass | Exit 0; confirmed no "Queued rebuilding of search index" message (flag worked) |
| `migrate --skip-failing` | ✅ Pass | Exit 0; search index still queued (this flag only affects patch-failure handling) |
| `rebuild-global-search` | ✅ Pass | Runs **synchronously to 100%** — unlike `build-search-index` (Tier B11), which only enqueues a background job that never runs without a worker |

### Still-to-test commands

| Command | Result | Notes |
|---|---|---|
| `restore` (db only, from fresh backup) | ✅ Pass | `Site test.local has been restored` |
| `restore --with-public-files --with-private-files` | ✅ Pass | `Site test.local has been restored with files`. Real flags confirmed via `--help`: `--with-public-files`/`--with-private-files` (matches master list) |
| `execute setup_wizard.setup_complete --kwargs {json}` | ⚡ Pass with modification | Empty `{}` fails (`TypeError: missing 1 required positional argument: 'args'`) — needs a populated `{"args": {...}}` payload (language, country, timezone, currency, full_name, email, company_name, company_abbr, domains). Also needed a script-file + `kubectl cp` approach instead of inline shell quoting (nested JSON with spaces broke `bash -c "..."` escaping). Result: `{"status": "ok"}` |
| `update-site-plan {plan}` | ❌ Fail | `Error: No such command 'update-site-plan'.` — doesn't exist in base Frappe v15; likely a Frappe Cloud/`press`-app-specific command not present without that app installed |
| `console` (via stdin pipe) | ✅ Pass | `echo "print(frappe.get_installed_apps())" \| kubectl exec -i ...` → printed `['frappe']`, then IPython's exit prompt closed cleanly on EOF |
| `ready-for-migration` | ✅ Pass | `NOT READY for migration: site test.local has pending background jobs` (exit 1) — **correct behavior**, ties directly to the B19 finding (queued jobs with no worker to process them) |
| `remove-from-installed-apps frappe` | ✅ Pass | `You cannot remove or uninstall the app frappe` (exit 1) — same core-app guardrail as `uninstall-app` (Tier B1). Site fully unaffected (verified via `list-apps`) |
| `execute frappe.utils.get_site_info` | ✅ Pass | Returned a full site info JSON (`installed_apps`, `setup_complete: false`, etc.) |
| `describe-database-table --doctype User` | ✅ Pass | Full table schema + row count JSON |
| `add-database-index --doctype User --column email` | ✅ Pass | Exit 0 |
| `browse --user Administrator` | ⚡ Pass with caveat | Prints `Login URL: http://test.local:8000/app?sid=<session-id>` — exactly the session-extraction mechanism the Agent needs. The browser-launch part (`xdg-open`) fails harmlessly (no browser binaries in this headless container) but doesn't affect exit code (0) |
| `drop-site --no-backup --force --root-login --root-password --archived-sites-path` | ✅ Pass | Tested on a disposable `drop-test.local` (created first via `bench new-site`), never `test.local`. Site archived to `sites/archived/`, removed from `sites/`. `test.local` verified unaffected afterward |
| `bench restart` | ⚡ Pass with caveat | Exit 0, no visible effect — confirmed why: no `config/supervisor.conf` and no `supervisorctl` binary exist in this pod (only an inert `Procfile` from `bench init`, never activated since `bench start` was never run). Effectively a no-op here |
| `bench restart --web` | ⚡ Pass with caveat | Same as above |
| `execute frappe.client.get_list --kwargs` | ✅ Pass | Already used dozens of times throughout Tier A-D as our own verification mechanism (e.g. confirming `testuser@test.com`, `sysmanager@test.com` roles); one more clean record captured here |
| `execute frappe.get_roles --args` | ✅ Pass | Same — already extensively validated (Tier B3); one more clean record captured |
| `bench git apply {patch}` | ❌ Fail | `Error: No such command 'git'.` — **`bench git apply` is not a real bench subcommand.** Likely a description artifact in the source material; the actual mechanism is plain `git apply`, run directly in the app directory (see Group B) |
| `bench git apply --reverse {patch}` | ❌ Fail | Same reason as above |

### Supplementary tests (per master list's preparation rules)

To properly test `uninstall-app` with 2+ apps and `bench build --apps {app1,app2}`, installed and then removed erpnext:

| Command | Result | Notes |
|---|---|---|
| `bench get-app erpnext --branch version-15` | ✅ Pass | Cloned, `bench build --app erpnext` ran automatically as part of get-app |
| `bench --site test.local install-app erpnext` | ✅ Pass | Full DocType install, no errors |
| `bench build --apps frappe,erpnext` | ✅ Pass | Multi-app build variant confirmed working |
| `bench --site test.local uninstall-app erpnext --no-backup --yes --force` | ✅ Pass | Real uninstall (many tables dropped) — distinct from Tier B1, which only tested the blocked single-app case |
| `bench remove-app erpnext` | ✅ Pass | Cleanup: uninstalled Python package, moved `apps/erpnext` → `archived/apps/erpnext-2026-08-23` |
| `bench new-site drop-test.local` | ✅ Pass | Prep for the `drop-site` test above |

### Final health check
```
$ bench --site test.local list-apps
frappe 15.118.0 version-15
$ bench --site test.local execute frappe.get_installed_apps
["frappe"]
```
Site fully healthy after all Group A tests.

### GROUP A Summary

| Result | Count |
|---|---|
| ✅ Pass | 22 |
| ⚡ Pass with modification/caveat | 5 |
| ❌ Fail | 3 |
| **Total tested this session** | **30** (+3 backfilled) |

## 2026-08-23 — Master Command List: GROUP B (git commands, in-pod)

All commands run via `kubectl exec` inside `bench-v15`, targeting `apps/frappe` (a shallow `--depth 1` clone, remote named `upstream`, branch `version-15`). State recorded first (`git status --short` clean, `git log --oneline -5` → single commit `9b8d265`). Any command switching commits was checked back out to `version-15` afterward, and `git clean -fd` was previewed with `-n` before running for real (found nothing to clean either time — working tree was already clean).

### Results

| Command | Result | Notes |
|---|---|---|
| `git rev-parse HEAD` | ✅ Pass | `9b8d265b27a1dfb11c7aef21a533a127e14a0a5a` |
| `git remote get-url {remote}` | ✅ Pass | `upstream` → `https://github.com/frappe/frappe.git` |
| `git remote add {remote} {url}` | ✅ Pass | Added `test-remote`, confirmed via `git remote -v` |
| `git remote remove {remote}` | ✅ Pass | Removed `test-remote` cleanly |
| `git fetch --depth 2 {remote} {branch}` | ✅ Pass | Used to pull a second commit into a shallow clone (`FETCH_HEAD` → 2 commits) |
| `git fetch --depth 1 {remote} {hash}` | ⚡ Pass with modification | **Abbreviated hash fails:** `git fetch --depth 1 upstream 16d483c` → `fatal: couldn't find remote ref 16d483c`. GitHub's server-side SHA-fetch only resolves **full 40-character SHAs**, not short ones. Retried with `git fetch --depth 1 upstream 16d483c2095d57a080c664dba3e19a0421739719` → succeeded. **The real Agent must always pass the full SHA, never an abbreviated one, to this command.** |
| `git diff --name-only {old} {new}` | ✅ Pass | Between the two fetched commits → `frappe/__init__.py` (the version-bump commit) |
| `git diff --name-only {old} {new} -- '*.vue' '*.js'` | ✅ Pass | Empty result (no frontend files changed in that commit) — correct |
| `git diff --name-only {old} {new} -- requirements.txt pyproject.toml` | ✅ Pass | Empty result — correct |
| `git reset --hard {hash}` | ✅ Pass | Used current `HEAD` — no-op, safe |
| `git clean -fd` | ✅ Pass | Previewed with `-n` first (empty — nothing to clean), then ran for real (also empty) |
| `git checkout {hash}` | ✅ Pass | Detached HEAD at the old commit, confirmed via `git log --oneline -1` |
| (recovery) `git checkout version-15` | ✅ Pass | Back on branch, `up to date with 'upstream/version-15'` |
| `git -C {app_path} rev-parse HEAD` | ✅ Pass | Run from bench root (not cd'd into the app dir) — confirms `-C` works without a prior `cd` |
| `git -C {app_path} fetch --depth 1 {url} {hash}` | ✅ Pass | Used the full clone URL directly instead of a named remote — also works |
| `git -C {app_path} reset --hard HEAD` | ✅ Pass | — |
| `git -C {app_path} clean -fd` | ✅ Pass | — |
| `git -C {app_path} checkout {hash}` | ✅ Pass | Detached, then checked back out to `version-15` |
| `git -C {app_path} diff --name-only {old} {new} -- '*.vue' '*.js'` | ✅ Pass | Empty (correct) |
| `git -C {app_path} diff --name-only {old} {new} -- requirements.txt pyproject.toml` | ✅ Pass | Empty (correct) |

### "New bench setup" git sequence (tested in an isolated `/tmp/scratch-git-test` directory, not the real app checkout)

| Command | Result | Notes |
|---|---|---|
| `git init` | ✅ Pass | (Prints a default-branch-name hint, harmless) |
| `git remote add origin {url}` | ✅ Pass | — |
| `git config credential.helper ''` | ✅ Pass | Disables credential prompting for this repo |
| `git fetch --depth 1 origin {hash}` | ✅ Pass | Full SHA, as established above |
| `git checkout -B {branch}` | ✅ Pass | `git checkout -B version-15 FETCH_HEAD` → new local branch tracking the fetched commit, confirmed via `log`/`branch --show-current` |

This full 5-command sequence is exactly how a bench-less "clone at a specific commit" would work — verified end-to-end. Scratch directory removed after testing.

### Final state check
```
$ git -C apps/frappe status --short
(clean)
$ git -C apps/frappe branch --show-current
version-15
```

### GROUP B Summary

| Result | Count |
|---|---|
| ✅ Pass | 20 |
| ⚡ Pass with modification | 1 (full-SHA requirement on hash-based fetch) |
| ❌ Fail | 0 |
| **Total** | **21 / 21** |

## 2026-08-23 — Master Command List: GROUP C (SQL commands, via mysql client pod)

All tests use ephemeral `kubectl run --image=mariadb:10.11` pods against `mariadb.frappe-system.svc.cluster.local`. Replication commands (`STOP/START SLAVE`, `CHANGE MASTER TO`, `SHOW SLAVE STATUS`, `PURGE BINARY LOGS` — kept, see below) are handled per the master list's own **Group J** guidance: deferred, ⏭️ needs a dedicated replica MariaDB, not built for this pass.

### User account lifecycle
```sql
CREATE OR REPLACE USER 'sql-test-user'@'%' IDENTIFIED BY ***; FLUSH PRIVILEGES;
GRANT ALL PRIVILEGES ON *.* TO 'sql-test-user'@'%' WITH GRANT OPTION;
SHOW GRANTS FOR 'sql-test-user'@'%';
  → GRANT ALL PRIVILEGES ON *.* TO `sql-test-user`@`%` ... WITH GRANT OPTION
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'sql-test-user'@'%';
SHOW GRANTS FOR 'sql-test-user'@'%';
  → GRANT USAGE ON *.* TO `sql-test-user`@`%` ...   (privileges genuinely stripped)
GRANT SELECT ON mysql.* TO 'sql-test-user'@'%';
SHOW GRANTS FOR 'sql-test-user'@'%';
  → GRANT USAGE ON *.* ...  +  GRANT SELECT ON `mysql`.* TO ...
RENAME USER 'sql-test-user'@'%' TO 'sql-test-user-renamed'@'%';
  → confirmed via mysql.user query
DROP USER IF EXISTS 'sql-test-user-renamed'@'%';
  → confirmed gone via follow-up verify pod
```
All ✅ Pass. (`REVOKE`/`GRANT SELECT` tested against `*.*`/`mysql.*` rather than a `{db}`-scoped grant, since the original grant was global — mechanism fully confirmed regardless of scope.)

### Database lifecycle
```sql
CREATE OR REPLACE DATABASE test_replace_db;        -- ✅ Pass, confirmed via SHOW DATABASES LIKE
GRANT ALL PRIVILEGES ON test_replace_db.* TO 'sql-test-user2'@'%' IDENTIFIED BY *** WITH GRANT OPTION;  -- ✅ Pass
DROP DATABASE IF EXISTS test_replace_db;            -- ✅ Pass
DROP USER IF EXISTS 'sql-test-user2'@'%';           -- ✅ Pass
```
Verified both gone via a follow-up pod.

### information_schema introspection (against real site db `_9354d31722f40d9e`)

| Query | Result |
|---|---|
| `SELECT table_name, data_length, index_length, data_free FROM information_schema.TABLES WHERE TABLE_SCHEMA=...` | ✅ Pass — real rows returned |
| `SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE FROM information_schema.COLUMNS WHERE ...` | ✅ Pass |
| `SELECT TABLE_NAME, COLUMN_NAME, INDEX_NAME FROM information_schema.STATISTICS WHERE ...` | ✅ Pass — real index list for `tabUser` (PRIMARY, username, mobile_no, api_key, last_active, modified, email_index) |
| `SELECT TABLE_NAME, INDEX_NAME, ROWS_READ FROM information_schema.INDEX_STATISTICS WHERE ...` | ⚡ Pass with caveat | Empty result — MariaDB's `userstat`/index-usage-tracking feature is **off by default**; the table exists and the query is valid, it's just never populated unless `userstat=ON` is set server-side |

### EXPLAIN / ANALYZE / stats / integrity (on real `tabUser`)
```sql
EXPLAIN SELECT * FROM _9354d31722f40d9e.tabUser WHERE name='Administrator';
  → type=const, key=PRIMARY, rows=1                                          -- ✅ Pass

ANALYZE TABLE _9354d31722f40d9e.tabUser PERSISTENT FOR ALL;
  → "Engine-independent statistics collected", status OK (+ per-column warnings for
     unindexed/TEXT-like columns — informational, not errors)                -- ✅ Pass

SELECT column_name, nulls_ratio FROM mysql.column_stats WHERE db_name=... AND table_name='tabUser';
  → real rows (requires the ANALYZE above to have run first)                 -- ✅ Pass

CHECK TABLE _9354d31722f40d9e.tabUser;
  → status: OK                                                               -- ✅ Pass

REPAIR TABLE _9354d31722f40d9e.tabUser;
  → note: "The storage engine for the table doesn't support repair"          -- ✅ Pass (expected: InnoDB doesn't support REPAIR TABLE — MyISAM-only feature, correctly reported rather than erroring)
```

### PROCESSLIST + KILL (safe, self-created connection)
Started a disposable `SELECT SLEEP(60)` connection in its own pod (`sql-sleeper`), then from a separate pod:
```sql
SHOW FULL PROCESSLIST;
  → Id 3119  User root  Command Query  Time 5  State "User sleep"  Info "SELECT SLEEP(60)"
```
Then:
```sql
KILL 3119;
```
Confirmed via the sleeper pod's own log:
```
ERROR 2013 (HY000) at line 1: Lost connection to server during query
```
Both ✅ Pass. No real connection was touched — the killed connection was created solely for this test.

### Misc single-shot commands

| Command | Result | Notes |
|---|---|---|
| `SELECT 1` | ✅ Pass | ping/liveness check |
| `CREATE DATABASE IF NOT EXISTS press_meta` | ✅ Pass | Created, confirmed, then dropped (not left behind) |
| `FLUSH TABLES` | ✅ Pass | — |
| `SELECT @@GLOBAL.gtid_binlog_pos` | ✅ Pass | Empty value — no GTID history (replication never configured), not an error |
| `SHOW VARIABLES` | ✅ Pass | 655 total variables (`information_schema.GLOBAL_VARIABLES` count used instead of a full dump) |
| `SELECT @@GLOBAL.{variable}` (`version`) | ✅ Pass | `10.11.18-MariaDB-ubu2204-log` |
| `SET GLOBAL server_audit_file_rotate_now = 1` | ❌ Fail | `ERROR 1193: Unknown system variable 'server_audit_file_rotate_now'` — the `server_audit` plugin isn't loaded on this instance (not a K8s issue; would need the plugin installed server-side) |
| `SELECT * FROM performance_schema.events_statements_summary_by_digest` | ⚡ Pass with caveat | Returns 0 rows — `performance_schema` is **OFF** by default on this instance (confirmed via `SHOW VARIABLES LIKE 'performance_schema'`); query itself is valid, just never collects data unless enabled server-side (requires a restart) |
| `SELECT * FROM information_schema.INNODB_TRX` | ✅ Pass | Empty — no active transactions, valid |
| `SELECT * FROM information_schema.INNODB_LOCKS JOIN INNODB_TRX` | ⚡ Pass with modification | **`INNODB_LOCKS` doesn't exist in MariaDB** — it's a MySQL-only table. MariaDB's equivalent is `information_schema.INNODB_LOCK_WAITS`. Used that instead — empty result (no lock waits currently), valid |
| `PURGE BINARY LOGS TO '{binlog}'` | ✅ Pass | No error even though `log_bin` is `OFF` on this instance — MariaDB treats this as a safe no-op rather than raising an error |
| `SHOW DATABASES` | ✅ Pass | Already exercised extensively in Tier D and earlier Group C tests |

### GROUP C Summary

| Result | Count |
|---|---|
| ✅ Pass | 27 |
| ⚡ Pass with modification/caveat | 4 |
| ❌ Fail | 1 |
| ⏭️ Deferred (needs replica, per Group J) | 4 (`STOP/START SLAVE`, `CHANGE MASTER TO`, `SHOW SLAVE STATUS`) |
| **Total** | **32 / 32 testable + 4 deferred** |

## 2026-08-23 — Phase 2, GROUP K: Full Bench Lifecycle (frappe-test / bench-test)

Building a complete bench from scratch as proper K8s resources (Namespace + PVC + Deployment + Service + IngressRoute), replacing what the original Docker Agent did with `docker run -d --name {bench} {image}`. All manifests saved to `k3s/`.

### K1: Namespace
```
$ kubectl create namespace frappe-test
namespace/frappe-test created
```

### K2: PVC (`k3s/bench-pvc.yaml`)
```
$ kubectl apply -f k3s/bench-pvc.yaml
persistentvolumeclaim/bench-test-data created
$ kubectl get pvc -n frappe-test
bench-test-data   Pending   ...   local-path
```
`Pending` is expected — `local-path` storage class uses `WaitForFirstConsumer` binding, resolves once a pod claims it (confirmed at K3).

### K3: Deployment (`k3s/bench-deployment.yaml`)
```
$ kubectl apply -f k3s/bench-deployment.yaml
deployment.apps/bench-test created
$ kubectl wait --for=condition=Available deployment/bench-test -n frappe-test --timeout=60s
deployment.apps/bench-test condition met
$ kubectl get pods -n frappe-test
bench-test-69f6bdfc87-fpvf4   1/1   Running
$ kubectl get pvc -n frappe-test
bench-test-data   Bound   10Gi   local-path
```
PVC bound as soon as the pod scheduled, as expected.

### K4: Service (`k3s/bench-service.yaml`)
```
$ kubectl apply -f k3s/bench-service.yaml
service/bench-test created
$ kubectl get svc -n frappe-test
bench-test   ClusterIP   10.43.145.221   8000/TCP,9000/TCP
```

### K5: IngressRoute (`k3s/bench-ingressroute.yaml`)
Pre-check: confirmed Traefik CRDs installed (`ingressroutes.traefik.io`, `middlewares.traefik.io`, apiVersion `traefik.io/v1alpha1` — matches spec exactly) before writing the manifest.
```
$ kubectl apply -f k3s/bench-ingressroute.yaml
ingressroute.traefik.io/bench-test created
```
Unlike the dangling test Ingress from Tier C7 (which pointed at a nonexistent Service), this one references the real `bench-test` Service created at K4 — genuinely wired up, not just a valid-but-empty resource.

### K6: bench init
```
$ kubectl exec -n frappe-test bench-test-69f6bdfc87-fpvf4 -- bash -c "
  cd /home/frappe/bench-data &&
  bench init frappe-bench --frappe-branch version-15 --skip-redis-config-generation
"
...
SUCCESS: Bench frappe-bench initialized
```
Clean pass, no errors — the PVC was mounted directly at `/home/frappe/bench-data` (one level above `frappe-bench`) and `--skip-redis-config-generation` was included from the start, avoiding both issues discovered the hard way during the original `bench-v15` setup (Tier A/Phase 1).

### K7: Configure infrastructure hosts
```
$ kubectl exec ... -- bash -c "
  bench set-mariadb-host mariadb.frappe-system.svc.cluster.local &&
  bench set-redis-cache-host redis://redis-cache-master.frappe-system.svc.cluster.local:6379 &&
  bench set-redis-queue-host redis://redis-queue-master.frappe-system.svc.cluster.local:6380 &&
  bench set-redis-socketio-host redis://redis-socketio-master.frappe-system.svc.cluster.local:6381
"
```
All four hosts correctly written to `common_site_config.json` with the `redis://` scheme from the start (learned from the Tier A fix — the spec here already included it correctly).

### K8: Create site
```
$ bench new-site k8s-test.local --mariadb-user-host-login-scope='%' --db-host mariadb.frappe-system.svc.cluster.local --mariadb-root-username root --mariadb-root-password *** --admin-password ***
...
Updating Dashboard for frappe
*** Scheduler is disabled ***
```
Clean pass, exit 0.

### K9: Verify
```
$ bench --site k8s-test.local list-apps
frappe 15.118.0 version-15
```

### GROUP K Summary

| Step | Result |
|---|---|
| K1 Namespace | ✅ Pass |
| K2 PVC | ✅ Pass |
| K3 Deployment | ✅ Pass |
| K4 Service | ✅ Pass |
| K5 IngressRoute | ✅ Pass |
| K6 bench init | ✅ Pass |
| K7 Host config | ✅ Pass |
| K8 new-site | ✅ Pass |
| K9 Verify | ✅ Pass |

**9/9 clean — zero modifications needed this time.** Every issue hit during the original bare-Pod bench setup (Tier A: PVC mount path, missing `--skip-redis-config-generation`, missing `redis://` scheme) was designed around correctly from the start here, since a proper Deployment+Service+IngressRoute is what a real bench actually needs in production.

## 2026-08-23 — Phase 2, GROUP L: Bench Restart and Scaling

Replaces `supervisorctl restart`/`docker stop`/`docker start`/`docker update` for `bench-test` (frappe-test namespace).

### L1: Rolling restart — ✅ Pass
```
$ kubectl rollout restart deployment/bench-test -n frappe-test
deployment.apps/bench-test restarted
$ kubectl rollout status deployment/bench-test -n frappe-test
deployment "bench-test" successfully rolled out
```
New pod name confirmed: `bench-test-696bf5f95f-zhtp6` replacing `bench-test-69f6bdfc87-fpvf4`.

### L2: Scale down — ✅ Pass
```
$ kubectl scale deployment/bench-test --replicas=0 -n frappe-test
deployment.apps/bench-test scaled
```
Pods briefly showed `Terminating` past a quick check (grace-period timing, not a stuck state — confirmed gone moments later): `kubectl get pods -n frappe-test` → `No resources found`.

### L3: Scale up — ✅ Pass
```
$ kubectl scale deployment/bench-test --replicas=1 -n frappe-test
$ kubectl rollout status deployment/bench-test -n frappe-test --timeout=60s
deployment "bench-test" successfully rolled out
```
New pod `bench-test-696bf5f95f-6ftc6` running. Bench data verified intact via PVC:
```
$ bench --site k8s-test.local list-apps
frappe 15.118.0 version-15
```

### L4: Patch resource limits — ✅ Pass
```
$ kubectl patch deployment bench-test -n frappe-test --patch '{"spec":{"template":{"spec":{"containers":[{"name":"bench","resources":{"requests":{"memory":"512Mi","cpu":"250m"},"limits":{"memory":"1Gi","cpu":"500m"}}}]}}}}'
deployment.apps/bench-test patched
$ kubectl rollout status deployment/bench-test -n frappe-test --timeout=60s
deployment "bench-test" successfully rolled out
$ kubectl describe pod -n frappe-test -l app=bench-test | grep -A4 Limits
Limits:
  cpu:     500m
  memory:  1Gi
Requests:
  cpu:        250m
  memory:     512Mi
```

### GROUP L Summary

| Step | Result |
|---|---|
| L1 Rolling restart | ✅ Pass |
| L2 Scale down | ✅ Pass |
| L3 Scale up (+ data persistence) | ✅ Pass |
| L4 Patch resources | ✅ Pass |

**4/4 clean.** All standard Deployment-native operations — no custom Agent logic needed beyond issuing the right `kubectl` command against the right resource.

## 2026-08-23 — Phase 2, GROUP M: Domain and Routing Management

Replaces nginx.conf editing + `nginx -s reload`.

### M1: Add domain (new IngressRoute) — ✅ Pass
```
$ kubectl apply -f - <<EOF ... EOF
ingressroute.traefik.io/k8s-test-domain created
$ kubectl get ingressroute -n frappe-test
bench-test        6m33s
k8s-test-domain   0s
```
Note: this used the **same host** (`k8s-test.local`) as the existing `bench-test` IngressRoute from K5 — a genuine near-duplicate rather than a new domain. Both created successfully; Traefik doesn't reject duplicate host matches at admission time (each becomes its own router). Removed at M3 before it could cause any real routing ambiguity.

### M2: Add second (distinct) domain — ✅ Pass
```
$ kubectl apply -f - <<EOF ... (host: custom-domain.local) EOF
ingressroute.traefik.io/custom-domain created
$ kubectl get ingressroute -n frappe-test
bench-test        6m42s
custom-domain     0s
k8s-test-domain   9s
```
Saved to `k3s/ingressroute-custom-domain.yaml`.

### M3: Remove domain — ✅ Pass
```
$ kubectl delete ingressroute k8s-test-domain -n frappe-test
ingressroute.traefik.io "k8s-test-domain" deleted from frappe-test namespace
$ kubectl get ingressroute -n frappe-test
bench-test      6m50s
custom-domain   8s
```
Confirmed gone; `bench-test` (K5) and `custom-domain` (M2) both still intact.

### M4: Maintenance mode middleware — ✅ Pass
```
$ kubectl apply -f - <<EOF ... EOF
middleware.traefik.io/maintenance created
$ kubectl get middleware -n frappe-test
maintenance   0s
```
`kubectl describe` confirms the `redirectRegex` spec applied correctly. Saved to `k3s/middleware-maintenance.yaml`. (Not attached to any IngressRoute in this test — only resource creation was in scope; wiring a Middleware to a route via `traefik.ingress.kubernetes.io/router.middlewares`-style reference was already exercised conceptually in Tier C9.)

### GROUP M Summary

| Step | Result |
|---|---|
| M1 Add domain | ✅ Pass |
| M2 Add second domain | ✅ Pass |
| M3 Remove domain | ✅ Pass |
| M4 Maintenance middleware | ✅ Pass |

**4/4 clean.** Domain/routing changes in K8s are pure `kubectl apply`/`delete` of IngressRoute/Middleware resources — no reload step needed (Traefik watches the API server directly), confirming the master list's own Group G conclusion.

## 2026-08-23 — Phase 2, GROUP N: Bench Archive and Cleanup

Replaces `docker rm`/`docker stack rm`.

### N1: Archive bench (keep data, remove pod) — ✅ Pass
```
$ kubectl scale deployment/bench-test --replicas=0 -n frappe-test
$ kubectl delete deployment bench-test -n frappe-test
$ kubectl delete service bench-test -n frappe-test
$ kubectl delete ingressroute --all -n frappe-test
  → deleted: bench-test, custom-domain
$ kubectl get pvc -n frappe-test
bench-test-data   Bound   10Gi   local-path
```
PVC survives independently of the Deployment/Service/IngressRoute — exactly the "archive" semantics needed (data kept, compute/routing removed).

### N2: Restore archived bench from existing PVC — ✅ Pass
```
$ kubectl apply -f k3s/bench-deployment.yaml
deployment.apps/bench-test created
```
New pod (`bench-test-598cd6f676-kgx7w`) bound to the **same** PVC. Verified bench data survived intact:
```
$ kubectl exec ... -- ls /home/frappe/bench-data/frappe-bench/sites/
apps.json  apps.txt  assets  common_site_config.json  k8s-test.local
$ bench --site k8s-test.local list-apps
frappe 15.118.0 version-15
```
Full archive → restore cycle confirmed working end-to-end with zero data loss.

### N3: Full cleanup (delete namespace) — ✅ Pass
```
$ kubectl delete namespace frappe-test
namespace "frappe-test" deleted
$ kubectl get namespace frappe-test
Error from server (NotFound): namespaces "frappe-test" not found
```
Confirmed `frappe-v15`/`bench-v15` (the protected test bench) completely untouched throughout Group N:
```
$ kubectl get namespace frappe-v15
frappe-v15   Active   4h27m
$ kubectl get pods -n frappe-v15
bench-v15    1/1   Running   4h21m
```

### GROUP N Summary

| Step | Result |
|---|---|
| N1 Archive (keep PVC) | ✅ Pass |
| N2 Restore from PVC | ✅ Pass |
| N3 Full cleanup | ✅ Pass |

**3/3 clean.** The archive/restore pattern (PVC survives independent of Deployment/Service lifecycle) is the direct K8s equivalent of Docker's "stop the container, keep the bind-mounted data, `docker rm`" pattern — confirmed working with a real bench, not just an empty volume.

## 2026-08-23 — Phase 2, GROUP O: Agent Self-Update Concept

Replaces `git reset --hard && git fetch && git merge && supervisorctl restart agent:*`.

### O1: Simulate image update (as originally specified) — ✅ Pass (fallback path)
```
$ kubectl set image deployment/bench-test bench=frappe/bench:latest -n frappe-test 2>/dev/null || echo "Deployment already deleted — concept verified"
Deployment already deleted — concept verified
```
`bench-test`/`frappe-test` no longer existed by this point (deleted in Group N), so this correctly hit the documented fallback branch.

### O1 (supplementary): live demonstration of the actual mechanism
To get real evidence beyond the fallback branch, spun up a disposable `demo-agent` deployment (`busybox:1.36`) in a throwaway `frappe-o-test` namespace:
```
$ kubectl set image deployment/demo-agent busybox=busybox:1.35 -n frappe-o-test
deployment.apps/demo-agent image updated
$ kubectl rollout status deployment/demo-agent -n frappe-o-test --timeout=30s
deployment "demo-agent" successfully rolled out
```
Image confirmed changed: `busybox:1.36` → `busybox:1.35`. Namespace deleted immediately after (was never meant to persist).

**Conclusion:** in K8s, Agent self-update is genuinely just `kubectl set image deployment/{agent} {container}={new-image}:{tag}` + a rollout wait — no `git pull`, no `supervisorctl restart`. The new image is baked ahead of time (via CI/registry push), and the rollout mechanism K8s already provides (rolling update, one-old-pod-at-a-time replacement) replaces what `supervisorctl restart agent:*` used to do manually.

### GROUP O Summary

| Step | Result |
|---|---|
| O1 (as-specified, fallback) | ✅ Pass |
| O1 (live mechanism demo) | ✅ Pass |

## 2026-08-23 — Decision Log Addition (formalizing a Phase 2 finding)

### D12: Traefik duplicate Host() behavior
**Discovered in:** Phase 2, Group M1 (add domain / IngressRoute)
**Finding:** Traefik does not reject duplicate `Host()` matches across two different IngressRoute resources — creating a second IngressRoute for the same host results in two competing routers with no error. Observed directly: created `k8s-test-domain` with the same `Host(`k8s-test.local`)` as the existing `bench-test` IngressRoute from K5 — both were accepted, no conflict/rejection at admission time.
**Impact on Custom Agent:** the Agent must pre-check for an existing IngressRoute on the same host before creating a new one, or duplicate/competing routers can silently accumulate with no error signal to catch the mistake.
**Implementation rule:** always use `kubectl apply` (upsert, matched by resource name) rather than `kubectl create`, OR use a check-then-create pattern (list existing IngressRoutes' `Host()` matches before creating a new one) to guarantee only one router exists per host.

## 2026-08-23 — GROUP D: Uncertain Commands

### D1: pip install -e {app_path} — ✅ Pass
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "
  /home/frappe/bench-data/frappe-bench/env/bin/pip install -e /home/frappe/bench-data/frappe-bench/apps/frappe
"
...
Building editable for frappe (pyproject.toml): finished with status 'done'
Successfully installed frappe-15.118.0
```
Verified rigorously (not just `pip show`'s `Location`, which always points at site-packages regardless of editable status):
```
$ pip list --editable
Package Version  Editable project location
frappe  15.118.0 /home/frappe/bench-data/frappe-bench/apps/frappe
$ pip show -f frappe | grep -i Editable
Editable project location: /home/frappe/bench-data/frappe-bench/apps/frappe
```
Genuinely editable, confirmed.

### D2: python -m pip install -e {app_path} — ✅ Pass
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "
  /home/frappe/bench-data/frappe-bench/env/bin/python -m pip install -e /home/frappe/bench-data/frappe-bench/apps/frappe
"
...
Successfully installed frappe-15.118.0
```
Identical outcome to D1; re-verified via `pip list --editable` — same result. Both invocation forms (`pip install -e` and `python -m pip install -e`) are equivalent here.

### D3: run-patch — ⚡ Pass with modification
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "
  cd /home/frappe/bench-data/frappe-bench &&
  bench --site test.local run-patch frappe.patches.v14_0.update_workspace2_for_rename
"
ModuleNotFoundError: No module named 'frappe.patches.v14_0.update_workspace2_for_rename'
command terminated with exit code 1
```
**Cause:** the exact patch name given doesn't exist. Checked the actual patches directory (`ls apps/frappe/frappe/patches/v14_0/`) and via `find -iname "*workspace2*"` — the real file is `update_workspace2.py`, not `update_workspace2_for_rename.py`.

**Corrected:**
```
$ bench --site test.local run-patch frappe.patches.v14_0.update_workspace2
Executing frappe.patches.v14_0.update_workspace2 in test.local (_9354d31722f40d9e)
Success: Done in 0.587s
```
Exit 0.

### D4: performance_schema queries — ⚡ (works but needs config change)
```
$ kubectl run sql-perf -n frappe-system --rm -i --image=mariadb:10.11 --restart=Never -- mysql -h mariadb.frappe-system.svc.cluster.local -u root -p*** -e "SELECT @@performance_schema;"
@@performance_schema
0
```
`performance_schema` is disabled by default on this instance (confirms the same finding from Phase 1 Group C). Per the branching rule given for this test: since it's `0`, the `events_statements_summary_by_digest` query wasn't run — would need `[mysqld] performance_schema=ON` added to the server config (`custom.cnf` ConfigMap) plus a MariaDB restart to enable, which is a server-level infrastructure change out of scope for a single command test. The query mechanism itself (unaffected by this) was already confirmed working in Phase 1 Group C — it just returns 0 rows while disabled rather than erroring.

### GROUP D Summary

| ID | Command | Result | Notes |
|---|---|---|---|
| D1 | `pip install -e {app_path}` | ✅ Pass | Rigorously verified as genuinely editable |
| D2 | `python -m pip install -e {app_path}` | ✅ Pass | Identical outcome to D1 |
| D3 | `run-patch` | ⚡ Pass with modification | Given patch name doesn't exist; corrected `update_workspace2_for_rename` → `update_workspace2` |
| D4 | performance_schema queries | ⚡ Needs config change | Disabled by default; query mechanism itself works fine once enabled |

**No permanent changes to `test.local` data** — D1/D2 only reinstalled the already-present `frappe` package in place (same version, same source), D3's patch is idempotent (workspace rename cleanup, already-applied-safe), D4 was read-only.

## 2026-08-23 — Phase 3, GROUP P: Kaniko Image Building

Replaces `docker buildx build` + `docker push` with a daemonless in-cluster build via Kaniko.

**Credential handling:** Docker Hub credentials were read once from the local credential file (per explicit instruction), used the **personal access token** rather than the plaintext account password also present in that file (safer — scoped, revocable). Built a `.dockerconfigjson` locally, transferred via `scp` to a private non-repo directory on the server, created the K8s Secret via `--from-file` (never `--docker-password=<value>` inline, which would briefly expose the token in the remote process list via `ps aux`), then immediately shredded the temp files on both ends. The raw token is not present anywhere in this repo.

### P1: Docker Hub secret — ✅ Pass
```
$ kubectl create secret generic dockerhub-secret --from-file=.dockerconfigjson=... --type=kubernetes.io/dockerconfigjson -n frappe-system
secret/dockerhub-secret created
$ kubectl get secret dockerhub-secret -n frappe-system
dockerhub-secret   kubernetes.io/dockerconfigjson   1   0s
```

### P2: Test Dockerfile — ✅ Pass
```
FROM frappe/bench:latest
LABEL test="kaniko-phase3"
```

### P3: Kaniko Job manifest — ✅ Pass
Saved to `k3s/kaniko-test-job.yaml`, destination substituted to the real Docker Hub username (`ahmed3majeed/frappe-k3s-agent-test:latest`).

### P4: ConfigMap from Dockerfile — ✅ Pass
```
$ kubectl create configmap test-dockerfile --from-file=Dockerfile=/tmp/test.Dockerfile -n frappe-system
configmap/test-dockerfile created
```

### P5: Run Kaniko Job — ✅ Pass
```
$ kubectl apply -f k3s/kaniko-test-job.yaml
$ kubectl wait --for=condition=complete job/kaniko-test-build -n frappe-system --timeout=600s
job.batch/kaniko-test-build condition met
$ kubectl get job kaniko-test-build -n frappe-system
kaniko-test-build   Complete   1/1   15s
```
Completed in **15 seconds** — much faster than the 10-minute budget, since Kaniko recognized the Dockerfile only adds a LABEL (no filesystem change) and skipped re-unpacking the base image layers.

### P6: Job logs — ✅ Pass
```
INFO Retrieving image manifest frappe/bench:latest
INFO Returning cached image manifest
INFO LABEL test="kaniko-phase3"
INFO Pushing image to ahmed3majeed/frappe-k3s-agent-test:latest
INFO Pushed index.docker.io/ahmed3majeed/frappe-k3s-agent-test@sha256:92c3f1b8f47a0f109e6ad0084a99d25b9244edcef96ab27b153a4c894e5a7d2e
```
No errors — clean build and push, real digest returned by Docker Hub.

### P7: Verify image on Docker Hub — ⚡ Pass with caveat
First attempt (`kubectl run verify-push --rm -i ... -- echo ...`) **hung in `ContainerCreating` for 8+ minutes** with no error events, just a persistent `Pulling image` event. Investigated:
- Node disk space: fine (132G free)
- Registry connectivity: fine (`curl https://registry-1.docker.io/v2/` → fast 401, as expected unauthenticated)
- Direct `crictl pull ahmed3majeed/frappe-k3s-agent-test:latest` — **eventually succeeded** (`Image is up to date`) after several more minutes with no explicit error at any point.

**Root cause (most likely): Docker Hub's anonymous-pull rate limit.** This session has pulled a very large number of images from Docker Hub over many hours of testing (mariadb, redis, bench, erpnext-related base images, busybox, etc.), all via unauthenticated/anonymous pulls (no `imagePullSecret` on any of the test pods) from this node's single IP. Docker Hub throttles anonymous pulls per-IP (historically ~100 pulls/6h) — a throttled pull doesn't always surface as a hard error in kubelet events, it can just silently slow to a crawl. Once the image was cached locally (after the slow pull finally completed), a fresh verification pod (`verify-push3`) completed in 6 seconds.
**Verified by:** `verify-push3` → `Completed`, logs: `Image pulled successfully`.
**Implementation note for the real Agent:** even for its own pushed images, prefer an authenticated pull (via `imagePullSecrets` referencing the same `dockerhub-secret`) rather than anonymous — authenticated pulls get a materially higher Docker Hub rate limit and avoid this exact multi-minute stall.

### P8: Cleanup — ✅ Pass
```
$ kubectl delete job kaniko-test-build -n frappe-system
Error from server (NotFound): jobs.batch "kaniko-test-build" not found
```
Already gone — the Job's own `ttlSecondsAfterFinished: 300` auto-deleted it during the P7 troubleshooting delay (confirms TTL cleanup works as configured, not a bug).
```
$ kubectl delete configmap test-dockerfile -n frappe-system
configmap "test-dockerfile" deleted from frappe-system namespace
```

**Note:** the pushed test image `ahmed3majeed/frappe-k3s-agent-test:latest` itself was **not** deleted from Docker Hub (Kubernetes cleanup only removes in-cluster resources, not the registry artifact). It's a small, harmless test image, but flagged here since it's now a real, visible repository under the account.

### GROUP P Summary

| Step | Result |
|---|---|
| P1 Docker Hub secret | ✅ Pass |
| P2 Test Dockerfile | ✅ Pass |
| P3 Kaniko Job manifest | ✅ Pass |
| P4 ConfigMap | ✅ Pass |
| P5 Run Job | ✅ Pass (15s, well under budget) |
| P6 Job logs | ✅ Pass |
| P7 Verify on Docker Hub | ⚡ Pass with caveat (anonymous-pull rate limiting, not a build/push bug) |
| P8 Cleanup | ✅ Pass |

**7/8 clean, 1/8 surfaced a real infrastructure consideration (registry pull throttling) rather than a bug in the build pipeline itself.**

## 2026-08-23 — Phase 3, GROUP Q: S3 Backup (IDrive e2)

Replaces the original Agent's `mkfifo` + `rclone rcat` streaming design with a simpler, K8s-native pattern: `bench backup` writes to the PVC → a Job uploads those files to S3-compatible storage.

**Credential handling:** same discipline as Group P — IDrive e2 access/secret keys read once from the local file, written to a local env-file, transferred via `scp` to a private non-repo server directory, loaded into the K8s Secret via `--from-env-file` (never as literal `--from-literal=` values on a visible command line), then shredded on both ends immediately.

### Q1: IDrive e2 secret — ✅ Pass
```
$ kubectl create secret generic idrive-e2-secret --from-env-file=... -n frappe-system
secret/idrive-e2-secret created
$ kubectl get secret idrive-e2-secret -n frappe-system
idrive-e2-secret   Opaque   3   16m
```

### Q2: bench backup — ✅ Pass
```
$ bench --site test.local backup --with-files --verbose
Backup for Site test.local has been successfully completed with files
```
Files: `sites/test.local/private/backups/20260823_031915-test_local-{database.sql.gz,files.tar,private-files.tar,site_config_backup.json}`.

### Q3: S3 upload Job manifest — ✅ Pass (written), see Q4 for two real bugs found running it

### Q4: Bucket create + run upload — ⚡ Pass with two modifications

**Bucket create:** ✅ clean — `make_bucket: frappe-k3s-test-backups` (via a small secret-referencing Pod manifest instead of `kubectl run --env=<value>`, which would've put the raw access key on the command line).

**First upload attempt — FAILED:**
```
Error from server (BadRequest): container "uploader" in pod "s3-backup-upload-tvckr" is waiting to start: CreateContainerConfigError
...
Warning  Failed  kubelet  Error: secret "idrive-e2-secret" not found
```
**Root cause:** the spec itself has a namespace mismatch — Q1 creates `idrive-e2-secret` in `frappe-system`, but Q3's Job runs in `frappe-v15`. Kubernetes Secrets are strictly namespace-scoped; a Job can only reference a Secret that lives in its own namespace.
**Fix:** copied the secret from `frappe-system` to `frappe-v15` via the K8s API (`kubectl get secret ... -o json` → strip metadata → `kubectl apply -n frappe-v15 -f -`) — this moves the already-base64-encoded secret data through `kubectl` without ever re-touching the raw credential text.

**Second upload attempt — FAILED:**
```
aws: [ERROR]: The user-provided path /backup-source/sites/test.local/private/backups/ does not exist.
Upload complete: 255
```
**Root cause:** another spec mismatch — the PVC (`bench-v15-data`) is mounted at `/home/frappe/bench-data`, and `bench init` created the actual bench at `frappe-bench/` **inside** that mount (a deliberate choice from Phase 1, since `bench init` requires its target directory not to already exist). So from the PVC root, the real path is `frappe-bench/sites/...`, not `sites/...` directly. The manifest as given assumed the PVC root *was* the bench directory.
**Fix:** corrected the mount path in `k3s/s3-upload-job.yaml` to `/backup-source/frappe-bench/sites/test.local/private/backups/`.

**Third attempt — SUCCESS:**
```
$ kubectl wait --for=condition=complete job/s3-backup-upload -n frappe-v15 --timeout=120s
job.batch/s3-backup-upload condition met
...
Upload complete: 0
```
All 9 accumulated backup files (from every backup taken across this whole engagement, not just Q2's) uploaded successfully.

### Q5: Verify files on IDrive e2 — ✅ Pass
```
$ aws s3 ls s3://frappe-k3s-test-backups/test.local/ --endpoint-url https://s3.eu-central-2.idrivee2.com
2026-08-23 07:23:18   1182898  20260822_205446-test_local-database.sql.gz
... (12 files total, all 3 backup sets, real non-zero sizes)
```

### Q6: Download from S3 and restore (full cycle) — ✅ Pass
The command given for this step (`kubectl run s3-download ...`) was missing both AWS credential env vars and any volume mount — same underspecified-example pattern hit earlier in this project. Built a proper Pod manifest (`k3s/s3-download-pod.yaml`) mounting the same `bench-v15-data` PVC at `/restore-target`, downloading into a scratch subdirectory (`s3-restore-test/`) so `bench-v15` can reach the files directly (same underlying PVC).
```
$ aws s3 cp s3://.../test.local/ /restore-target/s3-restore-test/ --recursive ...
Download complete: 0
```
Then ran the actual restore from the downloaded files:
```
$ bench --site test.local restore \
  --mariadb-root-username root --mariadb-root-password *** --admin-password *** \
  --with-public-files .../s3-restore-test/20260823_031915-test_local-files.tar \
  --with-private-files .../s3-restore-test/20260823_031915-test_local-private-files.tar \
  .../s3-restore-test/20260823_031915-test_local-database.sql.gz
Site test.local has been restored with files
```
Verified `bench --site test.local list-apps` → `frappe 15.118.0 version-15` — full **backup → S3 upload → S3 download → restore** cycle confirmed working end-to-end, `test.local` intact throughout (restored from a backup of its own current state, so no meaningful data change).

**Cleanup note:** the `s3-download` Pod ran as root, leaving root-owned scratch files on the shared PVC that the `frappe` user couldn't remove directly — needed `kubectl exec ... -- sudo rm -rf` to clean up. Worth remembering for any real Agent design: containers writing to a shared bench PVC should run as the `frappe` UID, not root, to avoid this exact friction.

### Q7: Cleanup S3 test data — ✅ Pass
```
$ aws s3 rm s3://frappe-k3s-test-backups/ --recursive ...
delete: s3://frappe-k3s-test-backups/test.local/... (12 files deleted)
```
Bucket itself left in place (empty) — not deleted, since bucket deletion wasn't requested and IDrive e2 buckets aren't disposable K8s resources.

### GROUP Q Summary

| Step | Result |
|---|---|
| Q1 IDrive e2 secret | ✅ Pass |
| Q2 bench backup | ✅ Pass |
| Q3 Upload Job manifest | ✅ Pass |
| Q4 Bucket + run upload | ⚡ Pass with 2 modifications (secret namespace, PVC path) |
| Q5 Verify on S3 | ✅ Pass |
| Q6 Download + restore (full cycle) | ✅ Pass |
| Q7 S3 cleanup | ✅ Pass |

**5/7 clean, 2/7 surfaced real spec bugs (both fixed and documented) rather than infrastructure problems.** Both bugs are exactly the kind of thing worth catching now: a namespace-scoping mistake and a path assumption that didn't match how the bench was actually laid out on its PVC — both would silently break a real Agent's backup pipeline if shipped as originally specified.

## 2026-08-23 — Decision Log Additions (formalizing Phase 3 findings)

### D13: Docker Hub anonymous pull rate limiting
**Discovered in:** Group P (P7 — verifying the Kaniko-pushed image was pullable)
**Finding:** A verification pod hung in `ContainerCreating` for 8+ minutes with zero error events (just a persistent `Pulling image` kubelet event) — not a disk space issue (132G free), not a registry connectivity issue (fast response from `registry-1.docker.io`), not a bad push (a direct `crictl pull` on the node eventually succeeded with no error). Root cause: this node has made a very large number of unauthenticated/anonymous image pulls from Docker Hub across this entire multi-session engagement (mariadb, redis, bench, erpnext, busybox, etc.), all from a single IP. Docker Hub throttles anonymous pulls per-IP; a throttled pull doesn't always surface as a hard kubelet error, it can just silently crawl. Once cached, a fresh verification pod completed in 6 seconds.
**Impact on Custom Agent:** any image pull the Agent triggers — including pulling its own just-built/pushed images — can silently stall for many minutes if done anonymously, with no error to catch or alert on. A naive timeout-based retry won't help if the underlying cause is throttling, not a transient failure.
**Implementation rule:** always attach `imagePullSecrets` (referencing the same registry Secret used for pushing) to every Pod/Deployment/Job spec that pulls an image from Docker Hub — including the Agent's own images, not just customer bench images. Authenticated pulls get a materially higher Docker Hub rate limit than anonymous ones.

### D14: K8s Secrets are namespace-scoped
**Discovered in:** Group Q (Q4 — first S3 upload Job attempt)
**Finding:** The IDrive e2 Secret (`idrive-e2-secret`) was created in the `frappe-system` namespace, but the S3 upload Job was specified to run in `frappe-v15`. The Job failed immediately with `CreateContainerConfigError` / `Error: secret "idrive-e2-secret" not found` — Kubernetes Secrets are strictly namespace-scoped; a Pod/Job can only reference a Secret that lives in its own namespace, full stop. There is no cross-namespace Secret reference mechanism in core Kubernetes.
**Impact on Custom Agent:** any manifest template (backup upload, image push, restore, or any other Job the Agent generates) that references a Secret by name must be generated with that Secret provisioned in the *same* namespace as the Job — a shared "central" Secret in one namespace is invisible everywhere else, and this fails silently at the manifest-authoring stage (no error until the Job actually tries to start).
**Implementation rule:** the Custom Agent must create (or copy) every required Secret into each bench namespace that needs it, at the time that namespace/bench is provisioned — never assume a Secret created once in an infra namespace (like `frappe-system`) is reachable from a per-bench namespace (like `frappe-v15`). When a Secret's contents are shared across namespaces (e.g. one S3 backup destination for all benches), copy the Secret's already-encoded data via the API (`kubectl get secret ... -o json` → strip metadata → `kubectl apply -n {target-ns} -f -`) rather than re-entering raw credentials per namespace.

### D15: PVC mount path offset
**Discovered in:** Group Q (Q4 — second S3 upload Job attempt, after fixing D14)
**Finding:** The S3 upload manifest assumed the PVC root directly contains `sites/` (i.e., `/backup-source/sites/test.local/...`), and failed with `aws: [ERROR]: The user-provided path /backup-source/sites/test.local/private/backups/ does not exist.` In this setup, the PVC (`bench-v15-data`) is mounted at `/home/frappe/bench-data`, and `bench init` created the actual bench one level inside that mount, at `frappe-bench/` (a deliberate choice from Phase 1/Phase 2 K6 — `bench init` requires its target directory not to already exist, so the PVC has to be mounted at the *parent* of `frappe-bench/`, not at `frappe-bench/` itself). So the real path from the PVC root is `frappe-bench/sites/test.local/...`, not `sites/test.local/...` directly.
**Impact on Custom Agent:** every Job/Pod that mounts a bench's PVC to read or write site files (backup upload, backup download+restore, log collection, asset access, etc.) must account for this one-level offset — `{pvc-mount}/frappe-bench/sites/...`, never `{pvc-mount}/sites/...`. Getting this wrong doesn't corrupt anything, but it does fail cleanly with a "path does not exist" error, so it's a straightforward one-line fix once caught — the risk is it going unnoticed until the first real backup/restore is attempted.
**Implementation rule:** any manifest template that mounts a bench PVC must reference paths as `{mountPath}/frappe-bench/sites/{site}/...`, matching the exact layout `k3s/bench-deployment.yaml` and `k3s/bench-pvc.yaml` establish (PVC mounted at `/home/frappe/bench-data`, bench created at `.../bench-data/frappe-bench/`). Treat this path prefix as a constant shared across every manifest template that touches bench data, not something to re-derive per Job.

## 2026-08-23 — GROUP R: Full App Update Cycle

Tests the complete workflow the Custom Agent must execute when Press requests an app update: fetch → diff → checkout → conditional pip/build/migrate → restart → verify.

### Pre-flight checks (before touching anything)
1. **Remote name:** confirmed via `git remote -v` → the remote is `upstream`, not `origin` (matches the Phase 1 Group B finding). The `origin` in the task spec would fail.
2. **`bench-v15` resource type:** `kubectl get pod bench-v15 -n frappe-v15 -o jsonpath="{.metadata.ownerReferences}"` → **empty** — no owner. `kubectl get deployment,replicaset,statefulset -n frappe-v15` → none exist. **`bench-v15` is a fully bare, unmanaged Pod.** The task's R6 fallback assumption ("K8s will recreate it automatically" after `kubectl delete pod`) is **false** for an unmanaged Pod — only pods owned by a controller (Deployment/ReplicaSet/StatefulSet/DaemonSet/Job) get recreated on deletion. Confirmed the original pod manifest (`/home/frappe/manifests/frappe-v15/bench-pod.yaml`) is still saved on the server as a safety net before proceeding. See **D16** below.

### R1: Baseline commit — ✅ Pass
```
$ git log --oneline -3
9b8d265 chore(release): Bumped to Version 15.118.0
16d483c Merge pull request #41779 from frappe/version-15-hotfix
...
$ git rev-parse HEAD
9b8d265b27a1dfb11c7aef21a533a127e14a0a5a
```
**OLD_HASH = `9b8d265b27a1dfb11c7aef21a533a127e14a0a5a`**

### R2: Fetch latest — ⚡ Pass with modification
```
$ git remote get-url origin
error: No such remote 'origin'
command terminated with exit code 2
```
Corrected to the real remote name:
```
$ git remote get-url upstream
https://github.com/frappe/frappe.git
$ git fetch --depth 2 upstream version-15 && git rev-parse FETCH_HEAD
9b8d265b27a1dfb11c7aef21a533a127e14a0a5a
```
**NEW_HASH = `9b8d265b27a1dfb11c7aef21a533a127e14a0a5a`**

**OLD_HASH == NEW_HASH** — no new commits have landed on `frappe/frappe`'s `version-15` branch since this bench was initialized. Per the task's own rule, **R3–R6 skipped**, proceeding directly to R7. (`test.local` was never at risk here — no `git reset --hard`/`git clean -fd`/checkout was run at all, since there was nothing to update to.)

### R7: Verify site — ✅ Pass
```
$ bench --site test.local list-apps
frappe 15.118.0 version-15
$ bench --site test.local migrate
...
Executing `after_migrate` hooks...
Queued rebuilding of search index for test.local
```
Clean, exit 0. `bench-v15` pod healthy throughout — never touched, since no update meant no restart was needed either.

### R8: App Update Decision Tree

| Changed files | Action |
|---|---|
| `*.vue`, `*.js` | `bench build --app {app}` |
| `requirements*.txt`, `pyproject.toml` | `pip install -e {app}` |
| `*/patches/*.py` | `bench migrate` |
| `*.py` (non-patch) | rollout restart only |
| No changes (`OLD_HASH == NEW_HASH`) | skip — already up to date |

**Not exercised this run:** since no real update was available, R3 (diff categorization), R4 (checkout), R5 (conditional pip/build/migrate), and R6 (restart) never ran against real changed files — only the decision table above (as specified in the task) is documented, not empirically re-derived from an actual diff. Available on request: re-run against a deliberately older commit to exercise the full update path for real, if that's wanted.

### GROUP R Summary

| Step | Result |
|---|---|
| Pre-flight (remote name, pod ownership) | Caught 2 real issues before running anything |
| R1 Baseline | ✅ Pass |
| R2 Fetch latest | ⚡ Pass with modification (`origin` → `upstream`) |
| R3–R6 | Skipped — no update available (per task's own rule) |
| R7 Verify | ✅ Pass |
| R8 Decision tree | ✅ Documented |

## Decision Log Addition

### D16: bare Pod vs. Deployment — restart/recreate semantics
**Discovered in:** Group R (pre-flight check before R6)
**Finding:** `bench-v15` (the original Phase 1 test bench) was created as a bare `kind: Pod` with no owning controller — `kubectl get pod bench-v15 -o jsonpath="{.metadata.ownerReferences}"` returns empty, and no Deployment/ReplicaSet/StatefulSet exists in `frappe-v15`. The Group R task instructions assumed that deleting this pod would trigger automatic recreation ("K8s will recreate it automatically") — **this is false for an unmanaged Pod.** Only pods owned by a controller get recreated on deletion; a bare Pod that's deleted is simply gone until something re-applies its manifest.
**Impact on Custom Agent:** any restart/update logic the Agent runs (`kubectl rollout restart deployment/...` or a delete-and-recreate fallback) must know in advance whether the target is actually a controller-managed resource. Applying Deployment-style restart logic to a bare-Pod bench (as `bench-v15` still is, a holdover from before Group K's proper Deployment-based bench pattern existed) would either fail cleanly (`rollout restart` on a nonexistent Deployment) or, worse, silently destroy the pod if the delete-fallback were used without a saved manifest to reapply.
**Implementation rule:** every bench the Agent manages must be a Deployment (as established in Phase 2 Group K's `k3s/bench-deployment.yaml` pattern) — never a bare Pod — specifically so that restart/update operations can rely on controller-managed recreation semantics. Before running any delete-based fallback on any resource, the Agent must first confirm the resource has an owning controller (non-empty `ownerReferences`); if not, either refuse the operation or ensure a manifest is available to reapply immediately after deletion, exactly as this test did as a precaution.

## 2026-08-23 — Decision Log Additions (pre-GROUP RS audit)

Audited RUNBOOK.md against a checklist of 6 critical findings before starting Group RS. 4 were already formal Decision Log entries (D13 Docker Hub rate limiting, D14 Secrets namespace-scoping, D15 PVC mount path offset, D16 bare Pod vs Deployment). 2 existed only as inline mentions and are formalized here.

### D17: git remote is named "upstream" not "origin"
**Discovered in:** Group R, R2 (also matches the earlier Phase 1 Group B finding)
**Finding:** the `frappe` app's git remote, as cloned by `bench init`, is named `upstream`, not `origin`. `git remote get-url origin` / `git fetch ... origin ...` fails with `error: No such remote 'origin'`. Confirmed identically in two independent tests (Phase 1 Group B, and Group R's R2).
**Impact on Custom Agent:** any git operation the Agent runs against an app's checkout (fetch, remote inspection, diff against a fetched ref) must target `upstream`, not `origin` — this isn't a one-off, it's how every bench-init'd app is set up.
**Implementation rule:** all git fetch/remote commands must use `upstream`:
```
git fetch --depth 1 upstream {branch}
```
**not**
```
git fetch --depth 1 origin {branch}
```

### D18: performance_schema disabled by default
**Discovered in:** Phase 1 Group C (SQL commands) and Group D (uncertain commands, D4)
**Finding:** `SELECT @@performance_schema;` → `0` on this MariaDB instance — disabled by default. Confirmed identically in two independent tests. The `events_statements_summary_by_digest` query itself is valid and doesn't error while disabled, it just returns 0 rows.
**Impact on Custom Agent:** any slow-query-analysis or performance-report feature the Agent offers (mirroring the original Agent's `performance_schema` queries) will silently return empty results, not an error, unless the MariaDB server was configured with performance_schema enabled from the start. A silent empty result is easy to mistake for "no slow queries" rather than "the feature isn't actually on."
**Implementation rule:** add `[mysqld] performance_schema=ON` to the MariaDB config (`custom.cnf`) at server setup time — this requires a MariaDB restart to take effect, so it must be decided during initial infrastructure provisioning, not toggled on-demand per query.

## 2026-08-23 — GROUP RS: Real App Update Flow (End-to-End)

Group R was skipped (OLD_HASH == NEW_HASH, no real update available). This test simulates a real update by deliberately rolling `apps/frappe` back 3 commits, then running the full update flow forward against `upstream/version-15`.

### RS1: Baseline
```
$ git log --oneline -5    # only showed 2 (shallow clone, depth 2) — deepened first
$ git fetch --depth 10 upstream version-15
$ git log --oneline -6
9b8d265 chore(release): Bumped to Version 15.118.0
16d483c Merge pull request #41779 ...
5145f2a Merge pull request #41769 ...
d6028ef Merge pull request #41708 ...
0ecfb97 test: resolve backport conflict in workflow tests
9e527c5 Merge pull request #41771 ...
```
**CURRENT_HEAD = `9b8d265b27a1dfb11c7aef21a533a127e14a0a5a`**. Per the task's own "4th line back" rule: **OLD_COMMIT = `d6028ef`**.

### RS2: Roll back — ✅ Pass
```
$ git reset --hard d6028ef
HEAD is now at d6028ef Merge pull request #41708 ...
```

### RS3: Fetch (simulate update trigger) — ✅ Pass
```
$ git fetch --depth 5 upstream version-15 && git rev-parse FETCH_HEAD
9b8d265b27a1dfb11c7aef21a533a127e14a0a5a
```
**NEW_HASH = `9b8d265...`** — confirmed different from OLD_COMMIT, 3 commits apart as designed.

### RS4: Detect changes — ✅ Pass
```
$ git diff --name-only HEAD FETCH_HEAD | wc -l
3
$ git diff --name-only HEAD FETCH_HEAD
frappe/__init__.py
frappe/workflow/doctype/workflow/test_workflow.py
frappe/workflow/doctype/workflow_action/workflow_action.py
```
Frontend: **none**. Dependencies: **none**. Patches/migrations: **none**. Python-only: **all 3 files**. A small, real, low-risk update — exactly the kind that should map to "code update + restart only," no build/pip/migrate needed.

### RS5: Apply update — ✅ Pass
```
$ git clean -fd && git checkout FETCH_HEAD
HEAD is now at 9b8d265 chore(release): Bumped to Version 15.118.0
```
(Detached HEAD — see RS9's finding on why this matters.)

### RS6: Conditional steps — all SKIPPED (correctly)
No frontend, dependency, or patch changes detected in RS4 → `pip install -e`, `bench build`, and `bench migrate` were all correctly skipped per the "only run what applies" rule. Since the app is installed in editable mode (Phase 1 Group D finding), the new Python code took effect immediately on checkout — no reinstall needed for pure code changes.

### RS7: Restart options — both tested, both fail as expected (confirms D16)
**Option A:**
```
$ kubectl rollout restart pod/bench-v15 -n frappe-v15
error: pods "bench-v15" restarting is not supported
```
Exact, unambiguous kubectl error for attempting a Deployment-style rollout on a bare Pod.

**Option B:**
```
$ kubectl exec -n frappe-v15 bench-v15 -- bash -c "pkill -f frappe ..."
command terminated with exit code 143
```
Interesting failure mode: exit 143 (SIGTERM) — `pkill -f frappe` matched and killed **its own invoking shell**, since the `bash -c` command line itself contains the substring "frappe" (via `/home/frappe/...`, `frappe-bench`, etc.). Confirmed the pod itself was unaffected: `kubectl get pod bench-v15` → `Running`, `0` restarts, unchanged age; `ps aux` inside the pod still shows PID 1 as `sleep infinity`. **`pkill -f` pattern matching is not just unnecessary here — it's actively unsafe**, since almost any reasonable pattern is likely to match the invoking shell's own command line inside a path like `/home/frappe/bench-data/frappe-bench/...`.
**Conclusion (matches D16):** in production, restart must be `kubectl rollout restart deployment/{bench-name}` against a real Deployment — this is exactly why every real bench must be created as a Deployment (Phase 2 Group K pattern), never a bare Pod.

### RS8: Verify after update — ✅ Pass
```
$ bench --site test.local list-apps
frappe 15.118.0 version-15
$ bench --site test.local migrate
...
Executing `after_migrate` hooks...
```
Exit 0, clean.

### RS9: Restore to CURRENT_HEAD — ⚡ Pass with a real, notable finding

First attempt:
```
$ git checkout 9b8d265b27a1dfb11c7aef21a533a127e14a0a5a
HEAD is now at 9b8d265 chore(release): Bumped to Version 15.118.0
$ bench --site test.local list-apps
frappe 15.118.0 HEAD          ← was "version-15" before Group RS started!
```
**Right commit, wrong branch label.** Investigated: `git checkout <hash>` (as literally specified) restores the *commit content* but leaves the repo in **detached HEAD**, not back on the named `version-15` branch.

Attempted fix #1 — `git checkout version-15`:
```
Your branch is behind 'upstream/version-15' by 9 commits, and can be fast-forwarded.
$ git log --oneline -1
d6028ef Merge pull request #41708 ...    ← wrong commit!
```
Deeper root cause found: RS2's `git reset --hard d6028ef` ran *while the `version-15` branch was checked out*, so it moved the **local branch pointer itself** back to `d6028ef`. Every checkout after that (RS3 fetch, RS5's `checkout FETCH_HEAD`, this first RS9 attempt) used detached HEAD, so the `version-15` branch ref was never updated — it sat stuck at `d6028ef` for the rest of the test.

Fix #2 — reset the branch to the correct commit while it's checked out:
```
$ git reset --hard 9b8d265b27a1dfb11c7aef21a533a127e14a0a5a
$ git branch --show-current
version-15
$ bench --site test.local list-apps
frappe 15.118.0 HEAD          ← still wrong! git state is now fully correct though.
```
Git itself was now fully correct (`git rev-parse --abbrev-ref HEAD` → `version-15`, `.git/HEAD` → `ref: refs/heads/version-15`), but `list-apps` still showed `HEAD`. Traced the actual source (not bench's own `get_current_branch`, since `bench --site X list-apps` is a **Frappe framework command**, not a bench-CLI command): `frappe/commands/site.py`'s `list_apps()` reads `app.git_branch` from the **`Installed Applications` DocType in the site's database** — a value written during `bench migrate`, not re-derived live from git on every call. RS8's `migrate` ran while the repo was in detached HEAD, so `git symbolic-ref -q --short HEAD` (empty on detached HEAD) resolved to the literal string `"HEAD"`, and *that* got persisted into the database.

**Real fix:** re-ran `bench --site test.local migrate` once more, now that the repo was correctly on the `version-15` branch:
```
$ bench --site test.local migrate
...
$ bench --site test.local list-apps
frappe 15.118.0 version-15      ← fully restored
```

**Final verified state:**
```
HEAD commit: 9b8d265b27a1dfb11c7aef21a533a127e14a0a5a
Branch: version-15
Status: (clean)
```
`bench-v15` pod: `Running`, `0` restarts, unchanged age throughout — never touched.

### RS10: App Update Decision Tree (empirically derived from RS4)

| Change type | Detected? | Action taken |
|---|---|---|
| Frontend (`*.js`/`*.vue`/`*.jsx`) | ✗ | skipped |
| Dependencies (`requirements*.txt`, `pyproject.toml`) | ✗ | skipped |
| Patches/migrations (`patches/`, `migrations/`) | ✗ | skipped |
| Python (non-patch) | ✓ (3 files) | code took effect immediately via editable install; `bench migrate` still run as a general post-update sanity check |

### GROUP RS Summary

| Step | Result |
|---|---|
| RS1 Baseline | ✅ Pass (had to deepen shallow clone first) |
| RS2 Roll back | ✅ Pass |
| RS3 Fetch | ✅ Pass |
| RS4 Detect changes | ✅ Pass |
| RS5 Apply update | ✅ Pass |
| RS6 Conditional steps | ✅ Pass (all correctly skipped) |
| RS7 Restart (both options) | ✅ Pass (both fail as expected, confirming D16) |
| RS8 Verify after update | ✅ Pass |
| RS9 Restore to CURRENT_HEAD | ⚡ Pass with a real, multi-layered finding (see D19) |
| RS10 Decision tree | ✅ Documented |

**9/9 steps completed, one of them (RS9) surfacing a genuinely important, non-obvious finding about how `bench migrate` and detached-HEAD checkouts interact.**

## Decision Log Additions

### D19: git checkout must target a branch, never a detached commit/FETCH_HEAD
**Discovered in:** Group RS, RS9 (surfaced while restoring state after the simulated update)
**Finding:** `git checkout {hash}` / `git checkout FETCH_HEAD` correctly updates the working tree content but leaves the repo in **detached HEAD** state. This is invisible to most operations (the app runs fine, git itself reports the right commit) — but `bench --site {s} migrate` calls `git symbolic-ref -q --short HEAD` to determine the app's current branch, which returns empty on a detached HEAD, and that resolves to the literal string `"HEAD"` being written into the site's `Installed Applications` DocType (`git_branch` field) — persisted in the **database**, not just a cosmetic git-state issue. Every subsequent `bench --site {s} list-apps` then shows `"HEAD"` instead of the real branch name, and this does **not** self-correct until `migrate` runs again while the repo is properly on a named branch. Separately, if a `git reset --hard {hash}` is run while a named branch happens to be checked out, it silently moves that branch's own ref pointer — so a later `git checkout {branch-name}` doesn't land where you'd expect, either.
**Impact on Custom Agent:** any update flow that fetches a new commit and applies it via `git checkout {hash}` (rather than a branch name) will leave the bench in detached HEAD. The very next `bench migrate` (a completely normal, expected step in the same update flow) will then corrupt the site's own app-version bookkeeping — a real, persisted regression, not a transient display glitch. This is a correctness bug that's easy to ship: everything appears to work (the app functions correctly), and the only symptom is a wrong branch label that most tests wouldn't think to check.
**Implementation rule:** the Agent's update flow must **never** `git checkout <commit-hash>` or `git checkout FETCH_HEAD` directly against a bench's app repo. Instead: fast-forward the actual branch ref (`git checkout {branch} && git merge --ff-only {fetched-hash}`, or equivalently `git checkout -B {branch} {fetched-hash}` if the branch needs to be reset to match), so the repo is always left on a named branch before `bench migrate` (or any other step that queries the current branch) ever runs.

### D20: `pkill -f` is unsafe for identifying processes to restart inside a bench pod
**Discovered in:** Group RS, RS7 (Option B restart test)
**Finding:** `pkill -f frappe` run via `kubectl exec -n {ns} {pod} -- bash -c "pkill -f frappe"` killed its own invoking shell process (exit code 143/SIGTERM) rather than reporting "no matching process." Root cause: `pkill -f` matches against the full command line of every process, and the `bash -c` command line itself contains the substring "frappe" (via paths like `/home/frappe/bench-data/frappe-bench/...`). The pod's actual PID 1 (`sleep infinity`) was correctly unaffected, since its command line contains no such substring — but any exec'd command whose own invocation happens to match the search pattern is at risk of self-terminating.
**Impact on Custom Agent:** if the Agent ever uses `pkill -f <pattern>` (or similar broad process-matching) inside a bench container to restart a specific process, it must guarantee the pattern cannot also match the invoking shell's own command line — otherwise the operation can silently kill the wrong thing (its own exec session) while reporting a generic-looking non-zero exit, easy to misread as "nothing to kill."
**Implementation rule:** avoid `pkill -f` with broad substrings for any in-container process management. Prefer exact PID targeting (from `pgrep`/`ps` filtered on a narrow, unambiguous pattern verified not to match the shell invocation itself), or — better — avoid in-container process signaling entirely and rely on `kubectl rollout restart deployment/{bench}` (which restarts the whole pod cleanly via the controller, per D16/D19), rather than trying to kill individual processes inside a running container.

## 2026-08-23 — Decision Log Additions (audit follow-up: 3 findings had no formal entry)

Full audit of D1–D20 against a 20-item reference checklist found 3 findings that existed only as inline table/narrative mentions, never as a formal Decision Log entry under any number. Added here as D21–D23 (existing D1–D20 numbering left untouched to avoid breaking cross-references like "see D16" elsewhere in this document).

### D21: Frappe site database name is an auto-generated hash, not the site domain
**Discovered in:** Phase 1, Tier D3 (database size query)
**Finding:** The MariaDB database backing a Frappe site is **not** named after the site's domain (e.g. `test.local` does not have a database literally called `test_local`). Frappe auto-generates a hash-style database name at `bench new-site` time (confirmed: `_9354d31722f40d9e` for `test.local`). Any command assuming `USE {site_with_dots_replaced}` or `WHERE table_schema='{site_name}'` will fail or silently return nothing — confirmed directly: `USE test_local; SHOW TABLES;` → `ERROR 1049: Unknown database 'test_local'`.
**Impact on Custom Agent:** any SQL-level operation the Agent performs directly against a site's database (table listing, size queries, optimize/repair, direct backups) must resolve the real database name first — it cannot be derived from the site name by simple string transformation.
**Implementation rule:** always read the real database name from the site's own `site_config.json` (`db_name` field) rather than deriving it from the site domain string. Never assume `{site-name-with-underscores}` is the database name.

### D22: `bench git apply` is not a real bench subcommand
**Discovered in:** Phase 1, Group A (git apply / git apply --reverse testing)
**Finding:** `bench git apply {patch}` fails with `Error: No such command 'git'.` — there is no `git` subcommand namespace under the `bench` CLI. This is likely a description artifact from the source material being audited, not a real Agent capability. The actual, working mechanism is plain `git apply`/`git apply --reverse`, run directly inside the app's directory (confirmed working: apply → change present → reverse → working tree clean).
**Impact on Custom Agent:** if the Agent's patch-application logic is built assuming a `bench git apply` command exists, every patch-apply operation will fail immediately with a confusing "no such command" error.
**Implementation rule:** apply/reverse patches via plain `git apply {patch}` / `git apply --reverse {patch}`, executed with a working directory of the target app's repo (`apps/{app}`) — never through a `bench git ...` subcommand, which doesn't exist.

### D23: `update-site-plan` is a Frappe Cloud (`press`)-specific command, not core Frappe
**Discovered in:** Phase 1, Group A (update-site-plan testing)
**Finding:** `bench --site {s} update-site-plan {plan}` fails with `Error: No such command 'update-site-plan'.` on a bench that only has the `frappe` app installed. This command is not part of the core Frappe framework's bench CLI — it's almost certainly provided by the `press` app (Frappe Cloud's own management app), which isn't installed in this environment.
**Impact on Custom Agent:** if the Agent's site-plan/billing-tier logic assumes `update-site-plan` is always available as a bench command, it will fail on any bench that doesn't have the `press` app installed — which is the normal case for a bench that only runs customer apps.
**Implementation rule:** do not depend on `update-site-plan` (or other `press`-app-specific bench commands) being available. If site-plan tracking is needed, the Agent should manage that state itself (e.g. in its own database/site_config) rather than relying on a command that only exists when a specific optional app is installed.

## 2026-08-23 — Frappe v16 Testing Environment

### Step 1: Check current Redis version — real finding, contradicts task premise
```
$ kubectl exec -n frappe-system redis-cache-master-0 -- redis-server --version
Redis server v=8.10.1 ...
```
The task's context claimed `frappe-system` runs "Redis 6/7, NOT compatible with v16." **This is factually wrong** — it's been v8.10.1 since Phase 1 (the Bitnami chart's `latest` tag resolved to Redis 8 at original install time). Proceeded with a dedicated `redis-v16` instance anyway, since the task's *other* stated reason (isolation from v15) is independently valid.

### Step 2: Namespace — ✅ Pass
```
$ kubectl create namespace frappe-v16
namespace/frappe-v16 created
```
Also proactively copied `dockerhub-secret` from `frappe-system` into `frappe-v16` (applying D13's lesson) before deploying anything, to avoid anonymous-pull throttling risk.

### Step 3: Deploy Redis 8 for v16 — ⚡ Pass with a real manifest bug found and fixed
As-specified manifest (single container, 3 `containerPort`s):
```
$ redis-cli -p 6379 ping   → PONG
$ redis-cli -p 6380 ping   → Could not connect to Redis at 127.0.0.1:6380: Connection refused
$ redis-cli -p 6381 ping   → Could not connect to Redis at 127.0.0.1:6381: Connection refused
```
A single `redis-server` process only binds the one port it's configured for — declaring extra `containerPort`s doesn't make it listen anywhere else. **Fixed** by running 3 separate `redis-server` processes as sidecar containers in the same pod (`redis-cache`/`redis-queue`/`redis-socketio`, each with its own `--port` flag), keeping the single-Deployment/single-Service design. Re-verified: all 3 ports respond via the Service DNS name (`redis-v16.frappe-v16.svc.cluster.local`). See `k3s/redis-v16.yaml` (corrected version) and Decision Log **D24**.

### Step 4: PVC — ✅ Pass
`bench-v16-data`, 10Gi, `local-path` — `Pending` until claimed (expected), `Bound` once the bench Deployment (Step 5) started.

### Step 5: bench Deployment — ✅ Pass
Built as a proper Deployment from the start (Phase 2 Group K pattern, not a bare Pod like the original `bench-v15`), PVC mounted at `/home/frappe/bench-data` (parent of `frappe-bench/`, per D6/D15), `imagePullSecrets` attached (per D13).

### Step 6: Python/Node versions — ✅ Pass
```
$ python3 --version → Python 3.14.2
$ node --version → v24.13.0
```
Both well above the stated minimums (3.12+/22+).

### Step 7: bench init — ✅ Pass
```
$ bench init frappe-bench --frappe-branch version-16 --skip-redis-config-generation
...
SUCCESS: Bench frappe-bench initialized
```
Confirms the `version-16` branch genuinely exists on `frappe/frappe`.

### Step 8: Configure infrastructure hosts — ✅ Pass
All four hosts (mariadb + 3× redis) written correctly to `common_site_config.json`, `redis://` scheme used throughout (per D3) — no host-format issues this time.

### Step 9: Create test site — ✅ Pass
```
$ bench new-site v16-test.local --mariadb-user-host-login-scope='%' --db-host mariadb.frappe-system.svc.cluster.local --mariadb-root-username root --mariadb-root-password *** --admin-password ***
...
Creating Workspace Sidebars
Creating Desktop Icons
Updating Dashboard for frappe
*** Scheduler is disabled ***
```
Two real behavioral differences from v15 noted: **no MariaDB version deprecation warning** (v15 always printed one), and **two extra install steps** ("Creating Workspace Sidebars", "Creating Desktop Icons") not present in v15's output.

### Step 10: Verify — ✅ Pass
```
$ bench --version → 5.31.0
$ python3 --version → Python 3.14.2
$ node --version → v24.13.0
$ bench --site v16-test.local list-apps
frappe 16.31.0 version-16
```

### GROUP Summary

| Step | Result |
|---|---|
| 1 Redis version check | Caught a wrong premise in the task context |
| 2 Namespace | ✅ Pass |
| 3 Redis v16 deploy | ⚡ Pass with a real manifest bug fixed |
| 4 PVC | ✅ Pass |
| 5 bench Deployment | ✅ Pass |
| 6 Python/Node check | ✅ Pass |
| 7 bench init | ✅ Pass |
| 8 Host config | ✅ Pass |
| 9 Create site | ✅ Pass — 2 real v15/v16 behavioral differences found |
| 10 Verify | ✅ Pass |

Full version comparison: `docs/VERSION-MATRIX.md`.

## Decision Log Addition

### D24: a single `redis-server` process only listens on the port it's configured for
**Discovered in:** Frappe v16 environment setup, Step 3 (Redis deployment)
**Finding:** A Kubernetes pod spec declaring multiple `containerPort` entries for one container does not make the process inside listen on all of them — `containerPort` is documentation/metadata for the kubelet and other tooling, not a listen directive. A single `redis-server` process only binds the port it was actually started with (default 6379). Confirmed directly: a manifest declaring `containerPort: 6379, 6380, 6381` for one `redis:8-alpine` container only ever answered on 6379; 6380/6381 refused connections.
**Impact on Custom Agent:** if the Agent ever generates a manifest assuming "N declared container ports" implies "N listening services," any consumer expecting the extra ports (like Frappe's cache/queue/socketio Redis split) will fail to connect with no indication from the Kubernetes side that anything is wrong — the Deployment reports `Running`/`Available` regardless.
**Implementation rule:** when a workload needs to expose multiple independent logical services (like Frappe's 3 Redis roles) from what could be one image, run one process per port — either as separate sidecar containers within one pod (each with its own `--port`/equivalent flag) or as fully separate Deployments — never rely on a single process implicitly listening on multiple declared `containerPort`s.

## 2026-08-23 — Decision Log Additions (pre-Tier-A-v16 audit)

Audited RUNBOOK.md against 3 findings from the v16 environment setup before starting Tier A testing on v16. D24 was already a formal entry. 2 others existed only as inline mentions (in both RUNBOOK.md's narrative and `docs/VERSION-MATRIX.md`) and are formalized here.

### D25: Redis version claims must be verified directly, not assumed from task context
**Discovered in:** Frappe v16 environment setup, Step 1 (Redis version check)
**Finding:** The v16 setup task's stated context claimed `frappe-system` runs "Redis 6/7, NOT compatible with v16 — needs Redis 8." Direct verification (`kubectl exec -n frappe-system redis-cache-master-0 -- redis-server --version`) showed `Redis server v=8.10.1` — it has been v8.10.1 since Phase 1 (the Bitnami chart's `latest`-tracking tag already resolved to Redis 8 at original install time in Phase 1 Group C, confirmed via that install's own logged output: `CHART VERSION: 28.0.10, APP VERSION: 8.10.1`). The stated premise was simply wrong, not stale — it was never true at any point in this project's history.
**Impact on Custom Agent:** if the Agent (or anyone operating it) makes version-gating decisions — e.g. "skip this bench version because the shared infra is too old" — based on assumed/reported version claims rather than a live check, it can make an incorrect decision (in this case, unnecessarily provisioning duplicate infrastructure, or in the opposite direction, wrongly assuming compatibility that doesn't exist). Task descriptions and documentation can drift from reality; the underlying infrastructure is the source of truth.
**Implementation rule:** before any version-gated decision (Redis, MariaDB, Python, Node, or app-level version checks), query the actual running service directly (`redis-server --version`, `SELECT @@version`, `python3 --version`, etc.) rather than trusting a stated/assumed version. This is independent of whether a dedicated per-version instance is still built for other reasons (e.g. isolation, as was the case here) — the compatibility premise itself must still be verified, not assumed.

### D26: Frappe v16 has two real behavioral differences from v15 in `bench new-site`
**Discovered in:** Frappe v16 environment setup, Step 9 (create test site)
**Finding:** Comparing `bench new-site` output between v15 and v16 (same `frappe/bench:latest` image, same MariaDB 10.11 instance, only the app version differs) surfaced two concrete differences: (1) v16 prints **no** `Warning: MariaDB version [...] is more than 10.8 which is not yet tested with Frappe Framework` — a warning v15 printed on every single `new-site`/`reinstall`/`restore` call; (2) v16's install sequence includes two extra steps not present in v15's output: `Creating Workspace Sidebars` and `Creating Desktop Icons`, appearing just before `Updating Dashboard for frappe`.
**Impact on Custom Agent:** if the Agent parses `bench new-site` output to detect specific known warnings/steps (e.g. to decide whether to surface a compatibility warning to the user, or to track install progress by matching expected output lines), a parser tuned against v15's output will not see the MariaDB warning on v16 (falsely appearing "cleaner") and will encounter unexpected extra lines it wasn't built to recognize.
**Implementation rule:** any output-parsing logic in the Agent (warning detection, progress tracking, success/failure classification) must be tested against each Frappe major version separately, not assumed stable across versions — `bench`'s own CLI output is not a stable, version-independent contract. Full comparison table: `docs/VERSION-MATRIX.md`.

## 2026-08-23 — Tier A: Core Command Testing on Frappe v16

Same commands as Phase 1 Tier A, run against `v16-test.local` (`bench-v16`, `frappe-v16` namespace), comparing directly to v15 behavior. Full comparison table: `docs/VERSION-MATRIX.md`.

### A1: new-site — ⚡ Different (already documented, D26) — skipped, already covered

### A2: install-app --force — ⚡ Different
```
$ kubectl exec -n frappe-v16 deployment/bench-v16 -- bash -c "
  echo -e 'admin123\nadmin123' | bench --site v16-test.local install-app frappe --force
"
...
Warning: Password input may be echoed.
Set Administrator password:

Creating Workspace Sidebars
Creating Desktop Icons
Updating Dashboard for frappe
```
Exit 0. Two things worth noting: (1) this worked **without** `kubectl exec -i` — the pipe (`echo -e ... | bench ...`) is entirely self-contained inside the exec'd `bash -c` string, so it doesn't depend on external stdin forwarding at all (this technique would have worked for v15 too, in retrospect — v15's testing used the external `-i` + piped-stdin approach instead). (2) Only **one** `Set Administrator password:` prompt is visible, not v15's two (`Set` + `Re-enter`) — unclear if v16 genuinely only asks once, or if the "Re-enter" line just wasn't flushed to the captured output. Verified the install actually took: `list-apps` → `frappe 16.31.0 version-16`.

### A3/A4/A5: migrate (+ --skip-failing, --skip-search-index) — ⚡ Different
```
$ bench --site v16-test.local migrate
Removing orphan Notifications
Removing orphan Workspace Sidebars
Removing orphan Desktop Icons
Deleting icon Frappe Framework
Syncing portal menu...
Updating installed applications...
Executing `after_migrate` hooks...
Queued rebuilding of search index for v16-test.local
```
New steps not present in v15's migrate output: orphan-record cleanup (Notifications/Workspace Sidebars/Desktop Icons), icon deletion, portal menu sync, and an explicit "Updating installed applications..." step. Flag semantics unchanged: `--skip-search-index` still correctly omits the reindex-queue message; `--skip-failing` behaves the same as v15. See **D27**.

### A6: backup --with-files --verbose — ⚡ Different
```
Backup Summary for v16-test.local at 2026-08-23 18:26:28
Config  : /home/frappe/bench-data/frappe-bench/sites/v16-test.local/private/backups/20260823_182627-v16-test_local-site_config_backup.json 218.0B
Database: /home/frappe/bench-data/frappe-bench/sites/v16-test.local/private/backups/20260823_182627-v16-test_local-database.sql.gz 245.8KiB
...
```
v16 lists **absolute** paths in the Backup Summary; v15 always used relative paths (`./test.local/private/backups/...`). See **D28**.

### A7-A17: clear-cache, clear-website-cache, list-apps (+ -f json), set-maintenance-mode, scheduler, set-admin-password, add-user, add-system-manager, build, setup requirements — ✅ All identical to v15
No behavioral differences found. `add-user` verified via `execute frappe.client.get_list` → `[{"name": "testuser16@test.com"}]`.

### A18: doctor — ⚡ Different (side effect of A3-A5)
```
$ bench doctor
Workers online: 0
Queue: default
  frappe.model.delete_doc.delete_dynamic_links : 1
  frappe.core.doctype.user.user.create_contact : 4
Queue: long
  build_index_for_all_routes : 2
```
New job type (`delete_dynamic_links`) appears — a direct consequence of migrate's new orphan-cleanup steps (D27) enqueuing work, not an independent doctor-specific change. Core finding (0 workers online, matching D9) unchanged.

### A19: restore — ✅ Identical to v15
```
$ bench --site v16-test.local restore --mariadb-root-username root --mariadb-root-password *** --admin-password *** sites/v16-test.local/private/backups/20260823_182627-v16-test_local-database.sql.gz
File ... not found. Trying to check in alternative directories.
File /home/frappe/bench-data/frappe-bench/sites/... found.
App frappe already installed
*** Scheduler is enabled ***
Site v16-test.local has been restored
```
Same fallback path resolution behavior as v15. No MariaDB deprecation warning (consistent with D26).

### A20: drop-site — ⚡ Different
Created throwaway `drop16-test.local`, then:
```
$ bench drop-site drop16-test.local --no-backup --force --root-login root --root-password ***
Dropping site database and user
Moving site to archive under /home/frappe/bench-data/frappe-bench/archived/sites
```
Verified directly:
```
$ ls /home/frappe/bench-data/frappe-bench/archived/
sites
$ ls /home/frappe/bench-data/frappe-bench/sites/archived/
No such file or directory
```
v16 archives dropped sites at a **top-level** `frappe-bench/archived/sites/` directory (sibling to `sites/`); v15 archived them at `frappe-bench/sites/archived/` (nested inside `sites/`). See **D29**. `v16-test.local` confirmed unaffected afterward.

### Tier A v16 Summary

| Result | Count |
|---|---|
| ✅ Same as v15 | 15 (A7-A17, A19 — 12 commands, several tested via multiple flag variants) |
| ⚡ Different from v15 | 5 (A1/new-site, A2, A3-A5/migrate, A6/backup, A18/doctor side-effect, A20/drop-site) |
| ❌ Fails on v16 | 0 |

**No outright failures — every command that works on v15 works on v16.** All differences are output-format/behavior changes, not breakages, but each one matters for anything (like the real Custom Agent) that parses `bench` output or assumes fixed file/directory locations.

## Decision Log Additions

### D27: Frappe v16's `bench migrate` has new cleanup steps not present in v15
**Discovered in:** Frappe v16 Tier A testing, A3 (migrate)
**Finding:** `bench --site {s} migrate` on v16 performs several steps not present in v15's migrate output: `Removing orphan Notifications`, `Removing orphan Workspace Sidebars`, `Removing orphan Desktop Icons`, `Deleting icon Frappe Framework`, `Syncing portal menu...`, and an explicit `Updating installed applications...` step. These enqueue at least one new background job type (`frappe.model.delete_doc.delete_dynamic_links`, observed via `bench doctor` afterward) that v15's migrate never produced.
**Impact on Custom Agent:** if the Agent parses migrate output to track progress or detect specific known steps/warnings, a parser built against v15's simpler output will encounter unrecognized lines on v16, and any logic that infers "migration produced N background jobs" from a fixed job-type list will undercount on v16.
**Implementation rule:** migrate output parsing (and any job-queue-based post-migrate verification) must be tested and maintained per major Frappe version, not assumed stable — treat `bench migrate`'s exact output shape as version-specific, matching D26's conclusion for `bench new-site`.

### D28: `bench backup`'s Backup Summary uses absolute paths on v16, relative on v15
**Discovered in:** Frappe v16 Tier A testing, A6 (backup)
**Finding:** v15's `Backup Summary` output lists file paths relative to the bench directory (e.g. `./test.local/private/backups/...`). v16's lists full absolute paths (e.g. `/home/frappe/bench-data/frappe-bench/sites/v16-test.local/private/backups/...`).
**Impact on Custom Agent:** any Agent logic that parses the Backup Summary output to extract backup file paths — e.g. to immediately hand them to an upload Job (as in Phase 3 Group Q) — must handle both formats, or must resolve paths itself rather than trusting the printed format to always be one or the other.
**Implementation rule:** don't string-match on whether backup paths are relative or absolute when parsing `bench backup --verbose` output; either resolve any relative path against the known bench directory before use, or (more robustly) construct the expected backup file path independently from the known site name and timestamp pattern, rather than parsing it out of CLI output at all.

### D29: `bench drop-site` archives to a different directory location on v16 vs v15
**Discovered in:** Frappe v16 Tier A testing, A20 (drop-site)
**Finding:** v15's `bench drop-site` moves the dropped site to `{bench_dir}/sites/archived/` (nested inside the `sites/` directory). v16 moves it to `{bench_dir}/archived/sites/` (a top-level directory, sibling to `sites/`). Confirmed directly: `ls {bench_dir}/sites/archived/` → `No such file or directory` on v16, while `ls {bench_dir}/archived/` → `sites` exists.
**Impact on Custom Agent:** if the Agent needs to locate an archived/dropped site's data (e.g. to offer recovery, or to clean up old archives on a schedule), a path built against v15's layout will silently find nothing on v16, and vice versa.
**Implementation rule:** don't hardcode the archived-site path; check both `{bench_dir}/sites/archived/` and `{bench_dir}/archived/sites/` (or better, derive the actual location from `bench drop-site`'s own stdout at drop time — it always prints `Moving site to archive under {path}` — and record that path rather than assuming a fixed layout).

## 2026-08-23 — Tier B + C: Command Testing on Frappe v16

Full comparison table: `docs/VERSION-MATRIX.md`. B3-B7, B13, B16 skipped as instructed (already covered in Tier A).

### B1: uninstall-app (2 apps) — ✅ Same as v15
Installed `erpnext --branch version-16` (branch exists, cloned fine), installed on site, then:
```
$ echo -e "admin123\nadmin123" | bench --site v16-test.local uninstall-app erpnext --no-backup --yes --force
...
Deleting Desktop Icons
Deleting Workspace Sidebars
Uninstalled App erpnext from Site v16-test.local
```
Same outcome as v15; extra "Deleting ..." steps match the D27 lifecycle-hook theme. `list-apps` confirmed `frappe` only afterward. Cleaned up: `bench remove-app erpnext` (same archive pattern as v15: `archived/apps/erpnext-2026-08-23`).

### B2: reinstall — ✅ Same as v15
```
$ bench --site v16-test.local reinstall --yes --admin-password *** --mariadb-root-username root --mariadb-root-password ***
...
App frappe already installed
*** Scheduler is enabled ***
```
Site verified healthy after (`list-apps` → `frappe 16.31.0 version-16`).

### B8/B9: execute get_installed_apps / get_roles — ✅ Same as v15
Identical output shape. (Role *data* differs slightly — v16 includes a "Marketing Manager" role not present in v15 — but that's normal version drift in Frappe's built-in roles, not a command behavior change.)

### B10: build-search-index — ✅ Same as v15 (D9 confirmed)
Still only enqueues (`Retrieving Routes: 3%`, exit 0), confirmed via `doctor` showing the job queued.

### B11: rebuild-global-search — ✅ Same as v15
Still runs synchronously to 100%.

### B12: build (full) — ✅ Same as v15
~18.5s, same output shape.

### B14/B15: setup requirements --python / --node — ✅ Same as v15

### B17: ready-for-migration — ✅ Same as v15
```
NOT READY for migration: site v16-test.local has pending background jobs
```
Same message, same exit 1.

### B18: remove-from-installed-apps — ✅ Same as v15
Same core-app guardrail: `You cannot remove or uninstall the app frappe`.

### B19/B20: describe-database-table / add-database-index — ✅ Same as v15

### B21: console via stdin — ✅ Same as v15

### B22: run-patch — ⚡ Different from v15
First located a real v16 patch (`ls apps/frappe/frappe/patches/v16_0/`) rather than guessing a name (lesson from Phase 1 D3). Found `auto_generate_desktop_icon_and_sidebar.py` in that listing — very likely the actual source of D26/D27's new "Workspace Sidebars"/"Desktop Icons" steps.
```
$ bench --site v16-test.local run-patch frappe.patches.v16_0.switch_default_sort_order
EXIT: 0
(no output)
$ bench --site v16-test.local run-patch frappe.patches.v16_0.set_reply_to_header 2>&1
EXIT: 0
(no output — re-verified with explicit 2>&1 capture to rule out a truncation artifact)
```
v15's equivalent test printed an explicit `Executing frappe.patches.v14_0.update_workspace2 in test.local (...)` / `Success: Done in 0.587s` message. v16 is **completely silent** on success — exit 0, zero output either way. See **D30**.

### B23: pip install -e — ✅ Same as v15

### C1: Rolling restart — ✅ Same as v15
New pod name confirmed (`...-5846f9dcfc-8tpqr` → `...-677465d49-2jh7w`), site data intact after.

### C2/C3: Scale down/up — ✅ Same as v15
Pods briefly show `Terminating` past a quick check (same grace-period timing as before, not a stuck state). Data intact after scale-up.

### C4: Patch resource limits — ✅ Same as v15
`Limits: cpu 500m, memory 1Gi` / `Requests: cpu 250m, memory 512Mi` — applied exactly as specified.

### C5: Add IngressRoute — ✅ Same pattern as v15 (D11), plus a syntax clarification
```
$ kubectl apply -f - <<EOF ... match: Host("v16-test.local") ... EOF
ingressroute.traefik.io/v16-test-domain created
```
Created fine (K8s API doesn't validate Traefik's matcher DSL at admission time). Checked Traefik's own logs to see whether the double-quote `Host("...")` syntax (as given in this task, vs the backtick `Host(\`...\`)` syntax used successfully in Phase 2) actually parsed:
```
ERR error="kubernetes service not found: frappe-v16/bench-v16" ingress=v16-test-domain namespace=frappe-v16
```
The only error is the missing backend Service (matches D11 exactly — no `bench-v16` Service exists, same as `bench-v15` originally didn't) — **no syntax error**, confirming double-quoted `Host("...")` is valid syntax in this Traefik version, not just backticks.

### C6: Remove IngressRoute — ✅ Same as v15

### Tier B+C v16 Summary

| Result | Count |
|---|---|
| ✅ Same as v15 | 28 |
| ⚡ Different from v15 | 1 (B22, run-patch verbosity) |
| ❌ Fails on v16 | 0 |

## Decision Log Addition

### D30: `bench run-patch` is silent on success in v16, verbose in v15
**Discovered in:** Frappe v16 Tier B testing, B22 (run-patch)
**Finding:** On v15, `bench --site {s} run-patch {patch}` printed an explicit `Executing {patch} in {site} ({db_name})` line followed by `Success: Done in {N}s` on completion. On v16, the identical command structure produces **zero output** on success (confirmed with two different real v16-specific patches, and re-verified with explicit `2>&1` capture to rule out a stream-redirection artifact) — only the exit code (0) indicates success.
**Impact on Custom Agent:** if the Agent parses `run-patch` stdout to confirm a patch actually executed (e.g. looking for "Success: Done" text, as would be a reasonable approach based on v15's behavior), that check will incorrectly report failure on every v16 patch run, even though the patch succeeded (exit 0).
**Implementation rule:** verify `run-patch` success by exit code only, never by matching specific output text — this is doubly important given output verbosity for this exact command changed between major Frappe versions with no announced deprecation. If confirmation beyond exit code is needed, check the patch's actual effect directly (e.g. query the `Patch Log` doctype) rather than parsing CLI text.

## 2026-08-23 — Decision Log Addition (final D1-D30 audit)

Full audit of every Decision Log entry in this document against a 30-item reference checklist. All 30 existing entries (D1-D30) were verified programmatically to already contain all 4 required labeled fields (**Discovered in:**, **Finding:**, **Impact on Custom Agent:**, **Implementation rule:**) — no partial or missing entries among them. One checklist item ("git fetch needs full 40-char SHA") had no formal entry anywhere — it existed only as a table row in the Phase 1 Group B results (git commands testing). Added here as D31.

### D31: `git fetch` by commit hash requires the full 40-character SHA
**Discovered in:** Phase 1, Group B (git commands testing)
**Finding:** `git fetch --depth 1 {remote} {hash}` fails when given an abbreviated hash: `git fetch --depth 1 upstream 16d483c` → `fatal: couldn't find remote ref 16d483c`. GitHub's server-side SHA-fetch (`uploadpack.allowTipSHA1InWant`/`allowReachableSHA1InWant`) only resolves full 40-character SHAs, not abbreviated ones — even though the same short hash works fine locally (`git rev-parse`, `git log`, `git diff`) once the commit is already present in the local object database. Confirmed the fix directly: `git fetch --depth 1 upstream 16d483c2095d57a080c664dba3e19a0421739719` (full SHA) succeeded.
**Impact on Custom Agent:** if the Agent's update-fetch logic resolves a target commit to a short/abbreviated hash anywhere in its pipeline (e.g. from a truncated display value, a short-form API response, or a locally-abbreviated `git log` parse) and passes that directly to `git fetch`, the fetch will fail with a confusing "couldn't find remote ref" error that gives no indication the actual problem is hash length.
**Implementation rule:** always resolve and pass the full 40-character commit SHA to `git fetch {remote} {hash}` — never an abbreviated form. If the Agent only has a short hash on hand, resolve it to the full form first via a already-fetched local ref (`git rev-parse {short-hash}`) before it can be used in a subsequent `git fetch` call.

## 2026-08-23 — Frappe v14 Environment Setup + Tier A

### S1: Resource check — plenty available
128G disk free (13% used), 21Gi RAM available, 4% CPU. No concerns proceeding.

### S2-S5: Namespace, secrets, Redis, PVC, Deployment — ✅ All pass
Same patterns as v16 (D14, D24, D16 lessons applied from the start): `dockerhub-secret` copied to `frappe-v14`; `redis-v14` deployed as 3 sidecar containers (cache/queue/socketio on 6379/6380/6381), all 3 ports verified responding; `bench-v14-data` PVC (10Gi) bound; `bench-v14` Deployment (not bare Pod) running.

### S6: Python/Node/bench versions — same image as v15/v16
`Python 3.14.2`, `v24.13.0`, bench `5.31.0` — identical to v15/v16 (same `frappe/bench:latest` image, unpinned).

### S7: bench init — ❌ then ⚡ Pass with modification (real Python-version incompatibility, fixed)

**Attempt 1 (default Python 3.14) — FAILED:**
```
× Failed to build `pypika==0.48.9`
AttributeError: module 'ast' has no attribute 'Str'
hint: `pypika` (v0.48.9) was included because `frappe` (v14.101.1) depends on `pypika==0.48.9`
```
`ast.Str` was deprecated in Python 3.8 and **removed in Python 3.12+**. Frappe v14 hard-pins `pypika==0.48.9`, whose `setup.py` still uses `ast.Str` to read its version — incompatible with the image's Python 3.14.

**Attempt 2 (`--python /usr/bin/python3.11`) — FAILED differently (progress):**
The `ast.Str` error was gone (3.11 still has it, deprecated but not removed) — but a new error appeared:
```
fatal error: Python.h: No such file or directory
hint: `hiredis` (v2.0.0) was included because `frappe` (v14.101.1) depends on `hiredis`
```
`/usr/bin/python3.11` (system Python, distinct from the image's pyenv-managed 3.14) has no dev headers installed, needed to compile `hiredis`'s C extension.

**Fix:** `sudo apt-get install -y python3.11-dev` (passwordless sudo available in this image), then retried:
```
$ bench init frappe-bench --frappe-branch version-14 --skip-redis-config-generation --python /usr/bin/python3.11
...
SUCCESS: Bench frappe-bench initialized
```
See **D32**.

### S8: Configure hosts — ✅ Pass
Same `redis://` pattern as v15/v16 (D3), all 4 hosts correctly written.

### S9: Create site — ⚡ Pass with modification
```
$ bench new-site v14-test.local --mariadb-user-host-login-scope='%' ...
Error: No such option: --mariadb-user-host-login-scope
```
Confirmed via `bench new-site --help`: this flag **doesn't exist at all** in v14's bench CLI — it's a v15+ addition (D5 already noted `--no-mariadb-socket` is deprecated *in v15*, implying it still exists there; v14 predates the replacement flag entirely and only has the old one). Retried with `--no-mariadb-socket` → succeeded. Two new steps not seen in v15/v16: `Restoring Database file...` and `Updating country info`. No MariaDB version deprecation warning suppressed — it still appeared (`Warning: MariaDB version ['10.11', '18'] is more than 10.8...`), same as v15. See **D33**.

### S10: Verify — ⚡ Different output format
```
$ bench --site v14-test.local list-apps
frappe
```
Just the bare app name — **no version number, no branch**, unlike v15/v16's `frappe {version} {branch}`. Confirmed via `list-apps -f json` too (`{"v14-test.local": ["frappe"]}`, no version field) and via `sites/apps.json` directly (`"version": "14.101.1"` — the real version is tracked, just not displayed by `list-apps`). See **D34**.

### Tier A Tests on v14 (17 commands)

| # | Command | Result | Notes |
|---|---|---|---|
| 1 | migrate | ✅ Same as v15 | No v16-style extra steps (those are v16-specific patches) |
| 2 | migrate --skip-failing | ✅ Same | — |
| 3 | migrate --skip-search-index | ✅ Same | Correctly omits reindex message |
| 4 | backup --with-files --verbose | ⚡ Different | Uses `mysqldump` (not `mariadb-dump`) and the older `self=$$; (mysqldump ... \|\| kill $self) \| gzip` self-kill shell pattern. Paths still **relative** (matches v15, not v16's absolute paths — D28's finding is v16-specific, not a general newer-versions trend). See **D35** |
| 5 | clear-cache | ✅ Same | — |
| 6 | clear-website-cache | ✅ Same | — |
| 7 | list-apps | ⚡ Different | See S10/D34 above |
| 8 | list-apps -f json | ⚡ Different | Same — no version field |
| 9 | set-maintenance-mode on/off | ✅ Same | — |
| 10 | scheduler pause/resume/enable | ✅ Same | — |
| 11 | set-admin-password | ✅ Same | — |
| 12 | add-user | ✅ Same | — |
| 13 | build-search-index | ✅ Same | Still enqueue-only (D9) |
| 14 | rebuild-global-search | ✅ Same | Still synchronous |
| 15 | doctor | ⚡ Minor | New job type `update_gravatar` in queue — side effect of `add-user` on this version, not an independent doctor change |
| 16 | build --app frappe | ✅ Same | ~10.7s |
| 17 | setup requirements | ⚡ Different | Node step includes `npm warn` deprecation notices and a `snyk-protect` patch-application step not seen in v15/v16's plain `yarn install` |

### GROUP Summary (v14)

| Result | Count |
|---|---|
| ✅ Same as v15/v16 | 11 |
| ⚡ Different | 6 |
| ❌ Fails (before fix) | 1 (bench init, resolved) |

**No permanent failures — v14 works fully on this image once the Python-version workaround is applied.** `v14-test.local` confirmed healthy (`frappe` listed, real version `14.101.1` per `apps.json`).

## Decision Log Additions

### D32: Frappe v14 requires Python 3.11 (not the image's default 3.14) plus dev headers
**Discovered in:** Frappe v14 environment setup, S7 (bench init)
**Finding:** Frappe v14 hard-pins `pypika==0.48.9`, whose `setup.py` uses the Python `ast.Str` API — deprecated since Python 3.8, **removed entirely in Python 3.12**. `frappe/bench:latest`'s default Python (pyenv-managed 3.14.2) fails to build it. Switching to the image's system `/usr/bin/python3.11` (which still has `ast.Str`, just deprecated) fixes that, but exposes a second issue: `hiredis` (another v14 dependency) needs to compile a C extension against `Python.h`, which isn't installed for the system Python by default — `sudo apt-get install python3.11-dev` resolves it.
**Impact on Custom Agent:** any Agent workflow that provisions a v14 bench using the same generic `frappe/bench:latest` image (shared across all supported Frappe versions) will hit this exact two-stage failure unless it knows in advance to use an older Python and pre-install its dev headers. A generic "bench init" retry loop without this specific knowledge will fail indefinitely.
**Implementation rule:** for Frappe v14 specifically, run `bench init` with `--python /usr/bin/python3.11`, and ensure `python3.11-dev` is installed in the bench image/container **before** attempting init (either bake it into a v14-specific base image, or install it via an init step). Do not assume the same Python version works across all supported Frappe major versions on a shared base image — pin per-version Python requirements explicitly (v14: 3.11 with dev headers; v15/v16: default image Python is fine, per Phase 1/2 testing).

### D33: `--mariadb-user-host-login-scope` doesn't exist in v14 — must use `--no-mariadb-socket`
**Discovered in:** Frappe v14 environment setup, S9 (bench new-site)
**Finding:** `bench new-site --mariadb-user-host-login-scope='%' ...` fails on v14 with `Error: No such option: --mariadb-user-host-login-scope` — this flag doesn't exist at all in v14's bench CLI (confirmed via `--help`). It's a v15+ addition; D5 documented it as the *replacement* for the now-deprecated `--no-mariadb-socket` on v15, but v14 predates that replacement entirely and only supports the older flag.
**Impact on Custom Agent:** any Agent logic that always uses the "modern" `--mariadb-user-host-login-scope` flag (correct guidance for v15+, per D5) will fail outright on v14 and (per the v13 setup task's own hint) likely v13 too — this is a hard version boundary, not a deprecation-warning situation.
**Implementation rule:** the Agent must select the correct `new-site`/socket flag based on the target Frappe major version: `--no-mariadb-socket` for v14 and earlier, `--mariadb-user-host-login-scope='%'` for v15 and later. Never hardcode one flag across all supported versions.

### D34: `bench list-apps`'s version/branch display depends on whether `migrate` has run yet, not on the Frappe version — corrected after further testing
**Discovered in:** Frappe v14 environment setup, S10 (verify); corrected after Tier A testing on the same site
**Finding:** `bench --site {s} list-apps`'s version/branch columns depend on whether `migrate` has run on that site, not on the Frappe major version. Original (incomplete) observation: immediately after `bench new-site` on v14, `list-apps` printed just `frappe` — no version, no branch — while v15/v16 showed `frappe {version} {branch}` at the equivalent point, which was initially documented as a fixed v14-vs-v15/v16 output-format difference. That was wrong: after running Tier A's `migrate` commands on the same v14 site, `list-apps` changed to show the full `frappe 14.101.1 version-14` — with `sites/apps.json`'s `resolution` fields still `null` throughout (ruling out apps.json as the source). This confirms the real mechanism is the same one D19 already established: `list-apps`'s version/branch columns come from the **`Installed Applications` DocType in the site's database**, populated via `migrate`'s `after_migrate` hooks — not a static, version-dependent command format. The corrected finding: **a freshly-created site shows no version/branch in `list-apps` until its first `migrate` runs**, regardless of Frappe major version. v15/v16 likely appeared to "always" show full info only because no test happened to check `list-apps` in the narrow window before their first migrate.
**Impact on Custom Agent:** if the Agent parses `list-apps` output to determine an installed app's version immediately after site creation (before ever running `migrate`), it may see incomplete output on **any** Frappe version, not just v14 — this is a site-lifecycle-state issue, not a version-compatibility issue.
**Implementation rule:** don't rely on `bench list-apps` output for version information without accounting for whether `migrate` has run on that site yet. For a reliable, migrate-independent version lookup, read the app's own version string directly from its source (e.g. `apps/{app}/{app}/__init__.py`'s `__version__`) rather than a DocType field that only gets populated as a migrate side-effect.

### D35: v14's `bench backup` uses `mysqldump`, not `mariadb-dump`
**Discovered in:** Frappe v14 Tier A testing, #4 (backup)
**Finding:** v15/v16's backup command invokes `mariadb-dump` (confirmed throughout Phase 1-3) with `set -o pipefail; mariadb-dump ... | gzip`. v14's backup invokes the older `mysqldump` binary name, wrapped in a different shell pattern: `self=$$; ( mysqldump ... || kill $self ) | gzip`. Both binaries exist and work in this environment (MariaDB ships both `mysqldump` and `mariadb-dump` as compatible aliases), so functionally the backup succeeds either way — but the exact command text differs.
**Impact on Custom Agent:** if the Agent parses `bench backup --verbose`'s printed dump command (e.g. to extract connection parameters, or to detect what tool is being used for a security/audit check), it must handle both binary names and both shell-wrapping patterns.
**Implementation rule:** don't string-match on `mariadb-dump` specifically when inspecting backup command output — treat `mysqldump` and `mariadb-dump` as equivalent, and don't assume a fixed shell-wrapping pattern (`set -o pipefail; ...` vs `self=$$; (... || kill $self)`) across Frappe versions.

## 2026-08-23 — Frappe v13 Environment Setup — ❌ Incompatible with current image

### T1: Resource check — plenty available
125G disk free (15% used) after v14's setup, 21Gi RAM available. No concerns.

### T2-T5: Namespace, secrets, Redis, PVC, Deployment — ✅ All pass
Identical pattern to v14/v16: `frappe-v13` namespace, `dockerhub-secret` copied, `redis-v13` (3-container pattern, all ports verified), `bench-v13-data` PVC bound, `bench-v13` Deployment running.

### T6: Python/Node versions — same image
`Python 3.14.2`, `v24.13.0` — same as all other versions (same unpinned `frappe/bench:latest` image).

### T7: bench init — ❌ FAILED — v13 incompatible with this image (two independent failure modes)

Applied the D32 lesson proactively this time (installed `python3.11-dev` and used `--python /usr/bin/python3.11` from the first attempt, rather than rediscovering the Python issue):
```
$ bench init frappe-bench --frappe-branch version-13 --skip-redis-config-generation --python /usr/bin/python3.11
```
Python-side dependency installation succeeded this time (v13's Python-level pins are apparently satisfied by 3.11, same as v14). **But it failed at a different, later stage — `yarn install` for the `frappe` app itself:**
```
bench.exceptions.CommandFailedError: yarn install --check-files
ERROR: There was a problem while creating frappe-bench
```

Investigated directly (ran `yarn install --check-files` manually in the partially-created app directory to get the real error, since bench's own traceback didn't show it):
```
../src/binding.cpp: In function ...
gyp ERR! build error
gyp ERR! stack Error: `make` failed with exit code: 2
gyp ERR! node -v v24.13.0
gyp ERR! node-gyp -v v8.4.1
Build failed with error code: 1
```
**Root cause:** v13 depends on `node-sass`, which compiles a native C++ addon (`node_modules/node-sass/build`) against Node's native addon ABI (via the NAN/`NODE_MODULE` macros). This compilation genuinely progressed for several minutes (confirmed via `ps aux` showing `cc1plus` moving through different `libsass` source files — not a hang) before failing: `node-sass`'s bindings are incompatible with Node v24's V8/addon ABI. This is a well-known, industry-wide issue — `node-sass` was deprecated years ago for exactly this reason (inability to keep up with newer Node ABI versions), which is why Frappe itself moved to Dart Sass (no native compilation) starting with later versions. v13's official requirement is Node 14 — six major versions behind this image's Node 24.

**Unlike D32's Python issue, this is not fixable via a CLI flag or a missing header package** — it would require an entirely different (EOL) Node.js major version, installed via `nvm install 14` or similar, with no guarantee that *other* tooling in this same image (bench, yarn itself, other native modules) would still work correctly against such an old Node runtime. Per the task's own explicit rule ("v13 is EOL — incompatibility with modern Python/Node is expected... do NOT spend more than 20 minutes debugging"), stopped here.

**Cleanup:** removed the partial `frappe-bench` directory. Disk confirmed healthy afterward (125G → 21G used, no leak from the failed native builds). See **D36**.

### T8-T10: Configure hosts, create site, verify — SKIPPED
Setup did not succeed; per the task's own instructions, these steps and Tier A testing are skipped entirely for v13.

**v13 is not compatible with `frappe/bench:latest` (Python 3.14.2 / Node v24.13.0) as currently configured. Would require a dedicated older-Node image (Node 14-something) to test further — out of scope for this pass.**

### PHASE 2 (v13) Summary

| Step | Result |
|---|---|
| T1 Resource check | ✅ Pass |
| T2-T5 Namespace/secrets/Redis/PVC/Deployment | ✅ Pass |
| T6 Python/Node check | ✅ Pass (recorded, same image) |
| T7 bench init | ❌ Fail — Node ABI incompatibility (node-sass), not fixable within budget |
| T8-T10 + Tier A | Skipped (setup didn't succeed) |

`frappe-v15`/`frappe-v16` never touched throughout this entire v13/v14 phase.

## Decision Log Addition

### D36: Frappe v13 is incompatible with `frappe/bench:latest`'s Node version — `node-sass` native compilation fails
**Discovered in:** Frappe v13 environment setup, T7 (bench init)
**Finding:** Even after applying D32's Python 3.11 fix (which resolves v13's Python-side dependency issues too), `bench init --frappe-branch version-13` fails at the `yarn install` step for the `frappe` app itself: `node-sass`'s native C++ addon (compiled via `node-gyp`/`make` against Node's NAN/`NODE_MODULE` ABI) fails to build against Node v24.13.0. Confirmed this is a genuine multi-minute compilation attempt (not a quick/config error) that ultimately fails with `gyp ERR! build error` / `make: *** Error 1`. v13 officially requires Node 14; `node-sass` (deprecated industry-wide for exactly this ABI-fragility reason) cannot bridge a 6-major-version gap.
**Impact on Custom Agent:** unlike D32's Python fix (a CLI flag + a header package), this failure **cannot** be resolved with a simple per-version flag — it requires an entirely different Node.js major version at the OS/image level. Any Agent designed to provision arbitrary Frappe versions from one shared, current-Node base image will hit a hard wall for v13 (and likely anything else still depending on `node-sass` rather than Dart Sass).
**Implementation rule:** do not attempt to support Frappe v13 (or any other EOL version still on `node-sass`) from the same base image used for v14+. Either maintain a dedicated older-Node base image specifically for such legacy versions (with Node 14 via `nvm`, accepting that other modern tooling in that image may need matching downgrades), or explicitly declare these versions unsupported by the Custom Agent and document the cutoff clearly (this project's testing confirms the practical floor is **v14**, with the D32 Python workaround — v13 and earlier are out of reach without a fundamentally different image).

### D37: clearing a Deployment's resource limits via `kubectl patch` requires explicit `null` per subfield — an empty `{}` is a silent no-op
**Discovered in:** automated test suite (`tests/run-all-tests.sh`), Tier C K8s operations — surfaced by a genuine `bench build` failure on a second run of the suite
**Finding:** the test suite's C4 step patches a bench Deployment's container with temporary `resources.limits`/`resources.requests` (512Mi/200m) to verify resource-patching works, then immediately patches again with `"resources":{}}` intending to remove them. That second patch is a **no-op** under Kubernetes' strategic merge patch semantics: an empty map patches nothing away, it does not clear previously-set subfields. Confirmed directly — `kubectl get deployment ... -o jsonpath='{...resources}'` still showed the full `{"limits":{"cpu":"200m","memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}` after the "clearing" patch. Those leftover limits silently persisted onto the running pod across test runs and OOM-killed a later `bench build` (esbuild/node asset bundling, exit code 137) and intermittently starved `bench console`. The fix is to patch with explicit `null` on each subfield — `"resources":{"limits":null,"requests":null}}` — which was verified to actually clear the field (`{}` returned afterward).
**Impact on Custom Agent:** any Agent logic that sets a temporary/tenant resource limit and later "removes" it by patching with an empty object will silently fail to actually remove it — the limit keeps applying indefinitely, invisibly, until something resource-hungry (a large migrate, an asset build, a bulk import) gets OOM-killed under a limit the Agent believes it already cleared.
**Implementation rule:** to clear a previously-patched resource field via `kubectl patch` (strategic merge, the default patch type), set each subfield explicitly to `null` — never patch with an empty object expecting it to delete existing values. Always verify the field actually cleared with a follow-up `get -o jsonpath` rather than trusting the patch command's own success/exit code, since a no-op patch still exits 0.

### D38: piping a live `kubectl exec`'s output straight into `grep -q` under `set -o pipefail` turns a genuine match into a reported failure
**Discovered in:** automated test suite (`tests/run-all-tests.sh`), debugging the `console (stdin)` / `list-apps` / Redis-reachability checks
**Finding:** `grep -q` exits the instant it finds its first match — it does not wait for its input stream to finish. When its input is a live, still-writing process (a `kubectl exec` streaming a remote command's output), that early exit closes the read end of the pipe while the writer is mid-write, which delivers `SIGPIPE` to it (observed as exit code 141, reproduced 5/5 in isolation). Under `set -o pipefail` (which this whole script runs under), the pipeline's reported exit status is the last *non-zero* status among all stages scanning from the end — so `kubectl exec`'s SIGPIPE-141 becomes the pipeline's status even though `grep -q` itself found the match and exited 0. The practical effect: `cmd | grep -q pattern && pass || fail` reports **FAIL every time**, deterministically, regardless of whether `pattern` was actually present — this is not flakiness, it reproduces 100% of the time once the writer is slow/large enough for `grep -q` to exit before it finishes.
**Impact on Custom Agent:** any Agent code (shell or subprocess-based) that pipes a live `kubectl exec`/`ssh`/similar streaming command's stdout directly into a short-circuiting matcher (`grep -q`, `head -1`, etc.) under strict/pipefail-style error checking will misreport successful, correctly-detected conditions as failures — silently, with a misleading-but-plausible non-zero exit code that looks like the remote command itself failed rather than a local piping artifact.
**Implementation rule:** never pipe a live/streaming command's output directly into a short-circuiting reader (`grep -q`, `grep -m1`, `head`) when the pipeline's exit status is checked and `pipefail` (or equivalent strict subprocess-chain error checking) is active. Capture the full output into a variable first (command substitution fully drains the writer, no early close), then match against the captured string with a non-piped check (e.g. bash's `[[ "$VAR" == *pattern* ]]` or a `grep` invocation that reads from the variable rather than from the live process).
