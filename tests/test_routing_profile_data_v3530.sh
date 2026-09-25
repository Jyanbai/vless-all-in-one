#!/usr/bin/env bash
# v3.5.30 data-layer tests: legacy routing-profile gate, no-op migration, write vocabulary.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/vless-server.sh"
PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
command -v jq >/dev/null || { echo "jq required"; exit 1; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
H="$WORK/harness.sh"
{
  echo "CFG=\"$WORK/cfg\""; echo 'DB_FILE="$CFG/db.json"'; echo 'DB_LOCK_FILE="$CFG/.db.lock"'
  echo "R='';G='';Y='';C='';D='';NC=''"
  echo '_log(){ :; }; _ok(){ :; }; _warn(){ :; }; _info(){ :; }; _err(){ echo "ERR: $*" >&2; }'
  awk '
    /^(_db_port_key_jq=|DB_LOCK_FD=|DB_LOCK_DIR_HELD=)/ { print; next }
    /^(_?db_[A-Za-z0-9_]*|init_db|_has_legacy_routing_profile_state)\(\) *\{/ { want=1 }
    want { print }
    want && /^\}$/ { want=0 }
  ' "$SCRIPT"
} > "$H"

reset_db() { rm -rf "$WORK/cfg"; mkdir -p "$WORK/cfg"; [[ -n "${1:-}" ]] && printf '%s\n' "$1" > "$WORK/cfg/db.json"; }
run() { bash -c "source '$H'; $*"; }
db() { cat "$WORK/cfg/db.json"; }
snaps() { ls "$WORK/cfg" | grep -c 'mig-rp' || true; }

CLEAN='{"version":"4.0.0","xray":{"vless":[{"port":443}],"mieru":[{"port":4405}]},"singbox":{},"meta":{}}'

echo "=== 1 fresh init_db has no routing_profiles ==="
reset_db; run init_db
jq -e 'has("routing_profiles")|not' "$WORK/cfg/db.json" >/dev/null && pass "init_db clean" || fail "init_db created routing_profiles"

echo "=== 2 clean DB: gate false, migration no write/snapshot ==="
reset_db "$CLEAN"; before=$(md5sum < "$WORK/cfg/db.json"); m1=$(stat -c %Y "$WORK/cfg/db.json")
run _has_legacy_routing_profile_state && fail "gate true on clean" || pass "gate false on clean"
run db_migrate_routing_profiles_v3529 && pass "migrate rc0" || fail "migrate rc!=0"
[[ "$(md5sum < "$WORK/cfg/db.json")" == "$before" ]] && pass "db byte-identical" || fail "db changed"
jq -e 'has("routing_profiles")|not' "$WORK/cfg/db.json" >/dev/null && pass "no routing_profiles key" || fail "key created"
[[ "$(snaps)" == 0 ]] && pass "no snapshot residue" || fail "snapshot residue"

echo "=== 3 gate true cases ==="
reset_db '{"xray":{},"routing_profiles":[{"id":"home","name":"家宽","rules":[]}]}'
run _has_legacy_routing_profile_state && pass "meaningful profiles" || fail "meaningful profiles"
reset_db '{"xray":{"vless":[{"port":443,"instance_outbound":"profile:home"}]}}'
run _has_legacy_routing_profile_state && pass "profile:* ref (xray)" || fail "profile:* ref"
reset_db '{"xray":{"mieru":[{"port":4405,"instance_outbound":"profile:x"}]}}'
run _has_legacy_routing_profile_state && pass "profile:* ref (mieru)" || fail "mieru ref"
reset_db '{"xray":{"vless":{"port":443,"instance_outbound":"profile:home_broadband"}}}'
run _has_legacy_routing_profile_state && pass "home_broadband ref" || fail "home_broadband ref"
reset_db '{"xray":{},"routing_profiles":[]}'
run _has_legacy_routing_profile_state && pass "empty-array artifact" || fail "artifact"
reset_db '{"xray":{"vless":[{"port":443,"instance_outbound":"direct"}]},"routing_profiles":null}'
run _has_legacy_routing_profile_state && fail "null/direct should be false" || pass "null key + direct = false"

echo "=== 4 artifact [] dropped, nothing else touched ==="
reset_db '{"xray":{"vless":[{"port":443,"instance_outbound":"warp"}]},"routing_profiles":[]}'
run db_migrate_routing_profiles_v3529 && pass "rc0" || fail "rc"
jq -e '(has("routing_profiles")|not) and .xray.vless[0].instance_outbound=="warp"' "$WORK/cfg/db.json" >/dev/null && pass "artifact removed" || fail "artifact handling"

echo "=== 5 legacy profile kept + runnable data intact ==="
L='{"xray":{"vless":[{"port":443,"instance_outbound":"profile:home"}],"mieru":[{"port":4405,"instance_outbound":"profile:home"}]},"routing_profiles":[{"id":"home","name":"家宽","fallback":"inherit","rules":[{"id":"r1","type":"custom","domains":"geosite:netflix","outbound":"direct"}]},{"id":"orphan","name":"o","rules":[]}]}'
reset_db "$L"
run db_migrate_routing_profiles_v3529 && pass "rc0" || fail "rc"
jq -e '(.routing_profiles|map(.id))==["home","orphan"] and .routing_profiles[0].rules[0].id=="r1" and .xray.mieru[0].instance_outbound=="profile:home"' "$WORK/cfg/db.json" >/dev/null && pass "legacy + orphan preserved" || fail "legacy altered"
[[ "$(snaps)" == 0 ]] && pass "snapshot cleaned" || fail "snapshot residue"

echo "=== 6 home_broadband rename still works ==="
reset_db '{"xray":{"vless":[{"port":443,"instance_outbound":"profile:home_broadband"}]},"routing_profiles":[{"id":"home_broadband","name":"家宽+直出备用","rules":[]}]}'
run db_migrate_routing_profiles_v3529 && pass "rc0" || fail "rc"
jq -e '.routing_profiles[0].id=="home" and .routing_profiles[0].name=="家宽" and .xray.vless[0].instance_outbound=="profile:home"' "$WORK/cfg/db.json" >/dev/null && pass "renamed" || fail "rename"

echo "=== 7 write vocabulary ==="
reset_db "$L"
for v in direct warp chain:JP balancer:g1; do
  run db_set_instance_outbound xray vless 443 "$v" 2>/dev/null && pass "accept $v" || fail "reject $v"
done
for v in chain: balancer: profile:home profile:orphan bogus block; do
  run db_set_instance_outbound xray vless 443 "$v" 2>/dev/null && fail "accepted $v" || pass "reject $v"
done
reset_db "$L"; before=$(md5sum < "$WORK/cfg/db.json")
run db_set_instance_outbound xray mieru 4405 profile:home && pass "same-value legacy keep rc0" || fail "keep"
[[ "$(md5sum < "$WORK/cfg/db.json")" == "$before" ]] && pass "keep wrote nothing" || fail "keep wrote"

echo "=== 8 leaving last ref keeps orphan profile ==="
reset_db "$L"
run db_set_instance_outbound xray vless 443 direct; run db_set_instance_outbound xray mieru 4405 ""
jq -e '(.routing_profiles|map(.id))==["home","orphan"] and (.xray.mieru[0]|has("instance_outbound")|not)' "$WORK/cfg/db.json" >/dev/null && pass "orphan preserved" || fail "orphan lost"

echo "=== 9 readers tolerate missing key ==="
reset_db "$CLEAN"
[[ "$(run db_list_routing_profiles)" == "[]" ]] && pass "list []" || fail "list"
run db_routing_profile_exists home && fail "exists on missing" || pass "exists false"
run db_get_routing_profile home >/dev/null 2>&1 && fail "get on missing" || pass "get fails closed"
jq -e 'has("routing_profiles")|not' "$WORK/cfg/db.json" >/dev/null && pass "readers no write" || fail "readers wrote"

echo "=== 10 static: no auto-create in product ==="
if grep -n 'routing_profiles = \[\]' "$SCRIPT" | grep -v '^\s*[0-9]*:\s*#' | grep -q .; then fail "auto-create remains"; else pass "no '.routing_profiles = []'"; fi
grep -q '^db_ensure_routing_profiles_defaults()' "$SCRIPT" && fail "defaults fn remains" || pass "defaults fn removed"

echo "=== 11 seed drop: exact name+rules only ==="
SEEDR=$(bash -c "source '$H'; db_routing_template_rules finance_crypto direct")
reset_db "{\"xray\":{},\"routing_profiles\":[{\"id\":\"finance_crypto\",\"name\":\"金融/加密\",\"fallback\":\"inherit\",\"rules\":$SEEDR}]}"
run db_migrate_routing_profiles_v3529 && jq -e 'has("routing_profiles")|not' "$WORK/cfg/db.json" >/dev/null && pass "exact unused seed dropped" || fail "exact seed not dropped"
reset_db "{\"xray\":{},\"routing_profiles\":[{\"id\":\"finance_crypto\",\"name\":\"我的金融\",\"fallback\":\"inherit\",\"rules\":$SEEDR}]}"
run db_migrate_routing_profiles_v3529 && jq -e '.routing_profiles[0].name=="我的金融"' "$WORK/cfg/db.json" >/dev/null && pass "renamed seed kept" || fail "renamed seed dropped"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
