#!/usr/bin/env bash
# Local semantic tests for per-instance routing profiles (v3.5.28/3.5.29 DA)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/vless-server.sh"
PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== A: bash -n ==="
if bash -n "$SCRIPT"; then pass "bash -n"; else fail "bash -n"; fi

echo "=== B: VERSION sync (accept current script VERSION; no bump required in DA) ==="
VER=$(grep -m1 '^readonly VERSION=' "$SCRIPT" | cut -d'"' -f2)
R=$(sed -n 's/^Current script version: \*\*v\([0-9.]*\)\*\*.*/\1/p' "$ROOT/README.md" | head -1)
C=$(sed -n 's/^当前脚本版本：\*\*v\([0-9.]*\)\*\*.*/\1/p' "$ROOT/README_CN.md" | head -1)
if [[ -n "$VER" && "$VER" == "$R" && "$VER" == "$C" ]]; then
  pass "VERSION=$VER synced"
else
  fail "VERSION mismatch script=$VER readme=$R cn=$C"
fi

echo "=== C: symbols present ==="
for s in db_routing_profile_exists db_list_routing_profiles db_get_routing_profile \
         db_add_routing_profile db_update_routing_profile db_delete_routing_profile \
         db_copy_routing_profile db_list_instances_using_profile \
         db_get_routing_profile_rules db_set_routing_profile_rules \
         db_add_routing_profile_rule db_delete_routing_profile_rule \
         db_get_telegram_dc_matchers db_set_telegram_dc_matchers \
         db_seed_telegram_dc_matchers_if_absent db_ensure_routing_profiles_defaults \
         db_routing_template_rules_finance_crypto db_routing_template_rules_telegram_dc \
         db_routing_template_rules_ai_media db_routing_template_rules \
         _db_routing_rule_outbound_ok _db_routing_rules_outbounds_ok \
         db_audit_routing_profiles_nested db_repair_routing_profiles_nested \
         db_migrate_routing_profiles_v3529 \
         _resolve_profile_rule_outbound _gen_xray_profile_inbound_rules \
         _gen_xray_profile_outbound_needs _mieru_expand_profile_rules \
         _list_profiles_referencing_outbound _routing_profile_validate_and_apply \
         manage_routing_profiles wizard_home_broadband_direct_backup; do
  if grep -q "^${s}()" "$SCRIPT"; then pass "symbol $s"; else fail "missing $s"; fi
done
grep -q '分流规则集' "$SCRIPT" && pass "UI marker 分流规则集" || fail "UI marker missing"
grep -q '家宽 + 直出备用' "$SCRIPT" && pass "wizard marker" || fail "wizard marker missing"

echo "=== D: profile:<id> vocab resolve fail-closed missing ==="
awk '/^_resolve_instance_outbound_target\(\)/,/^gen_xray_instance_outbound_needs|^# v3.5.28 product/' "$SCRIPT" | grep -q 'db_routing_profile_exists'   && pass "resolve checks exists" || fail "resolve missing exists"
grep -A30 '^db_set_instance_outbound()' "$SCRIPT" | grep -q 'profile:\*' && pass "setter accepts profile" || fail "setter no profile"

echo "=== E: unmatched inherits global (not direct) ==="
grep -q '无 catch-all\|inherit global\|继承全局' "$SCRIPT" && pass "inherit markers" || fail "no inherit markers"
if grep -A15 '_INSTANCE_OB_KIND" == "profile"' "$SCRIPT" | grep -q '_gen_xray_profile_inbound_rules'; then
  pass "profile uses multi-rule compile"
else
  fail "profile emit wrong"
fi

echo "=== F: Xray inboundTag scope on profile rules ==="
grep -A5 '_gen_xray_profile_inbound_rules' "$SCRIPT" | grep -q 'inboundTag' || \
  grep -n 'inboundTag:\$tags' "$SCRIPT" | grep -q . && pass "inboundTag in profile compile" || fail "no inboundTag"

echo "=== G: Mieru per-instance profile (no service-wide) ==="
grep -q '禁止 service-wide\|仅支持 per-instance\|仅限 per-instance' "$SCRIPT" && pass "no service-wide marker" || fail "missing per-instance guard"
grep -A30 'profile:\*)' "$SCRIPT" | grep -q '_mieru_expand_profile_rules\|_mieru_compile_egress_plan' && pass "mieru profile path" || \
  grep -q '_mieru_expand_profile_rules' "$SCRIPT" && pass "mieru expand present" || fail "mieru profile missing"

echo "=== H: DIRECT does not reorder ==="
grep -q 'does NOT reorder by outbound=direct\|DIRECT does not\|不浮动 DIRECT\|不重排' "$SCRIPT" && pass "no DIRECT reorder" || fail "reorder note missing"

echo "=== I: ensure does NOT auto-create finance/tg/ai profiles ==="
block=$(awk '/^db_ensure_routing_profiles_defaults\(\)/{f=1} f{print} f && /^}$/{exit}' "$SCRIPT")
if echo "$block" | grep -q 'db_add_routing_profile "finance_crypto"\|db_add_routing_profile "telegram_dc"\|db_add_routing_profile "ai_media"'; then
  fail "ensure still seeds finance/tg/ai profiles"
else
  pass "ensure does not seed finance/tg/ai"
fi
echo "$block" | grep -q 'db_seed_telegram_dc_matchers_if_absent' && pass "ensure seeds telegram matchers" || fail "ensure missing matchers seed"
echo "$block" | grep -q 'routing_profiles' && pass "ensure array init" || fail "ensure no array init"

echo "=== J: Telegram DC uses matchers not fake geoip:telegram ==="
grep -q 'geoip:telegram' "$SCRIPT" && {
  grep -q '规则集禁止 geoip:telegram' "$SCRIPT" && pass "profile forbids geoip:telegram" || fail "no forbid"
} || pass "no geoip:telegram at all"
grep -q 'telegram_dc_matchers\|type":"telegram_dc"\|type=telegram_dc\|telegram_dc' "$SCRIPT" && pass "uses telegram_dc type/matchers" || fail "no tg dc"

echo "=== K: unknown→TG fallback in template ==="
grep -A20 '^db_routing_template_rules_telegram_dc()' "$SCRIPT" | grep -q 'geosite:telegram' && pass "geosite:telegram fallback in template" || \
  grep -q 'tg_fallback\|geosite:telegram' "$SCRIPT" && pass "tg fallback present" || fail "no tg fallback"

echo "=== L: chain/balancer/WARP guards see profiles ==="
grep -q '_list_profiles_referencing_outbound' "$SCRIPT" && pass "profile outbound scanner" || fail "no scanner"
grep -A45 '^db_del_chain_node()' "$SCRIPT" | grep -q '_list_profiles_referencing_outbound' && pass "chain guard profiles" || fail "chain guard"
grep -A45 '^db_delete_balancer_group()' "$SCRIPT" | grep -q '_list_profiles_referencing_outbound' && pass "balancer guard profiles" || fail "balancer guard"
grep -A55 '^uninstall_warp()' "$SCRIPT" | grep -q '_list_profiles_referencing_outbound' && pass "warp guard profiles" || fail "warp guard"

echo "=== M: shared-profile edit transactional markers ==="
grep -q 'profile-apply' "$SCRIPT" && pass "profile-apply marker" || fail "no profile-apply"
grep -q '_routing_profile_validate_and_apply' "$SCRIPT" && pass "validate_and_apply" || fail "no validate helper"
grep -A35 '^_routing_profile_validate_and_apply()' "$SCRIPT" | grep -q 'Dry-run Xray' && pass "dry-compile xray unused" || fail "no xray dry-compile"
grep -A40 '^_routing_profile_validate_and_apply()' "$SCRIPT" | grep -q 'Dry-run Mieru' && pass "dry-compile mieru unused" || fail "no mieru dry-compile"
grep -A40 '^_routing_profile_validate_and_apply()' "$SCRIPT" | grep -q 'dry-compile' && pass "dry-compile marker" || fail "no dry-compile marker"

echo "=== N: template ids + fallback=inherit ==="
for id in ai_media finance_crypto telegram_dc; do
  grep -q "db_routing_template_rules_${id}\|\"$id\"" "$SCRIPT" && pass "template/id $id" || fail "missing template $id"
done
grep -q 'fallback: "inherit"\|fallback:"inherit"\|fallback = "inherit"' "$SCRIPT" && pass "fallback inherit" || fail "no fallback inherit"

echo "=== O: display name profile ==="
grep -A20 '^_get_outbound_display_name()' "$SCRIPT" | grep -q 'profile:\*' && pass "display profile" || fail "display missing profile"

echo "=== P: select_outbound includes profiles ==="
grep -A80 '^_select_outbound()' "$SCRIPT" | grep -q 'profile:' && pass "select profiles" || fail "select no profile"

echo "=== Q: menu 10/11 ==="
grep -A40 '^manage_routing()' "$SCRIPT" | grep -q '分流规则集' && pass "menu 10" || fail "menu 10"
grep -A40 '^manage_routing()' "$SCRIPT" | grep -q '家宽' && pass "menu 11" || fail "menu 11"

echo "=== R: jq unit — profile rule inboundTag shape ==="
rule=$(jq -n --argjson tags '["vless-443"]' --arg tag "direct-prefer-ipv4" \
  --argjson domains '["geosite:openai"]' \
  '{type:"field", inboundTag:$tags, domain:$domains, outboundTag:$tag}')
echo "$rule" | jq -e 'has("inboundTag") and has("outboundTag") and (has("balancerTag")|not)' >/dev/null \
  && pass "sample profile rule shape" || fail "jq shape"

echo "=== S: template helpers return JSON arrays ==="
# Extract + run template helpers via mini harness
_TMP=$(mktemp -d)
_H="$_TMP/h.sh"
{
  echo 'set -euo pipefail'
  echo '_err(){ echo "ERR: $*" >&2; }'
  awk '/^db_routing_template_rules_finance_crypto\(\)/{f=1} f{print} f && /^}$/{if(++c==1){f=0}}' "$SCRIPT"
  awk '/^db_routing_template_rules_telegram_dc\(\)/{f=1} f{print} f && /^}$/{if(++c==1){f=0}}' "$SCRIPT"
  awk '/^db_routing_template_rules_ai_media\(\)/{f=1} f{print} f && /^}$/{if(++c==1){f=0}}' "$SCRIPT"
  awk '/^db_routing_template_rules\(\)/{f=1} f{print} f && /^}$/{if(++c==1){f=0}}' "$SCRIPT"
  cat <<'HS'
fc=$(db_routing_template_rules_finance_crypto)
tg=$(db_routing_template_rules_telegram_dc)
ai=$(db_routing_template_rules_ai_media)
disp=$(db_routing_template_rules finance_crypto chain:X)
echo "$fc" | jq -e 'type=="array" and length==2 and .[0].id=="fc_crypto"' >/dev/null
echo "$tg" | jq -e 'type=="array" and (.[0].type=="telegram_dc") and (map(.domains // "") | any(.=="geosite:telegram"))' >/dev/null
echo "$ai" | jq -e 'type=="array" and length==2' >/dev/null
echo "$disp" | jq -e '.[0].outbound=="chain:X"' >/dev/null
# must not contain geoip:telegram
echo "$tg" | jq -e 'tostring | contains("geoip:telegram") | not' >/dev/null
HS
} > "$_H"
if bash "$_H"; then pass "templates return JSON arrays"; else fail "templates JSON"; fi
rm -rf "$_TMP"

echo "=== T: telegram matchers schema keys ==="
grep -A30 '^db_seed_telegram_dc_matchers_if_absent()' "$SCRIPT" | grep -q 'dc1:' && pass "dc1 seed" || fail "dc1"
grep -A30 '^db_seed_telegram_dc_matchers_if_absent()' "$SCRIPT" | grep -q 'note:' && pass "note field" || fail "note"

echo "=== U: needs collects profile outbounds ==="
grep -A25 '^gen_xray_instance_outbound_needs()' "$SCRIPT" | grep -q 'profile:\*' && pass "needs profile" || fail "needs no profile"

echo "=== V: rule helpers reject profile:* (symbol + code) ==="
grep -A25 '^_db_routing_rule_outbound_ok()' "$SCRIPT" | grep -q 'profile:\*' && pass "rule outbound rejects profile" || fail "no reject"
grep -A20 '^db_add_routing_profile_rule()' "$SCRIPT" | grep -q '_db_routing_rule_outbound_ok' && pass "add_rule validates" || fail "add_rule no validate"
grep -A20 '^db_set_routing_profile_rules()' "$SCRIPT" | grep -q '_db_routing_rules_outbounds_ok' && pass "set_rules validates" || fail "set_rules no validate"
grep -A25 '^db_add_routing_profile()' "$SCRIPT" | grep -q '_db_routing_rules_outbounds_ok' && pass "add_profile validates" || fail "add_profile no validate"
grep -A30 '^db_update_routing_profile()' "$SCRIPT" | grep -q '_db_routing_rules_outbounds_ok' && pass "update_profile validates" || fail "update_profile no validate"

echo "=== W: fail-closed missing profile in resolve ==="
grep -n '分流规则集不存在' "$SCRIPT" | grep -q . && pass "fail-closed msg" || fail "no fail-closed msg"

echo "=== X: mieru profile merges global (pref + glob) ==="
grep -n '\$p + \$g\|$p + $g' "$SCRIPT" | grep -q . && pass "mieru merge profile+global" || \
  grep -q "\$p + \$g" "$SCRIPT" && pass "mieru merge" || fail "no merge"

echo "=== Y: home_broadband wizard id (legacy; migrate renames) ==="
grep -q 'home_broadband' "$SCRIPT" && pass "home_broadband id" || fail "no home_broadband"
grep -q 'db_migrate_routing_profiles_v3529' "$SCRIPT" && pass "migrate symbol wired in script" || fail "no migrate"

echo "=== Z: v3.5.28/29 markers present (no forced VERSION bump) ==="
grep -q 'v3.5.28\|v3.5.29' "$SCRIPT" && pass "v3.5.28/29 markers" || fail "no version markers"
grep -q 'v3.5.29 routing profiles migrate' "$SCRIPT" && pass "startup migrate wire" || fail "no startup wire"

echo "=== AA: instance rules priority comment intact ==="
grep -q '用户 > 实例 > 全局' "$SCRIPT" && pass "priority comment" || fail "priority missing"

echo "=== AB: template telegram clean of geoip:telegram ==="
block=$(awk '/^db_routing_template_rules_telegram_dc\(\)/,/^}$/' "$SCRIPT" | head -30)
echo "$block" | grep -q 'geoip:telegram' && fail "template has geoip:telegram" || pass "template clean of geoip:telegram"

echo "=== AC: offline DB smoke — ensure + migrate A/B/C/home ==="
TMP=$(mktemp -d)
CFG="$TMP"
DB_FILE="$TMP/db.json"
DB_LOCK_FILE="$TMP/.db.lock"
LOG_FILE="$TMP/test.log"
export CFG DB_FILE DB_LOCK_FILE LOG_FILE
HARNESS=$(mktemp)
{
  cat <<'HS'
set -euo pipefail
R=''; G=''; Y=''; C=''; M=''; W=''; D=''; NC=''
_log(){ :; }
_err(){ echo "ERR: $*" >&2; }
_ok(){ :; }
_warn(){ :; }
HS
  # Extract needed helpers (include locks/init/apply + routing profile stack + list outbound)
  awk '
    BEGIN { want=0 }
    /^_db_port_key_jq=/ { print; next }
    /^(DB_LOCK_FD=|DB_LOCK_DIR_HELD=)/ { print; next }
    /^(_db_lock_acquire|_db_lock_release|init_db|_db_apply|db_list_ports|db_get_port_config|db_get_instance_outbound|db_set_instance_outbound|db_clear_instance_outbound|db_list_instances_using_outbound|_db_routing_profile_id_ok|_db_routing_rule_outbound_ok|_db_routing_rules_outbounds_ok|db_routing_profile_exists|db_list_routing_profiles|db_get_routing_profile|db_add_routing_profile|db_update_routing_profile|db_delete_routing_profile|db_list_instances_using_profile|db_get_routing_profile_rules|db_set_routing_profile_rules|db_add_routing_profile_rule|db_get_telegram_dc_matchers|db_set_telegram_dc_matchers|db_seed_telegram_dc_matchers_if_absent|db_routing_template_rules_finance_crypto|db_routing_template_rules_telegram_dc|db_routing_template_rules_ai_media|db_routing_template_rules|_db_routing_profile_rules_exact_seed|db_ensure_routing_profiles_defaults|db_audit_routing_profiles_nested|db_repair_routing_profiles_nested|_db_migrate_drop_unused_exact_seed_profile|_db_rewrite_instance_outbound_value|db_migrate_routing_profiles_v3529)\(\)/ {
      want=1
    }
    want { print }
    want && /^}$/ { want=0; print "" }
  ' "$SCRIPT"
} > "$HARNESS"

# Prepend CFG bindings
{
  echo "CFG=\"$CFG\""
  echo "DB_FILE=\"\$CFG/db.json\""
  echo "DB_LOCK_FILE=\"\$CFG/.db.lock\""
  echo "LOG_FILE=\"\$CFG/test.log\""
  cat "$HARNESS"
  cat <<'BODY'
init_db

# 1) ensure does NOT create the three profiles
db_ensure_routing_profiles_defaults
for id in finance_crypto telegram_dc ai_media; do
  if db_routing_profile_exists "$id"; then
    echo "ENSURE_CREATED $id" >&2
    exit 10
  fi
done
# matchers seeded
src=$(jq -r '.telegram_dc_matchers.source // empty' "$DB_FILE")
[[ -n "$src" ]] || { echo "NO_MATCHERS" >&2; exit 11; }

# 2) rule reject profile:*
db_add_routing_profile "home" "家宽" '[]'
if db_add_routing_profile_rule "home" '{"id":"bad","type":"custom","domains":"geosite:openai","outbound":"profile:other","ip_version":"prefer_ipv4"}' 2>/dev/null; then
  echo "NESTED_ACCEPTED" >&2
  exit 12
fi
if db_set_routing_profile_rules "home" '[{"id":"bad","type":"custom","domains":"x","outbound":"profile:x","ip_version":"prefer_ipv4"}]' 2>/dev/null; then
  echo "SET_NESTED_ACCEPTED" >&2
  exit 13
fi

# 3) migrate A/B/C: unused exact seed → delete
seed_fc=$(db_routing_template_rules_finance_crypto direct)
seed_tg=$(db_routing_template_rules_telegram_dc direct)
seed_ai=$(db_routing_template_rules_ai_media direct)
# inject via raw _db_apply to bypass validators if needed — seeds use direct so OK
db_add_routing_profile "finance_crypto" "金融/加密" "$seed_fc"
db_add_routing_profile "telegram_dc" "Telegram DC" "$seed_tg"
db_add_routing_profile "ai_media" "AI/流媒体" "$seed_ai"
# used modified keep: create modified unused + used exact
db_add_routing_profile "keep_mod" "mod" '[{"id":"m1","type":"custom","domains":"geosite:openai","outbound":"direct","ip_version":"prefer_ipv4"}]'
# mark finance as used: need a mieru/vless instance — write fixture rows
_db_apply '
  .xray.vless = [{port:443, users:[{name:"u",uuid:"U",enabled:true}], instance_outbound:"profile:finance_crypto"}]
'
# wait — finance_crypto is exact seed AND used → KEEP
# telegram_dc exact unused → DELETE
# ai_media: modify then unused → KEEP
db_set_routing_profile_rules "ai_media" '[{"id":"ai_intl","type":"custom","domains":"geosite:openai","outbound":"direct","ip_version":"prefer_ipv4"}]'

# home_broadband rename
db_add_routing_profile "home_broadband" "家宽+直出备用" '[{"id":"hb1","type":"custom","domains":"geosite:openai","outbound":"direct","ip_version":"prefer_ipv4"}]'
# but home already exists from step 2 — so migrate must LEAVE home_broadband
# delete home first to test rename path in a second DB... for this DB leave both

db_migrate_routing_profiles_v3529

db_routing_profile_exists "finance_crypto" || { echo "USED_SEED_DELETED" >&2; exit 14; }
db_routing_profile_exists "telegram_dc" && { echo "UNUSED_SEED_KEPT" >&2; exit 15; }
db_routing_profile_exists "ai_media" || { echo "MODIFIED_DELETED" >&2; exit 16; }
# home exists → home_broadband left
db_routing_profile_exists "home_broadband" || { echo "HB_CLOBBERED" >&2; exit 17; }
db_routing_profile_exists "home" || { echo "HOME_GONE" >&2; exit 18; }

# nested audit/repair
db_add_routing_profile "nest_victim" "nv" '[]'
# inject nested via raw apply (bypass validator)
_db_apply '
  .routing_profiles = ((.routing_profiles // []) | map(
    if .id == "nest_victim" then .rules = [{id:"n1", type:"custom", domains:"geosite:openai", outbound:"profile:home", ip_version:"prefer_ipv4"}] else . end
  ))
'
db_audit_routing_profiles_nested >/dev/null 2>&1 && { echo "AUDIT_MISS" >&2; exit 19; }
db_repair_routing_profiles_nested
db_audit_routing_profiles_nested >/dev/null 2>&1 || { echo "REPAIR_FAIL" >&2; exit 20; }
rules=$(db_get_routing_profile_rules nest_victim)
echo "$rules" | jq -e 'length==0' >/dev/null

# Second DB: home_broadband → home rename + instance rewrite
CFG2=$(dirname "$DB_FILE")/db2
mkdir -p "$CFG2"
DB_FILE="$CFG2/db.json"
DB_LOCK_FILE="$CFG2/.db.lock"
init_db
db_ensure_routing_profiles_defaults
rules_hb='[{"id":"hb1","type":"custom","domains":"geosite:openai","outbound":"direct","ip_version":"prefer_ipv4"}]'
db_add_routing_profile "home_broadband" "家宽+直出备用" "$rules_hb"
_db_apply '
  .xray.vless = [{port:8443, users:[{name:"u",uuid:"U",enabled:true}], instance_outbound:"profile:home_broadband"}]
'
db_migrate_routing_profiles_v3529
db_routing_profile_exists "home" || { echo "RENAME_FAIL" >&2; exit 21; }
db_routing_profile_exists "home_broadband" && { echo "OLD_ID_LEFT" >&2; exit 22; }
name=$(db_get_routing_profile home | jq -r .name)
[[ "$name" == "家宽" ]] || { echo "NAME_NOT_家宽:$name" >&2; exit 23; }
ob=$(jq -r '.xray.vless[0].instance_outbound' "$DB_FILE")
[[ "$ob" == "profile:home" ]] || { echo "OB_NOT_REWRITTEN:$ob" >&2; exit 24; }

echo SMOKE_OK
BODY
} > "${HARNESS}.run"
if bash "${HARNESS}.run"; then pass "offline ensure+migrate smoke"; else fail "offline smoke"; fi
rm -rf "$TMP" "$HARNESS" "${HARNESS}.run" 2>/dev/null || true

echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
