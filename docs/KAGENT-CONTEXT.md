# Kagent — Session Handoff Context

**Purpose of this file:** a self-contained briefing for a fresh Claude Code session picking up this project with zero prior context. Read this file top to bottom before doing anything else — it links out to the deeper reference docs (RUNBOOK.md, COMMANDS.md, VERSION-MATRIX.md, DEPENDENCY-MATRIX.md) but should be enough on its own to understand what exists, why, and what's next.

Generated: 2026-08-25.

---

## 1. Project overview: what Kagent is and why

**Frappe Cloud's real "Agent"** is a Python service that lives on every bench server and manages the Frappe bench lifecycle (site creation, backups, migrations, app installs, etc.) by shelling out to `docker exec` against Docker containers — Frappe Cloud's whole hosting fleet today is Docker-based.

**This project's goal** is to prove out, command-by-command and manifest-by-manifest, what it would take to replace that Docker layer with **Kubernetes (k3s)** — i.e. design the real dependency/behavior spec for a hypothetical **"Kagent"**: a Kubernetes-native rewrite of Frappe Cloud's Agent that manages benches as K8s Deployments/PVCs/Services instead of Docker containers.

The working method has been: stand up a real k3s cluster, run every command the real Agent would need (`bench new-site`, `migrate`, `backup`, `restore`, `install-app`, resource scaling, ingress routing, image builds, S3 backup upload, etc.) against **real Frappe benches on real infrastructure**, across **all 4 major Frappe versions (v13/v14/v15/v16)**, and document every difference from the Docker-based original — both version-to-version differences and Docker-to-K8s translation differences. Every non-obvious finding is written up as a numbered **Decision Log** entry (D1–D38 so far) in a strict format designed to become direct implementation rules for Kagent's real code.

**Two prior turns of work exist that are NOT yet reflected below and are the natural next step:**
- A task was started to clone the real `https://github.com/frappe/agent` repo to `/home/ubuntu/kagent`, read `agent/bench.py` in full, and catalog every `docker_execute()`/`docker()` call plus every YAML file (Ansible playbooks, compose files) to map out exactly what needs a K8s equivalent. **This was interrupted before any real analysis happened** — only a GitHub-auth-method check was done (no `gh` CLI installed, no global git config on `ubuntu@92.5.91.195`, only a repo-scoped SSH deploy key exists — see §3). The clone, the `bench.py` read, the `docker_execute()` inventory, the YAML inventory, and the new `kagent` GitHub repo **do not exist yet**.
- This context-handoff document was requested instead, to consolidate everything learned so far before that analysis resumes.

---

## 2. Server access details

| Field | Value |
|---|---|
| Server IP | `92.5.91.195` |
| Provider | Oracle Cloud, ARM64 (aarch64), Ubuntu 22.04.5 LTS |
| SSH key (local machine) | `/home/ahmed/Projects/Big/ssh-key-2026-08-22.key` (private, mode 400) + matching `.pub` |
| Primary SSH user | `ubuntu` — owns `/home/ubuntu/frappe-k3s-agent` (the git repo), has passwordless `sudo` |
| K8s-native SSH user | `frappe` — has `KUBECONFIG=/home/frappe/.kube/config` pre-set for direct (non-sudo) `kubectl` access |
| Repo root (on server) | `/home/ubuntu/frappe-k3s-agent` |
| K3s version | `v1.36.3+k3s1` (containerd 2.3.2-k3s2) |
| Node | single node, name `test`, control-plane, internal IP `10.0.0.37` |
| Resources | 4 vCPU, 23Gi RAM, ~146G disk |

**Standard connection pattern used throughout this project:**
```bash
# For git/repo work (as ubuntu, with sudo for kubectl when needed):
ssh -i /home/ahmed/Projects/Big/ssh-key-2026-08-22.key ubuntu@92.5.91.195 '<command>'
ssh -i /home/ahmed/Projects/Big/ssh-key-2026-08-22.key ubuntu@92.5.91.195 'sudo kubectl ...'

# For k8s-native work (as frappe, KUBECONFIG already set, no sudo needed):
ssh -i /home/ahmed/Projects/Big/ssh-key-2026-08-22.key frappe@92.5.91.195 \
  'KUBECONFIG=/home/frappe/.kube/config kubectl ...'
```
Both users reach the same cluster; `ubuntu` needs `sudo kubectl` (default kubeconfig at `/etc/rancher/k3s/k3s.yaml`, root-owned), `frappe` has its own pre-authorized kubeconfig.

---

## 3. GitHub access details

| Field | Value |
|---|---|
| GitHub account | `ahmed3majeed` |
| Existing repo | `ahmed3majeed/frappe-k3s-agent` (public), default branch `main` |
| Repo creation method | GitHub REST API `POST /user/repos`, authenticated with a **short-lived PAT used once from the local operator machine only** — the PAT was never copied to or stored on the server |
| Push/pull auth (on server) | SSH deploy key `/home/ubuntu/.ssh/github_frappe_agent` (ed25519, no passphrase), scoped to this one repo |
| SSH config (on server) | `/home/ubuntu/.ssh/config`:
  ```
  Host github.com
    HostName github.com
    User git
    IdentityFile /home/ubuntu/.ssh/github_frappe_agent
  ```
| Git identity (on server) | **Not set globally** — `git config --global` is empty (`~/.gitconfig` doesn't exist). Set locally per-repo when needed: `git config user.email "ahmed3mageed@gmail.com"` / `git config user.name "frappe-k3s-agent"` (this is what every commit in the repo uses). |

**Important gap for the `kagent` repo task:** the `github_frappe_agent` deploy key is scoped to the single `frappe-k3s-agent` repo (GitHub deploy keys are per-repo by design) — it **cannot** push to a new `kagent` repo. Creating `kagent` and pushing to it needs either (a) a new deploy key added to that specific new repo, or (b) a PAT with `repo` scope used the same one-time, not-stored-on-server way the original repo was created, or (c) the `gh` CLI authenticated (not currently installed on the server — checked and confirmed absent). Resolve this before attempting repo creation/push.

---

## 4. Full cluster state (as of 2026-08-25)

### Namespaces
```
default           kube-node-lease   kube-public   kube-system
frappe-system      (shared infra: MariaDB, Redis)
frappe-v13         (incompatible — see D36; pod exists but bench init never succeeded)
frappe-v14
frappe-v15
frappe-v16
```

### Pods (all namespaces)
```
NAMESPACE       NAME                          READY   STATUS      AGE
frappe-system   mariadb-0                     1/1     Running     2d18h   (StatefulSet — see D1)
frappe-system   mariadb-test4b                0/1     Completed   2d14h   (leftover test job pod)
frappe-system   redis-cache-master-0          1/1     Running     2d14h   (Bitnami chart StatefulSet)
frappe-system   redis-queue-master-0          1/1     Running     2d18h
frappe-system   redis-socketio-master-0       1/1     Running     2d18h
frappe-v13      bench-v13-...                 1/1     Running     2d1h    (pod alive, bench init FAILED — D36)
frappe-v13      redis-v13-...                 3/3     Running     2d1h
frappe-v14      bench-v14-...                 1/1     Running     45h     (Deployment)
frappe-v14      redis-v14-...                 3/3     Running     2d1h
frappe-v15      bench-v15                     1/1     Running     2d17h   (bare Pod, NOT a Deployment — D16)
frappe-v16      bench-v16-...                 1/1     Running     45h     (Deployment)
frappe-v16      redis-v16-...                 3/3     Running     2d5h
kube-system     coredns, traefik, metrics-server, local-path-provisioner  (all standard k3s add-ons, Running)
```
Pod suffixes (ReplicaSet hashes) change on every rollout/restart — always re-query rather than hardcoding a full pod name; the deployment-name-based selectors below are stable.

### Services (all namespaces)
```
default         kubernetes                ClusterIP      443/TCP
frappe-system   mariadb                    ClusterIP None 3306/TCP    (headless, for the StatefulSet)
frappe-system   redis-cache-headless/master/replicas       6379/TCP
frappe-system   redis-queue-headless/master/replicas       6380/TCP
frappe-system   redis-socketio-headless/master/replicas    6381/TCP
frappe-v13      redis-v13                 ClusterIP      6379,6380,6381/TCP
frappe-v14      redis-v14                 ClusterIP      6379,6380,6381/TCP
frappe-v16      redis-v16                 ClusterIP      6379,6380,6381/TCP
kube-system     kube-dns, metrics-server
kube-system     traefik                   LoadBalancer   80:32042/TCP, 443:31789/TCP, external IP 10.0.0.37
```
**Note:** there is currently **no Service in front of any `bench-vNN` pod in any namespace** — none was ever created as a permanent fixture (D11's finding — an Ingress without one silently doesn't route). The automated test suite (`tests/run-all-tests.sh`) creates one temporarily per test run and deletes it afterward; a real Kagent must create a permanent one per bench.

### PVCs (all namespaces)
```
frappe-system   data-mariadb-0    10Gi   Bound
frappe-v13      bench-v13-data    10Gi   Bound
frappe-v14      bench-v14-data    10Gi   Bound
frappe-v15      bench-v15-data    10Gi   Bound
frappe-v16      bench-v16-data    10Gi   Bound
```
All `local-path` storage class (k3s's default, single-node hostPath-backed provisioner — fine for this single-node test cluster, would need a real distributed storage class like Longhorn/EBS/etc. for a production multi-node Kagent).

### Key shared credentials in use on the cluster
- MariaDB root password: `frappe_root_2024` (used directly in many `kubectl exec ... mysql -u root -p...` commands throughout RUNBOOK.md and the test suite — this is a **test-only** password, not from any credentials file, and should not be treated as a real secret pattern to replicate).
- Docker Hub: pushed one test image during Phase 3 (`ahmed3majeed/frappe-k3s-agent-test:latest`, still present on Docker Hub — cleanup only removed the in-cluster Kaniko Job, not the registry artifact).
- IDrive e2 (S3-compatible): a test bucket `frappe-k3s-test-backups` was created and emptied again (Phase 3 Group Q) — bucket itself still exists, empty.

---

## 5. Credentials file locations (local machine)

All on the **local operator machine** at `/home/ahmed/Projects/Big/`:

| File | Purpose |
|---|---|
| `ssh-key-2026-08-22.key` (+ `.pub`) | SSH private key for server access (400 permissions) |
| `Docker Token and user name and password .txt` | Docker Hub credentials — the **PAT** from this file (not the plaintext password also present) was used for the Kaniko push secret |
| `e2-s3.eu-central-2.idrivee2.com-Access-Keys.txt` | IDrive e2 (S3-compatible) access/secret keys, used for the S3 backup test |
| `commands-master-list.md` | The original task's master command list (Docker Agent commands to verify against K8s) |
| `part1_site.md` | Original task specification document |
| `files.zip` | (bundled reference material, not individually inventoried here) |

**Handling discipline established and followed throughout this project** (see Decision Log Group P/Q credential-handling notes): credentials are read once from these local files, transferred to the server via `scp` into a private non-repo directory (or loaded directly into a K8s Secret via `--from-file`/`--from-env-file`, never `--from-literal=<value>` or any form that would expose the raw value in a process list or shell history), then shredded on both ends immediately. **No raw credential value is ever committed to the git repo.**

---

## 6. The 10 most critical Decision Log entries for building Kagent

Full RUNBOOK.md Decision Log currently runs D1–D38. These 10 are the ones most load-bearing for Kagent's core design — infrastructure topology, version branching, and secret/registry handling. Quoted verbatim from RUNBOOK.md.

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

### D6: `bench init` target directory must not pre-exist (PVC mount placement)
**Discovered in:** Phase 1, bench-v15 PVC/pod setup (before D4 was found)
**Finding:** Mounting the bench PVC directly at `.../frappe-bench` fails: `bench init` refuses with `ERROR: Bench instance already exists at frappe-bench`, because it needs to create that directory itself and rejects a pre-existing (even if empty) target path. Mounting the PVC one level up (e.g. at `/home/frappe/bench-data`) leaves the `frappe-bench` subdirectory path free for `bench init` to create, while everything it creates still persists on the PVC.
**Impact on Custom Agent:** any manifest that mounts a bench's PVC directly at the bench directory path will make `bench init` fail immediately — this is the direct cause of D15's PVC path offset (`{mount}/frappe-bench/sites/...`, not `{mount}/sites/...`) and must be understood together with it.
**Implementation rule:** always mount a new bench's PVC at the *parent* of where `bench init` will create the bench (e.g. PVC at `/home/frappe/bench-data`, bench created at `/home/frappe/bench-data/frappe-bench`), never directly at the bench directory path itself.

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

### D13: Docker Hub anonymous pull rate limiting
**Discovered in:** Group P (P7 — verifying the Kaniko-pushed image was pullable)
**Finding:** A verification pod hung in `ContainerCreating` for 8+ minutes with zero error events (just a persistent `Pulling image` kubelet event) — not a disk space issue (132G free), not a registry connectivity issue (fast response from `registry-1.docker.io`), not a bad push (a direct `crictl pull` on the node eventually succeeded with no error). Root cause: this node has made a very large number of unauthenticated/anonymous image pulls from Docker Hub across this entire multi-session engagement, all from a single IP. Docker Hub throttles anonymous pulls per-IP; a throttled pull doesn't always surface as a hard kubelet error, it can just silently crawl. Once cached, a fresh verification pod completed in 6 seconds.
**Impact on Custom Agent:** any image pull the Agent triggers — including pulling its own just-built/pushed images — can silently stall for many minutes if done anonymously, with no error to catch or alert on. A naive timeout-based retry won't help if the underlying cause is throttling, not a transient failure.
**Implementation rule:** always attach `imagePullSecrets` (referencing the same registry Secret used for pushing) to every Pod/Deployment/Job spec that pulls an image from Docker Hub — including the Agent's own images, not just customer bench images. Authenticated pulls get a materially higher Docker Hub rate limit than anonymous ones.

### D14: K8s Secrets are namespace-scoped
**Discovered in:** Group Q (Q4 — first S3 upload Job attempt)
**Finding:** The IDrive e2 Secret (`idrive-e2-secret`) was created in the `frappe-system` namespace, but the S3 upload Job was specified to run in `frappe-v15`. The Job failed immediately with `CreateContainerConfigError` / `Error: secret "idrive-e2-secret" not found` — Kubernetes Secrets are strictly namespace-scoped; a Pod/Job can only reference a Secret that lives in its own namespace, full stop. There is no cross-namespace Secret reference mechanism in core Kubernetes.
**Impact on Custom Agent:** any manifest template (backup upload, image push, restore, or any other Job the Agent generates) that references a Secret by name must be generated with that Secret provisioned in the *same* namespace as the Job — a shared "central" Secret in one namespace is invisible everywhere else, and this fails silently at the manifest-authoring stage (no error until the Job actually tries to start).
**Implementation rule:** the Custom Agent must create (or copy) every required Secret into each bench namespace that needs it, at the time that namespace/bench is provisioned — never assume a Secret created once in an infra namespace (like `frappe-system`) is reachable from a per-bench namespace (like `frappe-v15`). When a Secret's contents are shared across namespaces (e.g. one S3 backup destination for all benches), copy the Secret's already-encoded data via the API (`kubectl get secret ... -o json` → strip metadata → `kubectl apply -n {target-ns} -f -`) rather than re-entering raw credentials per namespace.

### D16: bare Pod vs. Deployment — restart/recreate semantics
**Discovered in:** Group R (pre-flight check before R6)
**Finding:** `bench-v15` (the original Phase 1 test bench) was created as a bare `kind: Pod` with no owning controller — `kubectl get pod bench-v15 -o jsonpath="{.metadata.ownerReferences}"` returns empty, and no Deployment/ReplicaSet/StatefulSet exists in `frappe-v15`. The Group R task instructions assumed that deleting this pod would trigger automatic recreation ("K8s will recreate it automatically") — **this is false for an unmanaged Pod.** Only pods owned by a controller get recreated on deletion; a bare Pod that's deleted is simply gone until something re-applies its manifest.
**Impact on Custom Agent:** any restart/update logic the Agent runs (`kubectl rollout restart deployment/...` or a delete-and-recreate fallback) must know in advance whether the target is actually a controller-managed resource. Applying Deployment-style restart logic to a bare-Pod bench (as `bench-v15` still is, a holdover from before Group K's proper Deployment-based bench pattern existed) would either fail cleanly (`rollout restart` on a nonexistent Deployment) or, worse, silently destroy the pod if the delete-fallback were used without a saved manifest to reapply.
**Implementation rule:** every bench the Agent manages must be a Deployment (as established in Phase 2 Group K's `k3s/bench-deployment.yaml` pattern) — never a bare Pod — specifically so that restart/update operations can rely on controller-managed recreation semantics. Before running any delete-based fallback on any resource, the Agent must first confirm the resource has an owning controller (non-empty `ownerReferences`); if not, either refuse the operation or ensure a manifest is available to reapply immediately after deletion.

### D30: `bench run-patch` is silent on success in v16, verbose in v15
**Discovered in:** Frappe v16 Tier B testing, B22 (run-patch)
**Finding:** On v15, `bench --site {s} run-patch {patch}` printed an explicit `Executing {patch} in {site} ({db_name})` line followed by `Success: Done in {N}s` on completion. On v16, the identical command structure produces **zero output** on success (confirmed with two different real v16-specific patches, and re-verified with explicit `2>&1` capture to rule out a stream-redirection artifact) — only the exit code (0) indicates success.
**Impact on Custom Agent:** if the Agent parses `run-patch` stdout to confirm a patch actually executed (e.g. looking for "Success: Done" text, as would be a reasonable approach based on v15's behavior), that check will incorrectly report failure on every v16 patch run, even though the patch succeeded (exit 0).
**Implementation rule:** verify `run-patch` success by exit code only, never by matching specific output text — this generalizes: the Agent should treat exit-code checking as the default for every bench command, and only additionally parse output when a command's own documented contract requires it. If confirmation beyond exit code is needed, check the patch's actual effect directly (e.g. query the `Patch Log` doctype) rather than parsing CLI text.

### D33: `--mariadb-user-host-login-scope` doesn't exist in v14 — must use `--no-mariadb-socket`
**Discovered in:** Frappe v14 environment setup, S9 (bench new-site)
**Finding:** `bench new-site --mariadb-user-host-login-scope='%' ...` fails on v14 with `Error: No such option: --mariadb-user-host-login-scope` — this flag doesn't exist at all in v14's bench CLI (confirmed via `--help`). It's a v15+ addition; D5 documented it as the *replacement* for the now-deprecated `--no-mariadb-socket` on v15, but v14 predates that replacement entirely and only supports the older flag.
**Impact on Custom Agent:** any Agent logic that always uses the "modern" `--mariadb-user-host-login-scope` flag (correct guidance for v15+, per D5) will fail outright on v14 and likely v13 too — this is a hard version boundary, not a deprecation-warning situation.
**Implementation rule:** the Agent must select the correct `new-site`/socket flag based on the target Frappe major version: `--no-mariadb-socket` for v14 and earlier, `--mariadb-user-host-login-scope='%'` for v15 and later. Never hardcode one flag across all supported versions.

*(D3–D9, D12, D15, D17–D29, D31–D38 are all also real and useful — see RUNBOOK.md's full Decision Log for the complete set. The above 10 are the ones a from-scratch Kagent design most needs on day one: cluster topology (D1/D2/D6/D10/D11/D16), version branching (D30/D33), and secret/registry handling (D13/D14).)*

---

## 7. Supported versions table with exact commands

Full detail in `docs/DEPENDENCY-MATRIX.md`; summary below.

| Version | Status | Notes |
|---|---|---|
| v13 | ❌ Not supported | `node-sass` native compile fails against Node 24+ (V8 ABI break, D36). No workaround within a reasonable effort — would need a dedicated old-Node base image. |
| v14 | ✅ Supported | Needs Python 3.11 explicitly (image defaults to 3.14 — D32) + `python3.11-dev`. Uses the older MariaDB flag (D33). |
| v15 | ✅ Supported | Baseline/reference version. |
| v16 | ✅ Supported | Latest. `run-patch` silent on success (D30); `backup` prints absolute paths (D28); `migrate` has extra cleanup steps (D27); `drop-site` archives to a different path (D29); `new-site` has 2 extra output steps (D26). |

**`bench init` (version-specific):**
```bash
# v14
apt-get install -y python3.11-dev   # once, before bench init
bench init frappe-bench --frappe-branch version-14 \
  --python /usr/bin/python3.11 --skip-redis-config-generation

# v15 / v16
bench init frappe-bench --frappe-branch version-{15,16} \
  --skip-redis-config-generation
```
`--skip-redis-config-generation` is required on **every** version (D4) — the image has no local `redis-server` binary.

**`bench new-site` (version-specific):**
```bash
# v14
bench new-site <site> --no-mariadb-socket \
  --db-host <mariadb-host> --mariadb-root-username root \
  --mariadb-root-password <pass> --admin-password <pass>

# v15 / v16
bench new-site <site> --mariadb-user-host-login-scope='%' \
  --db-host <mariadb-host> --mariadb-root-username root \
  --mariadb-root-password <pass> --admin-password <pass>
```
Redis host values passed via `bench set-redis-*-host` (if ever done manually, outside `new-site`) must use the `redis://host:port` form, never bare `host:port` (D3).

**Verified actual installed versions** (read directly from the live pods — see DEPENDENCY-MATRIX.md for full detail):
| | v14 | v15 | v16 |
|---|---|---|---|
| Frappe | 14.101.1 | 15.118.0 | 16.31.0 |
| Python | 3.11.2 | 3.14.2 | 3.14.2 |
| Node.js | v24.13.0 (all three — shared image) | | |
| bench CLI | 5.31.0 (all three — shared image) | | |
| MariaDB | 10.11.18-MariaDB (shared instance, all versions) | | |
| Redis | 8.10.1 (all versions, different instances) | | |
| OS (container) | **Debian 12 (bookworm)** — not Ubuntu, verified via `/etc/os-release`, corrects a common assumption | | |

---

## 8. What needs to be built (Kagent scope)

**Confirmed-working K8s-native replacements for Docker-Agent operations** (all tested end-to-end on the live cluster):
- **Bench lifecycle**: `bench init`/`new-site`/`migrate`/`backup`/`restore`/`drop-site`/`install-app`/`uninstall-app`/`reinstall` — all via `kubectl exec` into a Deployment-managed bench pod, version-branched per §7.
- **Image builds**: Kaniko Job (daemonless, in-cluster) replaces `docker buildx build` + `docker push` — proven in Phase 3 Group P. Needs `imagePullSecrets` wired everywhere per D13.
- **S3 backup**: a Job pattern (`bench backup` writes to PVC → a separate Job uploads to S3-compatible storage via the `aws` CLI) replaces the original Agent's `mkfifo` + `rclone rcat` streaming design — proven in Phase 3 Group Q, full backup→upload→download→restore cycle verified.
- **Routing**: Traefik IngressRoute + a real backend Service (D11) replaces whatever Docker networking/reverse-proxy config the original Agent manages.
- **Scaling/restart**: `kubectl rollout restart` / `scale` / resource `patch` on a Deployment (never a bare Pod — D16) replaces `docker restart`/container resource flags.
- **Health checks**: `tests/run-all-tests.sh` in this repo is a working reference implementation of infra + bench-command + K8s-op + SQL health checks across all 3 supported versions — a real Kagent's health-check subsystem should follow the same version-branching pattern it uses.

**Confirmed NOT yet done — the actual next step for this project:**
- **No analysis of the real `frappe/agent` source has happened yet.** The plan (started, then superseded by this handoff doc) was: clone `https://github.com/frappe/agent` to `/home/ubuntu/kagent`, read `agent/bench.py` in full, enumerate every `docker_execute()` call and every other `docker()`/subprocess-docker call with line numbers, inventory every YAML file (Ansible playbooks and what server setup each handles; Docker Compose files and what services each defines; any config YAML) and determine what K8s manifest/Helm chart replaces each, and identify which `bench.py` methods don't touch Docker at all (and so stay unchanged in Kagent). **None of this exists yet.** This is pure analysis — no code changes — and is the natural continuation of this project once server-side git auth for a new `kagent` repo is sorted out (see §3's gap).
- No actual "Kagent" code exists anywhere — everything so far is cluster experimentation + documentation (RUNBOOK.md, COMMANDS.md, VERSION-MATRIX.md, DEPENDENCY-MATRIX.md) plus one test-automation script. Writing real Kagent source is future work, contingent on the `bench.py` analysis above.

---

## 9. What files exist and where

**On the server, repo root `/home/ubuntu/frappe-k3s-agent`** (git remote: `git@github.com:ahmed3majeed/frappe-k3s-agent.git`, branch `main`):
```
RUNBOOK.md                  — chronological, append-only log of every command run + Decision Log (D1–D38)
docs/COMMANDS.md            — condensed Docker-Agent-command → K8s-equivalent reference table
docs/VERSION-MATRIX.md      — v15 vs v16 environment/behavior comparison (pre-dates v14 testing)
docs/DEPENDENCY-MATRIX.md   — authoritative per-version (v13–v16) dependency table + bench init/new-site commands
docs/KAGENT-CONTEXT.md      — THIS FILE
tests/run-all-tests.sh      — automated test suite: infra health + all bench commands + K8s ops + SQL, across v14/v15/v16
k3s/                         — every K8s manifest produced during testing:
  bench-deployment.yaml, bench-v16-deployment.yaml   — bench Deployment patterns
  bench-pvc.yaml, bench-v16-pvc.yaml                  — PVC patterns (mounted one level above bench dir — D6)
  bench-service.yaml                                  — Service pattern (web:8000, socketio:9000)
  bench-ingressroute.yaml, ingressroute-custom-domain.yaml  — Traefik IngressRoute patterns
  middleware-maintenance.yaml                         — Traefik Middleware (redirectRegex) pattern
  redis-v16.yaml                                       — 3-sidecar-container Redis pattern (one process per port — see RUNBOOK's Redis setup correction)
  kaniko-test-job.yaml                                 — Kaniko in-cluster image build Job
  s3-upload-job.yaml, s3-download-pod.yaml, s3-setup-pod.yaml, s3-verify-pod.yaml, s3-cleanup-pod.yaml — S3 backup cycle manifests
```

**Not yet existing** (planned, per §8): `/home/ubuntu/kagent` (clone of `frappe/agent` + eventual real Kagent source), a `kagent` GitHub repo under `ahmed3majeed`, `/home/ubuntu/kagent/docs/ANALYSIS.md`.

**On the local operator machine** (`/home/ahmed/Projects/Big/`): see §5.

---

## 10. Documentation rules

These conventions have been followed consistently across the whole engagement and should continue:

1. **RUNBOOK.md is append-only and chronological.** Every command run against the server gets logged there under a dated `## ` heading, in the order it actually happened — it is the raw historical record, never edited to rewrite history (only corrected in-place when a specific entry is later found to be factually wrong, and even then the correction is usually written as a visible "corrected after further testing" addendum rather than a silent edit).
2. **Decision Log entries use a strict, non-negotiable 5-field format** — this has been enforced and audited multiple times (most recently: all D1–D38 verified complete):
   ```
   ### D[N]: [Title]
   **Discovered in:** [Group/Phase]
   **Finding:** [exact description]
   **Impact on Custom Agent:** [what breaks if ignored]
   **Implementation rule:** [exact rule to follow]
   ```
   Every field label must appear exactly as `**Field:**` (bold, with the trailing colon inside the bold) for it to pass the programmatic audit script pattern used to verify completeness. A prior entry (D34) briefly broke this convention by using non-standard labels (`**Finding (original, incomplete):**` / `**Correction:**`) during a correction — this was itself flagged and fixed; don't repeat that mistake even when documenting a correction to an earlier entry.
3. **docs/COMMANDS.md is a curated, condensed reference** derived from RUNBOOK.md's raw logs — one block per distinct command, cross-referencing back to RUNBOOK.md's dated sections rather than duplicating full output.
4. **docs/VERSION-MATRIX.md and docs/DEPENDENCY-MATRIX.md are structured comparison tables**, not logs — updated/rewritten in place as understanding improves (unlike RUNBOOK.md), always sourced from values actually read off the live pods, never assumed from external docs without a Notes/caveat callout when the two disagree (e.g. DEPENDENCY-MATRIX.md's note that the cluster's MariaDB 10.11.18 is below v16's official-docs-recommended 11.8, yet works fine).
5. **"Verify, don't assume" is the governing principle throughout** — repeatedly, values assumed from a task's own instructions turned out to be wrong when checked directly (Redis version claims, the container OS being Debian not Ubuntu, deployment container names, label selectors, official version minimums). Any new documentation should follow the same discipline: state what was actually observed on the live cluster, and flag explicitly wherever an assumption from a task brief or external doc doesn't match reality.
6. **Credentials are never committed** — read once from a local file, transferred via `scp`/K8s Secret mechanisms that don't expose them in shell history or process lists, shredded after use (see §5).
7. **After any documentation change, the standard close-out is**: `git add -A && git commit -m "<message>" && git push origin main` — always from the `ubuntu` user on the server, using the local `git config user.email/user.name` set in that repo (see §3).
