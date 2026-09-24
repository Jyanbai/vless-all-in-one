#!/usr/bin/env bash
# Schema/data tests: migrate .service_outbound.mieru → per-instance instance_outbound (v3.5.27)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/vless-server.sh"
PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== A: bash -n ==="
if bash -n "$SCRIPT"; then pass "bash -n"; else fail "bash -n"; fi

echo "=== B: symbol present ==="
if grep -q '^db_migrate_mieru_service_outbound_to_instances()' "$SCRIPT"; then
  pass "symbol db_migrate_mieru_service_outbound_to_instances"
else
  fail "missing db_migrate_mieru_service_outbound_to_instances"
fi
if grep -q 'v3.5.27 mieru outbound migrate' "$SCRIPT"; then
  pass "startup wire comment"
else
  fail "startup wire missing"
fi
# rename must NOT write service_outbound.mieru anymore (instance path covers mieru)
if awk '/^db_rename_chain_node\(\)/{f=1} f{print} f && /^\}$/{exit}' "$SCRIPT" | grep -q 'service_outbound.mieru'; then
  fail "db_rename_chain_node still writes service_outbound.mieru"
else
  pass "db_rename_chain_node has no service_outbound.mieru branch"
fi

# --- harness: extract real DB helpers into a temp env with non-readonly CFG/DB_FILE ---
_load_db_harness() {
  local cfg="$1"
  local harness
  harness=$(mktemp)
  cat > "$harness" <<'HS'
set -euo pipefail
R=''; G=''; Y=''; C=''; M=''; W=''; D=''; NC=''
_log() { :; }
_err() { echo "ERR: $*" >&2; }
_ok() { :; }
_warn() { :; }
HS
  # Extract supporting vars + functions from script (line ranges are stable around helpers)
  # Pull _db_port_key_jq assignment and lock/init/_db_apply + outbound helpers + migrate
  awk '
    BEGIN { want=0 }
    /^_db_port_key_jq=/ { print; next }
    /^(DB_LOCK_FD=|DB_LOCK_DIR_HELD=)/ { print; next }
    /^(_db_lock_acquire|_db_lock_release|init_db|_db_apply|db_list_ports|db_get_port_config|db_get_instance_outbound|db_set_instance_outbound|db_clear_instance_outbound|db_get_service_outbound_mieru|db_set_service_outbound_mieru|db_clear_service_outbound_mieru|db_migrate_mieru_service_outbound_to_instances)\(\)/ {
      want=1
    }
    want { print }
    want && /^}$/ { want=0; print "" }
  ' "$SCRIPT" >> "$harness"
  # Prepend CFG/DB_FILE (non-readonly)
  {
    echo "CFG=\"$cfg\""
    echo "DB_FILE=\"\$CFG/db.json\""
    echo "DB_LOCK_FILE=\"\$CFG/.db.lock\""
    echo "LOG_FILE=\"\$CFG/test.log\""
    cat "$harness"
  } > "${harness}.full"
  mv "${harness}.full" "$harness"
  echo "$harness"
}

_write_fixture_with_svc() {
  local db="$1" svc="${2:-direct}"
  cat > "$db" <<JSON
{
  "version": "4.0.0",
  "service_outbound": { "mieru": "$svc" },
  "xray": {
    "mieru": [
      {
        "port": 4405,
        "users": [{"name":"u1","password":"KEEP_PASS_A","enabled":true}],
        "bindIP": "0.0.0.0"
      },
      {
        "port": 4406,
        "users": [{"name":"u2","password":"KEEP_PASS_B","enabled":true}],
        "bindIP": "0.0.0.0"
      }
    ],
    "vless": {
      "port": 443,
      "users": [{"name":"v1","uuid":"KEEP-UUID-1111","enabled":true}]
    }
  },
  "singbox": {},
  "meta": {"created":"2026-01-01T00:00:00+0800","updated":"2026-01-01T00:00:00+0800"}
}
JSON
}

_write_fixture_empty_svc() {
  local db="$1"
  cat > "$db" <<'JSON'
{
  "version": "4.0.0",
  "service_outbound": { "mieru": "" },
  "xray": {
    "mieru": [
      {
        "port": 4405,
        "users": [{"name":"u1","password":"KEEP_PASS_A","enabled":true}]
      },
      {
        "port": 4406,
        "users": [{"name":"u2","password":"KEEP_PASS_B","enabled":true}]
      }
    ]
  },
  "meta": {"created":"2026-01-01T00:00:00+0800","updated":"2026-01-01T00:00:00+0800"}
}
JSON
}

echo "=== C: functional migrate service=direct → instance_outbound ==="
TMPC=$(mktemp -d)
mkdir -p "$TMPC"
_write_fixture_with_svc "$TMPC/db.json" "direct"
HARNESS=$(_load_db_harness "$TMPC")
USERS_BEFORE=$(jq -c '.xray.mieru | map(.users)' "$TMPC/db.json")
VLESS_BEFORE=$(jq -c '.xray.vless.users' "$TMPC/db.json")
if bash -c "source '$HARNESS'; db_migrate_mieru_service_outbound_to_instances"; then
  pass "migrate returned 0"
else
  fail "migrate returned nonzero"
fi
ob5=$(jq -r '.xray.mieru[] | select(.port==4405) | .instance_outbound // empty' "$TMPC/db.json")
ob6=$(jq -r '.xray.mieru[] | select(.port==4406) | .instance_outbound // empty' "$TMPC/db.json")
svc=$(jq -r '.service_outbound.mieru // empty' "$TMPC/db.json")
has_svc_key=$(jq -r '(.service_outbound // {}) | has("mieru")' "$TMPC/db.json")
[[ "$ob5" == "direct" && "$ob6" == "direct" ]] && pass "both instances instance_outbound=direct" || fail "instances ob5=$ob5 ob6=$ob6"
[[ -z "$svc" ]] && pass "service_outbound.mieru empty/absent" || fail "service still=$svc"
[[ "$has_svc_key" == "false" ]] && pass "mieru key removed from service_outbound" || fail "mieru key still present"
# no leftover snap
shopt -s nullglob
snaps=("$TMPC"/db.json.mig-mieru-ob.*)
[[ ${#snaps[@]} -eq 0 ]] && pass "snap cleaned" || fail "snap leftover: ${snaps[*]}"
shopt -u nullglob
rm -f "$HARNESS"
rm -rf "$TMPC"

echo "=== D: empty service → no instance_outbound written, service cleared ==="
TMPD=$(mktemp -d)
mkdir -p "$TMPD"
_write_fixture_empty_svc "$TMPD/db.json"
HARNESS=$(_load_db_harness "$TMPD")
if bash -c "source '$HARNESS'; db_migrate_mieru_service_outbound_to_instances"; then
  pass "empty-svc migrate returned 0"
else
  fail "empty-svc migrate failed"
fi
wrote=$(jq '[.xray.mieru[] | select(has("instance_outbound"))] | length' "$TMPD/db.json")
svc=$(jq -r '.service_outbound.mieru // empty' "$TMPD/db.json")
has_key=$(jq -r '(.service_outbound // {}) | has("mieru")' "$TMPD/db.json")
[[ "$wrote" == "0" ]] && pass "no instance_outbound written" || fail "wrote instance_outbound count=$wrote"
[[ -z "$svc" && "$has_key" == "false" ]] && pass "empty service cleared" || fail "svc=$svc has_key=$has_key"
rm -f "$HARNESS"
rm -rf "$TMPD"

echo "=== E: fail-closed restore when set fails ==="
TMPE=$(mktemp -d)
mkdir -p "$TMPE"
_write_fixture_with_svc "$TMPE/db.json" "warp"
BEFORE=$(cat "$TMPE/db.json")
HARNESS=$(_load_db_harness "$TMPE")
# Force set to fail after harness load
rc=0
bash -c "
  source '$HARNESS'
  db_set_instance_outbound() { return 1; }
  db_migrate_mieru_service_outbound_to_instances
" || rc=$?
[[ "$rc" -ne 0 ]] && pass "migrate failed as expected (rc=$rc)" || fail "migrate should fail when set fails"
AFTER=$(cat "$TMPE/db.json")
# service must still be present (restored)
svc=$(jq -r '.service_outbound.mieru // empty' "$TMPE/db.json")
[[ "$svc" == "warp" ]] && pass "service_outbound.mieru restored to warp" || fail "service after fail=$svc"
wrote=$(jq '[.xray.mieru[] | select(has("instance_outbound"))] | length' "$TMPE/db.json")
[[ "$wrote" == "0" ]] && pass "no partial instance_outbound after fail" || fail "partial writes=$wrote"
# content restored (ignore meta.updated drift from any partial apply — compare structural fields)
same=$(jq -n --argjson a "$(jq 'del(.meta)' <<<"$BEFORE")" --argjson b "$(jq 'del(.meta)' "$TMPE/db.json")" '$a == $b')
[[ "$same" == "true" ]] && pass "DB structural content restored" || fail "DB not restored structurally"
shopt -s nullglob
snaps=("$TMPE"/db.json.mig-mieru-ob.*)
[[ ${#snaps[@]} -eq 0 ]] && pass "fail path snap cleaned" || fail "fail path snap leftover"
shopt -u nullglob
rm -f "$HARNESS"
rm -rf "$TMPE"

echo "=== F: identity/keys unchanged after successful migrate ==="
TMPF=$(mktemp -d)
mkdir -p "$TMPF"
_write_fixture_with_svc "$TMPF/db.json" "direct"
HARNESS=$(_load_db_harness "$TMPF")
USERS_BEFORE=$(jq -c '{mieru:(.xray.mieru|map(.users)), vless:.xray.vless.users}' "$TMPF/db.json")
bash -c "source '$HARNESS'; db_migrate_mieru_service_outbound_to_instances" || true
USERS_AFTER=$(jq -c '{mieru:(.xray.mieru|map(.users)), vless:.xray.vless.users}' "$TMPF/db.json")
[[ "$USERS_BEFORE" == "$USERS_AFTER" ]] && pass "users/passwords/uuids unchanged" || fail "identity mutated: before=$USERS_BEFORE after=$USERS_AFTER"
# passwords specifically
p1=$(jq -r '.xray.mieru[]|select(.port==4405)|.users[0].password' "$TMPF/db.json")
p2=$(jq -r '.xray.mieru[]|select(.port==4406)|.users[0].password' "$TMPF/db.json")
u1=$(jq -r '.xray.vless.users[0].uuid' "$TMPF/db.json")
[[ "$p1" == "KEEP_PASS_A" && "$p2" == "KEEP_PASS_B" && "$u1" == "KEEP-UUID-1111" ]] && pass "literal secrets intact" || fail "secrets changed p1=$p1 p2=$p2 u1=$u1"
rm -f "$HARNESS"
rm -rf "$TMPF"

echo "=== G: VERSION present (Documentor-owned) ==="
VER=$(grep -m1 '^readonly VERSION=' "$SCRIPT" | cut -d'"' -f2)
[[ -n "$VER" ]] && pass "VERSION=$VER" || fail "VERSION missing"

echo "=== H: service setter hard-error (no new writes) ==="
if grep -A8 '^db_set_service_outbound_mieru()' "$SCRIPT" | grep -q '_db_apply'; then
  fail "db_set_service_outbound_mieru still writes via _db_apply"
else
  pass "setter has no _db_apply write path"
fi
if grep -A6 '^db_set_service_outbound_mieru()' "$SCRIPT" | grep -q 'return 1'; then
  pass "setter returns 1"
else
  fail "setter missing return 1"
fi
if grep -A5 '^db_set_service_outbound_mieru()' "$SCRIPT" | grep -q '已移除'; then
  pass "setter hard-error message"
else
  fail "setter missing hard-error message"
fi
# comment: migration-only get/clear
if grep -q 'migration-only get/clear' "$SCRIPT"; then
  pass "migration-only get/clear comment"
else
  fail "stale service comment"
fi
if grep -q 'Kept until Implementer rewires callers' "$SCRIPT"; then
  fail "stale Implementer-rewire comment still present"
else
  pass "stale Implementer-rewire comment gone"
fi
TMPH=$(mktemp -d)
HARNESS=$(_load_db_harness "$TMPH")
echo '{}' > "$TMPH/db.json"
if bash -c "source '$HARNESS'; db_set_service_outbound_mieru direct"; then
  fail "setter unexpectedly succeeded"
else
  pass "runtime setter call fails"
fi
# must not create service_outbound.mieru
has=$(jq -r '(.service_outbound // {}) | has("mieru")' "$TMPH/db.json")
[[ "$has" == "false" ]] && pass "setter did not write service field" || fail "service field written"
rm -f "$HARNESS"
rm -rf "$TMPH"

echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
