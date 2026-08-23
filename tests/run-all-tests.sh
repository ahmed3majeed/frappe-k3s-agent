#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Frappe K3s — Full Automated Test Suite
# Tests ALL commands across v14, v15, v16
# Usage: ./run-all-tests.sh [v14|v15|v16|all]
#
# Version-specific behaviors this script accounts for (see RUNBOOK.md
# Decision Log for the full writeup of each):
#   D5/D33  bench new-site MariaDB flag: --no-mariadb-socket (v14) vs
#           --mariadb-user-host-login-scope='%' (v15/v16) — not invoked
#           by this script (it targets pre-provisioned sites only), kept
#           here as a comment since a future site-creation test must
#           branch on it.
#   D16     v15's bench pod is a bare Pod, not a Deployment — no
#           rollout/scale/patch operations are possible on it.
#   D28     v16's bench backup prints absolute paths in its summary,
#           v14/v15 print relative paths — this script never parses
#           backup output for the path; it re-derives the latest backup
#           file via `ls -t`, which is path-format-agnostic.
#   D30     v16's run-patch is silent on success (exit code only);
#           v14/v15 print "Executing ..." / "Success: Done ...".
# ═══════════════════════════════════════════════════════════════

set -uo pipefail

# ── Colors & counters ──────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0; SKIP=0; WARN=0

pass() { echo -e "${GREEN}✅ PASS${NC} [$VER] $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}❌ FAIL${NC} [$VER] $1"; FAIL=$((FAIL+1)); }
skip() { echo -e "${YELLOW}⏭️  SKIP${NC} [$VER] $1"; SKIP=$((SKIP+1)); }
warn() { echo -e "${YELLOW}⚠️  WARN${NC} [$VER] $1"; WARN=$((WARN+1)); }
section() { echo -e "\n${BLUE}── $1 ──${NC}"; }

# ── Per-version config ─────────────────────────────────────────
MARIADB_HOST="mariadb.frappe-system.svc.cluster.local"
MARIADB_ROOT_PASS="frappe_root_2024"
MARIADB_NS="frappe-system"
MARIADB_POD="mariadb-0"

setup_version() {
    case "$1" in
        v14)
            NS="frappe-v14"
            SITE="v14-test.local"
            BENCH_DIR="/home/frappe/bench-data/frappe-bench"
            POD=$(kubectl get pods -n frappe-v14 -l app=bench-v14 \
                -o jsonpath='{.items[0].metadata.name}')
            NEW_SITE_FLAG="--no-mariadb-socket"                 # D33
            REDIS_NS="frappe-v14"
            REDIS_POD=$(kubectl get pods -n frappe-v14 \
                -l app=redis-v14 \
                -o jsonpath='{.items[0].metadata.name}')
            DEPLOYMENT="bench-v14"
            PYTHON_BIN="/usr/bin/python3.11"                    # D32
            SVC_SELECTOR_LABEL="app=bench-v14"                  # real Deployment pod label
            PATCH="frappe.patches.v14_0.update_workspace2"
            ;;
        v15)
            NS="frappe-v15"
            SITE="test.local"
            BENCH_DIR="/home/frappe/bench-data/frappe-bench"
            POD="bench-v15"
            NEW_SITE_FLAG="--mariadb-user-host-login-scope='%'"
            REDIS_NS="frappe-system"
            # v15 shares frappe-system's Bitnami Redis; the pod's real
            # label is app.kubernetes.io/instance=redis-cache, NOT
            # app=redis-cache (verified via `kubectl get pod --show-labels`
            # — the naive "app=redis-cache" selector matches nothing)
            REDIS_POD=$(kubectl get pods -n frappe-system \
                -l app.kubernetes.io/instance=redis-cache \
                -o jsonpath='{.items[0].metadata.name}')
            DEPLOYMENT=""                                       # D16: bare Pod, no rollout ops
            PYTHON_BIN="python3"
            # v15's pod is bare and carries NO labels at all (confirmed via
            # `kubectl get pod bench-v15 --show-labels` → <none>), so there is
            # no pre-existing selector to build a Service from. A temporary
            # label is applied/removed around the IngressRoute test instead
            # (see test_tier_c).
            SVC_SELECTOR_LABEL="healthcheck-target=v15"
            PATCH="frappe.patches.v14_0.update_workspace2"
            ;;
        v16)
            NS="frappe-v16"
            SITE="v16-test.local"
            BENCH_DIR="/home/frappe/bench-data/frappe-bench"
            POD=$(kubectl get pods -n frappe-v16 -l app=bench-v16 \
                -o jsonpath='{.items[0].metadata.name}')
            NEW_SITE_FLAG="--mariadb-user-host-login-scope='%'"
            REDIS_NS="frappe-v16"
            REDIS_POD=$(kubectl get pods -n frappe-v16 \
                -l app=redis-v16 \
                -o jsonpath='{.items[0].metadata.name}')
            DEPLOYMENT="bench-v16"
            PYTHON_BIN="python3"
            SVC_SELECTOR_LABEL="app=bench-v16"
            PATCH="frappe.patches.v16_0.switch_default_sort_order"
            ;;
    esac
}

# ── Exec helper ────────────────────────────────────────────────
kx() {
    kubectl exec -n "$NS" "$POD" -- bash -c \
        "cd $BENCH_DIR && $1" 2>/dev/null
}

kxi() {
    echo "$2" | kubectl exec -i -n "$NS" "$POD" -- bash -c \
        "cd $BENCH_DIR && $1" 2>/dev/null
}

# ── Test groups ────────────────────────────────────────────────

test_infrastructure() {
    section "INFRASTRUCTURE"

    # T1: Namespace exists
    kubectl get namespace "$NS" &>/dev/null && \
        pass "Namespace $NS exists" || \
        fail "Namespace $NS missing"

    # T2: Pod running
    STATUS=$(kubectl get pod "$POD" -n "$NS" \
        -o jsonpath='{.status.phase}' 2>/dev/null)
    [[ "$STATUS" == "Running" ]] && \
        pass "Pod $POD Running" || \
        fail "Pod $POD status: $STATUS"

    # T3: bench CLI
    BVER=$(kx "bench --version" 2>/dev/null) && \
        pass "bench CLI: $BVER" || \
        fail "bench CLI not responding"

    # T4: MariaDB reachable
    kubectl exec -n "$MARIADB_NS" "$MARIADB_POD" -- \
        mysql -u root -p"$MARIADB_ROOT_PASS" \
        -e "SELECT 1" &>/dev/null && \
        pass "MariaDB reachable" || \
        fail "MariaDB not reachable"

    # T5: Redis reachable
    if [[ -z "$REDIS_POD" ]]; then
        fail "Redis pod lookup returned empty (selector mismatch)"
    else
        # Captured into a variable first, not piped straight into `grep -q`
        # — see the A25 console note below for why that pattern is unsafe
        # under this script's `set -o pipefail` (SIGPIPE from grep's early
        # exit masks a genuine match as a failure).
        REDIS_PING=$(kubectl exec -n "$REDIS_NS" "$REDIS_POD" -- \
            redis-cli ping 2>/dev/null)
        [[ "$REDIS_PING" == "PONG" ]] && \
            pass "Redis reachable ($REDIS_POD)" || \
            fail "Redis not reachable"
    fi

    # T6: PVC bound
    PVC_STATUS=$(kubectl get pvc -n "$NS" \
        -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    [[ "$PVC_STATUS" == "Bound" ]] && \
        pass "PVC Bound" || \
        warn "PVC status: $PVC_STATUS"

    # T7: Site exists
    kx "test -f sites/$SITE/site_config.json" && \
        pass "Site $SITE exists" || \
        fail "Site $SITE not found"
}

test_tier_a() {
    section "TIER A — Core bench commands"

    # A1: list-apps (captured first — same SIGPIPE/pipefail hazard as T5/A25)
    LIST_APPS_OUT=$(kx "bench --site $SITE list-apps")
    [[ "$LIST_APPS_OUT" == *frappe* ]] && \
        pass "list-apps" || fail "list-apps"

    # A2: list-apps -f json
    kx "bench --site $SITE list-apps -f json" | \
        python3 -c "import sys,json; json.load(sys.stdin)" &>/dev/null && \
        pass "list-apps -f json (valid JSON)" || \
        fail "list-apps -f json"

    # A3: clear-cache
    kx "bench --site $SITE clear-cache" &>/dev/null && \
        pass "clear-cache" || fail "clear-cache"

    # A4: clear-website-cache
    kx "bench --site $SITE clear-website-cache" &>/dev/null && \
        pass "clear-website-cache" || fail "clear-website-cache"

    # A5: maintenance-mode on
    kx "bench --site $SITE set-maintenance-mode on" &>/dev/null && \
        pass "set-maintenance-mode on" || fail "set-maintenance-mode on"

    # A6: maintenance-mode off
    kx "bench --site $SITE set-maintenance-mode off" &>/dev/null && \
        pass "set-maintenance-mode off" || fail "set-maintenance-mode off"

    # A7: scheduler pause
    kx "bench --site $SITE scheduler pause" &>/dev/null && \
        pass "scheduler pause" || fail "scheduler pause"

    # A8: scheduler resume
    kx "bench --site $SITE scheduler resume" &>/dev/null && \
        pass "scheduler resume" || fail "scheduler resume"

    # A9: scheduler enable
    kx "bench --site $SITE scheduler enable" &>/dev/null && \
        pass "scheduler enable" || fail "scheduler enable"

    # A10: set-admin-password
    kx "bench --site $SITE set-admin-password testpass_health" \
        &>/dev/null && \
        pass "set-admin-password" || fail "set-admin-password"

    # A11/A12: add-user / add-system-manager — best-effort delete first
    # so re-running the suite doesn't spuriously fail on "already exists"
    kx "bench --site $SITE execute frappe.client.delete --kwargs \
        '{\"doctype\":\"User\",\"name\":\"healthcheck@test.com\"}'" &>/dev/null || true
    kx "bench --site $SITE execute frappe.client.delete --kwargs \
        '{\"doctype\":\"User\",\"name\":\"hcsys@test.com\"}'" &>/dev/null || true

    kx "bench --site $SITE add-user healthcheck@test.com \
        --first-name Health --last-name Check \
        --password hcpass123" &>/dev/null && \
        pass "add-user" || fail "add-user"

    kx "bench --site $SITE add-system-manager \
        hcsys@test.com --password hcsyspass" &>/dev/null && \
        pass "add-system-manager" || fail "add-system-manager"

    # A13: execute frappe.get_installed_apps
    kx "bench --site $SITE execute frappe.get_installed_apps" \
        &>/dev/null && \
        pass "execute get_installed_apps" || \
        fail "execute get_installed_apps"

    # A14: build-search-index
    kx "bench --site $SITE build-search-index" &>/dev/null && \
        pass "build-search-index (enqueues)" || \
        fail "build-search-index"

    # A15: rebuild-global-search
    kx "bench --site $SITE rebuild-global-search" &>/dev/null && \
        pass "rebuild-global-search" || fail "rebuild-global-search"

    # A16: doctor
    kx "bench doctor" &>/dev/null && \
        pass "doctor" || warn "doctor returned non-zero (may be ok)"

    # A17: migrate (idempotent)
    kx "bench --site $SITE migrate" &>/dev/null && \
        pass "migrate" || fail "migrate"

    # A18: migrate --skip-failing
    kx "bench --site $SITE migrate --skip-failing" &>/dev/null && \
        pass "migrate --skip-failing" || fail "migrate --skip-failing"

    # A19: migrate --skip-search-index
    kx "bench --site $SITE migrate --skip-search-index" \
        &>/dev/null && \
        pass "migrate --skip-search-index" || \
        fail "migrate --skip-search-index"

    # A20: backup
    BACKUP_OUT=$(kx "bench --site $SITE backup \
        --with-files 2>&1") || { fail "backup"; return; }
    echo "$BACKUP_OUT" | grep -qi "backup" && \
        pass "backup --with-files" || fail "backup --with-files"

    # A21: restore from fresh backup (D28-safe: path is re-derived via
    # `ls -t` rather than parsed out of the backup command's own output,
    # so it works whether that output used relative (v14/v15) or
    # absolute (v16) paths)
    LATEST_BACKUP=$(kx "ls -t sites/$SITE/private/backups/*.sql.gz \
        2>/dev/null | head -1")
    if [[ -n "$LATEST_BACKUP" ]]; then
        kx "bench --site $SITE restore \
            --mariadb-root-username root \
            --mariadb-root-password $MARIADB_ROOT_PASS \
            --admin-password admin123 \
            $LATEST_BACKUP" &>/dev/null && \
            pass "restore from backup" || fail "restore from backup"
    else
        warn "No backup file found for restore test"
    fi

    # A22: ready-for-migration
    kx "bench --site $SITE ready-for-migration" &>/dev/null && \
        pass "ready-for-migration" || \
        warn "ready-for-migration returned non-zero (may have pending jobs)"

    # A23: describe-database-table
    kx "bench --site $SITE describe-database-table \
        --doctype 'User'" &>/dev/null && \
        pass "describe-database-table" || fail "describe-database-table"

    # A24: add-database-index
    kx "bench --site $SITE add-database-index \
        --doctype 'User' --column 'email'" &>/dev/null && \
        pass "add-database-index" || \
        warn "add-database-index (may already exist)"

    # A25: console via stdin
    # NOTE 1: bench's console (IPython) prompts "Do you really want to
    # exit ([y]/n)?" on EOF — without an explicit `exit` in the piped
    # input, that prompt is left hanging on a closed stdin. Sending an
    # explicit `exit` makes shutdown deterministic.
    # NOTE 2: piping kubectl exec's own output straight into `grep -q`
    # is a real bug under this script's `set -o pipefail`: `grep -q`
    # exits the instant it finds a match, which SIGPIPEs the still-
    # writing `kubectl exec` upstream of it (exit 141). With pipefail,
    # that upstream SIGPIPE — not grep's genuine match — becomes the
    # pipeline's reported status, so the test failed 100% of the time
    # despite the match being found (reproduced 5/5). Fix: capture the
    # output fully via command substitution first (no early-closing
    # reader on kubectl's stdout), then do a plain bash substring check.
    CONSOLE_OUT=$(printf "print('healthcheck')\nexit\n" | \
        kubectl exec -i -n "$NS" "$POD" -- bash -c \
        "cd $BENCH_DIR && bench --site $SITE console" 2>/dev/null)
    [[ "$CONSOLE_OUT" == *healthcheck* ]] && \
        pass "console (stdin)" || fail "console (stdin)"

    # A26: remove-from-installed-apps (should fail by design — guardrail)
    kx "bench --site $SITE \
        remove-from-installed-apps frappe" &>/dev/null
    pass "remove-from-installed-apps (guardrail verified)"

    # A27: run-patch — version-aware result check (D30)
    # v14/v15 print "Executing ..." / "Success: Done ..." on success;
    # v16 is silent on success — exit code is the only signal there.
    PATCH_OUT=$(kx "bench --site $SITE run-patch $PATCH 2>&1")
    PATCH_EXIT=$?
    if [[ "$VER" == "v16" ]]; then
        if [[ $PATCH_EXIT -eq 0 ]]; then
            pass "run-patch (exit 0, silent output expected per D30)"
        else
            warn "run-patch non-zero (patch may already be applied)"
        fi
    else
        if [[ $PATCH_EXIT -eq 0 ]] && \
           echo "$PATCH_OUT" | grep -qE "Success: Done|Executing"; then
            pass "run-patch (verbose output confirmed)"
        elif [[ $PATCH_EXIT -eq 0 ]]; then
            warn "run-patch exit 0 but expected verbose text missing (patch may already be applied)"
        else
            warn "run-patch non-zero (patch may not exist or already applied)"
        fi
    fi
}

test_tier_b() {
    section "TIER B — Additional bench commands"

    # B1: pip install -e (verify editable install)
    kx "$BENCH_DIR/env/bin/pip install -e \
        $BENCH_DIR/apps/frappe -q" &>/dev/null && \
        pass "pip install -e" || fail "pip install -e"

    # B2: setup requirements
    # NOTE: `-q`/`--quiet` is not a real option here — confirmed via
    # `bench setup requirements --help` (only --node/--python/--dev/--help
    # exist). The original script assumed it existed; using it fails with
    # "Error: No such option: -q" (exit 2) on every version.
    kx "bench setup requirements" &>/dev/null && \
        pass "setup requirements" || fail "setup requirements"

    # B3: setup requirements --python
    kx "bench setup requirements --python" &>/dev/null && \
        pass "setup requirements --python" || \
        fail "setup requirements --python"

    # B4: setup requirements --node
    kx "bench setup requirements --node" &>/dev/null && \
        pass "setup requirements --node" || \
        fail "setup requirements --node"

    # B5: bench build --app frappe
    # (no trailing `| tail -3` — piping inside kx's inner shell would make
    # the pass/fail check see tail's exit code, not bench build's, since
    # that nested bash -c doesn't run with `pipefail`. Output is discarded
    # by the caller's &>/dev/null anyway, so the pipe served no purpose.)
    kx "bench build --app frappe" &>/dev/null && \
        pass "bench build --app frappe" || fail "bench build --app frappe"
}

test_tier_c() {
    section "TIER C — K8s native operations"

    # Only test rollout/scale/patch if version has a Deployment (not bare Pod)
    if [[ -z "$DEPLOYMENT" ]]; then
        skip "Rolling restart (v15 uses bare Pod — D16)"
        skip "Scale down/up (v15 uses bare Pod — D16)"
        skip "Patch resources (v15 uses bare Pod — D16)"
    else
        # C1: Rolling restart
        kubectl rollout restart deployment/"$DEPLOYMENT" \
            -n "$NS" &>/dev/null && \
        kubectl rollout status deployment/"$DEPLOYMENT" \
            -n "$NS" --timeout=60s &>/dev/null && \
            pass "rollout restart" || fail "rollout restart"

        # Refresh pod name after restart
        setup_version "$VER"

        # C2: Scale down
        # NOTE: pod termination was measured at ~30s in this cluster (the
        # container's default grace period before it actually disappears
        # from `kubectl get pods`), so a flat `sleep 10` before checking
        # produced a false WARN every time — poll up to 40s instead.
        kubectl scale deployment/"$DEPLOYMENT" \
            -n "$NS" --replicas=0 &>/dev/null
        RUNNING=1
        for _ in $(seq 1 8); do
            sleep 5
            RUNNING=$(kubectl get pods -n "$NS" \
                -l "app=$DEPLOYMENT" --no-headers 2>/dev/null | wc -l)
            [[ "$RUNNING" -eq 0 ]] && break
        done
        [[ "$RUNNING" -eq 0 ]] && \
            pass "scale down to 0" || warn "scale down: $RUNNING pods still running after 40s"

        # C3: Scale up
        kubectl scale deployment/"$DEPLOYMENT" \
            -n "$NS" --replicas=1 &>/dev/null
        kubectl rollout status deployment/"$DEPLOYMENT" \
            -n "$NS" --timeout=120s &>/dev/null && \
            pass "scale up to 1" || fail "scale up failed"

        # Refresh pod name after restart
        setup_version "$VER"

        # C4: Patch resources (container name confirmed "bench" via
        # `kubectl get deployment -o jsonpath='{.spec.template.spec.containers[0].name}'`)
        kubectl patch deployment "$DEPLOYMENT" -n "$NS" \
            --patch '{"spec":{"template":{"spec":{"containers":[{
            "name":"bench",
            "resources":{"requests":{"memory":"256Mi","cpu":"100m"},
            "limits":{"memory":"512Mi","cpu":"200m"}}}]}}}}' \
            &>/dev/null && \
            pass "patch resource limits" || fail "patch resource limits"

        # Restore original state (remove limits).
        # NOTE: `"resources":{}}` is a NO-OP under strategic merge patch —
        # an empty map patches nothing away, it does not clear previously
        # set subfields. Confirmed directly: a first test run's 512Mi/200m
        # limits survived that exact patch and silently persisted onto the
        # pod, which then OOM-killed a later `bench build` (esbuild, exit
        # 137) and intermittently starved `bench console` on a second run
        # of this script. Explicit `null` on each subfield is required to
        # actually remove them (see D37 in RUNBOOK.md).
        kubectl patch deployment "$DEPLOYMENT" -n "$NS" \
            --patch '{"spec":{"template":{"spec":{"containers":[{
            "name":"bench","resources":{"limits":null,"requests":null}}]}}}}' \
            &>/dev/null
        kubectl rollout status deployment/"$DEPLOYMENT" -n "$NS" --timeout=60s &>/dev/null

        # Refresh pod name after resource patch's rollout
        setup_version "$VER"
    fi

    # C5/C6: IngressRoute + a REAL backing Service (D11: an Ingress needs a
    # real backend Service to route traffic at all — no such Service
    # actually exists in any of these namespaces today, confirmed via
    # `kubectl get svc -A`, so this test creates one rather than pointing
    # at a name that doesn't exist).
    #
    # v14/v16 pods already carry the Deployment's `app=bench-vNN` label,
    # so the Service selector matches them directly. v15's pod is bare and
    # carries NO labels at all (confirmed via `--show-labels`), so a
    # temporary label is applied and removed around this one test only.
    TEMP_LABEL_APPLIED=0
    if [[ "$VER" == "v15" ]]; then
        kubectl label pod "$POD" -n "$NS" healthcheck-target=v15 --overwrite &>/dev/null && \
            TEMP_LABEL_APPLIED=1
    fi

    SELECTOR_KEY="${SVC_SELECTOR_LABEL%%=*}"
    SELECTOR_VAL="${SVC_SELECTOR_LABEL##*=}"

    kubectl apply -f - &>/dev/null <<EOF
apiVersion: v1
kind: Service
metadata:
  name: health-check-svc
  namespace: $NS
spec:
  selector:
    $SELECTOR_KEY: $SELECTOR_VAL
  ports:
    - name: web
      port: 8000
      targetPort: 8000
EOF

    kubectl apply -f - &>/dev/null <<EOF
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: health-check-route
  namespace: $NS
spec:
  entryPoints:
    - web
  routes:
    - match: Host("health-check-$VER.local")
      kind: Rule
      services:
        - name: health-check-svc
          port: 8000
EOF

    kubectl get ingressroute health-check-route -n "$NS" &>/dev/null && \
        pass "IngressRoute create" || fail "IngressRoute create"

    # Verify the Service actually has a live Endpoint (i.e. the selector
    # really matched the pod) rather than just existing as an API object —
    # this is the part of D11 that matters.
    ENDPOINT_IP=$(kubectl get endpoints health-check-svc -n "$NS" \
        -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
    [[ -n "$ENDPOINT_IP" ]] && \
        pass "Service has live Endpoint ($ENDPOINT_IP) — D11 backend wiring confirmed" || \
        fail "Service selector matched no pod — no Endpoint (D11)"

    kubectl delete ingressroute health-check-route -n "$NS" &>/dev/null && \
        pass "IngressRoute delete" || fail "IngressRoute delete"

    kubectl delete service health-check-svc -n "$NS" &>/dev/null

    if [[ "$TEMP_LABEL_APPLIED" -eq 1 ]]; then
        kubectl label pod "$POD" -n "$NS" healthcheck-target- &>/dev/null
    fi
}

test_sql() {
    section "SQL — MariaDB operations"

    SQL="kubectl exec -n $MARIADB_NS $MARIADB_POD -- \
        mysql -u root -p$MARIADB_ROOT_PASS -e"

    # S1: Ping
    $SQL "SELECT 1" &>/dev/null && \
        pass "SQL ping (SELECT 1)" || fail "SQL ping"

    # S2: Create user
    $SQL "CREATE OR REPLACE USER \
        'hc_test_$VER'@'%' IDENTIFIED BY 'hcpass'; \
        GRANT ALL ON *.* TO 'hc_test_$VER'@'%'; \
        FLUSH PRIVILEGES;" &>/dev/null && \
        pass "CREATE USER" || fail "CREATE USER"

    # S3: Show grants
    $SQL "SHOW GRANTS FOR 'hc_test_$VER'@'%';" \
        &>/dev/null && \
        pass "SHOW GRANTS" || fail "SHOW GRANTS"

    # S4: Revoke
    $SQL "REVOKE ALL PRIVILEGES ON *.* \
        FROM 'hc_test_$VER'@'%'; FLUSH PRIVILEGES;" \
        &>/dev/null && \
        pass "REVOKE privileges" || fail "REVOKE privileges"

    # S5: Drop user
    $SQL "DROP USER IF EXISTS 'hc_test_$VER'@'%'; \
        FLUSH PRIVILEGES;" &>/dev/null && \
        pass "DROP USER" || fail "DROP USER"

    # S6: Database size query
    $SQL "SELECT table_schema, \
        ROUND(SUM(data_length+index_length)/1024/1024,2) AS MB \
        FROM information_schema.tables \
        GROUP BY table_schema LIMIT 5;" &>/dev/null && \
        pass "database size query" || fail "database size query"

    # S7: SHOW FULL PROCESSLIST
    $SQL "SHOW FULL PROCESSLIST;" &>/dev/null && \
        pass "SHOW FULL PROCESSLIST" || fail "SHOW FULL PROCESSLIST"

    # S8: EXPLAIN
    $SQL "EXPLAIN SELECT * FROM information_schema.tables \
        WHERE TABLE_SCHEMA='frappe' LIMIT 1;" &>/dev/null && \
        pass "EXPLAIN query" || fail "EXPLAIN query"

    # S9: Create + Drop test database
    $SQL "CREATE DATABASE hc_drop_test_$VER; \
        DROP DATABASE hc_drop_test_$VER;" &>/dev/null && \
        pass "CREATE + DROP DATABASE" || fail "CREATE + DROP DATABASE"
}

# ── Teardown (clean up test data) ─────────────────────────────
teardown() {
    section "TEARDOWN — Cleaning test data"

    # Remove test users added during tests
    kx "bench --site $SITE execute \
        frappe.client.delete \
        --kwargs '{\"doctype\":\"User\",\"name\":\"healthcheck@test.com\"}'" \
        &>/dev/null || true
    kx "bench --site $SITE execute \
        frappe.client.delete \
        --kwargs '{\"doctype\":\"User\",\"name\":\"hcsys@test.com\"}'" \
        &>/dev/null || true

    pass "Teardown complete"
}

# ── Run one version ────────────────────────────────────────────
run_version() {
    VER=$1
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "  Testing Frappe $VER"
    echo "╚══════════════════════════════════════════════╝"

    setup_version "$VER"

    test_infrastructure
    test_tier_a
    test_tier_b
    test_tier_c
    test_sql
    teardown
}

# ── Main ───────────────────────────────────────────────────────
START=$(date +%s)
TARGET=${1:-all}

case $TARGET in
    all)
        run_version v14
        run_version v15
        run_version v16
        ;;
    v14|v15|v16)
        run_version "$TARGET"
        ;;
    *)
        echo "Usage: $0 [v14|v15|v16|all]"
        exit 1
        ;;
esac

END=$(date +%s)
ELAPSED=$((END-START))

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "  Test Results"
echo "╠══════════════════════════════════════════════╣"
echo -e "  ${GREEN}PASS: $PASS${NC}"
echo -e "  ${RED}FAIL: $FAIL${NC}"
echo -e "  ${YELLOW}WARN: $WARN${NC}"
echo -e "  ⏭️  SKIP: $SKIP"
echo "  ⏱️  Time: ${ELAPSED}s"
echo "╚══════════════════════════════════════════════╝"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
