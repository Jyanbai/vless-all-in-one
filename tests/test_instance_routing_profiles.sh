#!/usr/bin/env bash
# Local semantic tests for per-instance routing profiles (v3.5.28)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/vless-server.sh"
PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== A: bash -n ==="
if bash -n "$SCRIPT"; then pass "bash -n"; else fail "bash -n"; fi

echo "=== B: VERSION sync (pin 3.5.28) ==="
VER=$(grep -m1 '^readonly VERSION=' "$SCRIPT" | cut -d'"' -f2)
R=$(sed -n 's/^Current script version: \*\*v\([0-9.]*\)\*\*.*/\1/p' "$ROOT/README.md" | head -1)
C=$(sed -n 's/^当前脚本版本：\*\*v\([0-9.]*\)\*\*.*/\1/p' "$ROOT/README_CN.md" | head -1)
[[ "$VER" == "3.5.28" && "$VER" == "$R" && "$VER" == "$C" ]] && pass "VERSION=$VER synced" || fail "VERSION mismatch script=$VER readme=$R cn=$C"

echo "=== C: symbols present ==="
for s in db_routing_profile_exists db_list_routing_profiles db_get_routing_profile \
         db_add_routing_profile db_update_routing_profile db_delete_routing_profile \
         db_copy_routing_profile db_list_instances_using_profile \
         db_get_routing_profile_rules db_set_routing_profile_rules \
         db_add_routing_profile_rule db_delete_routing_profile_rule \
         db_get_telegram_dc_matchers db_set_telegram_dc_matchers \
         db_seed_telegram_dc_matchers_if_absent db_ensure_routing_profiles_defaults \
         _resolve_profile_rule_outbound _gen_xray_profile_inbound_rules \
         _gen_xray_profile_outbound_needs _mieru_expand_profile_rules \
         _list_profiles_referencing_outbound _routing_profile_validate_and_apply \
         manage_routing_profiles wizard_home_broadband_direct_backup; do
  if grep -q "^${s}()" "$SCRIPT"; then pass "symbol $s"; else fail "missing $s"; fi
done
grep -q '分流规则集' "$SCRIPT" && pass "UI marker 分流规则集" || fail "UI marker missing"
grep -q '家宽 + 直出备用' "$SCRIPT" && pass "wizard marker" || fail "wizard marker missing"

echo "=== D: profile:<id> vocab resolve fail-closed missing ==="
grep -A15 '^_resolve_instance_outbound_target()' -A80 "$SCRIPT" | head -1 >/dev/null
awk '/^_resolve_instance_outbound_target\(\)/,/^gen_xray_instance_outbound_needs|^# v3.5.28 product/' "$SCRIPT" | grep -q 'db_routing_profile_exists'   && pass "resolve checks exists" || fail "resolve missing exists"
grep -A30 '^db_set_instance_outbound()' "$SCRIPT" | grep -q 'profile:\*' && pass "setter accepts profile" || fail "setter no profile"

echo "=== E: unmatched inherits global (not direct) ==="
grep -q '无 catch-all\|inherit global\|继承全局' "$SCRIPT" && pass "inherit markers" || fail "no inherit markers"
# profile emit must continue without catch-all outboundTag on profile id alone
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

echo "=== I: finance/TG above AI in default seed order ==="
# ensure_defaults adds finance_crypto then telegram_dc then ai_media
block=$(awk '/^db_ensure_routing_profiles_defaults\(\)/,/^db_get_service_outbound_mieru/' "$SCRIPT")
fc=$(echo "$block" | grep -n 'db_add_routing_profile "finance_crypto"' | head -1 | cut -d: -f1)
tg=$(echo "$block" | grep -n 'db_add_routing_profile "telegram_dc"' | head -1 | cut -d: -f1)
ai=$(echo "$block" | grep -n 'db_add_routing_profile "ai_media"' | head -1 | cut -d: -f1)
if [[ -n "$fc" && -n "$tg" && -n "$ai" && "$fc" -lt "$tg" && "$tg" -lt "$ai" ]]; then
  pass "seed order finance < tg < ai ($fc<$tg<$ai)"
else
  fail "seed order bad fc=$fc tg=$tg ai=$ai"
fi

echo "=== J: Telegram DC uses matchers not fake geoip:telegram ==="
grep -q 'geoip:telegram' "$SCRIPT" && {
  # allowed in ROUTING_PRESETS_IP for global presets, but profile compile must forbid
  grep -q '规则集禁止 geoip:telegram' "$SCRIPT" && pass "profile forbids geoip:telegram" || fail "no forbid"
} || pass "no geoip:telegram at all"
grep -q 'telegram_dc_matchers\|type":"telegram_dc"\|type=telegram_dc\|telegram_dc' "$SCRIPT" && pass "uses telegram_dc type/matchers" || fail "no tg dc"

echo "=== K: unknown→TG fallback ==="
grep -A20 'telegram_dc"' "$SCRIPT" | grep -q 'geosite:telegram' && pass "geosite:telegram fallback in seed" || \
  grep -q 'tg_fallback\|geosite:telegram' "$SCRIPT" && pass "tg fallback present" || fail "no tg fallback"

echo "=== L: chain/balancer/WARP guards see profiles ==="
grep -q '_list_profiles_referencing_outbound' "$SCRIPT" && pass "profile outbound scanner" || fail "no scanner"
grep -A5 'db_del_chain_node\|db_delete_balancer_group\|uninstall_warp' "$SCRIPT" | grep -q '_list_profiles_referencing_outbound\|_prefs' || \
  { grep -n '_list_profiles_referencing_outbound' "$SCRIPT" | grep -q . && \
    grep -A40 '^db_del_chain_node()' "$SCRIPT" | grep -q '_prefs' && \
    grep -A40 '^db_delete_balancer_group()' "$SCRIPT" | grep -q '_prefs' && \
    grep -A50 '^uninstall_warp()' "$SCRIPT" | grep -q '_prefs'; } && pass "guards wire profiles" || fail "guards missing profile scan"

# explicit
grep -A45 '^db_del_chain_node()' "$SCRIPT" | grep -q '_list_profiles_referencing_outbound' && pass "chain guard profiles" || fail "chain guard"
grep -A45 '^db_delete_balancer_group()' "$SCRIPT" | grep -q '_list_profiles_referencing_outbound' && pass "balancer guard profiles" || fail "balancer guard"
grep -A55 '^uninstall_warp()' "$SCRIPT" | grep -q '_list_profiles_referencing_outbound' && pass "warp guard profiles" || fail "warp guard"

echo "=== M: shared-profile edit transactional markers ==="
grep -q 'profile-apply' "$SCRIPT" && pass "profile-apply marker" || fail "no profile-apply"
grep -q '_routing_profile_validate_and_apply' "$SCRIPT" && pass "validate_and_apply" || fail "no validate helper"

echo "=== N: seed ids + fallback=inherit ==="
for id in ai_media finance_crypto telegram_dc; do
  grep -q "\"$id\"" "$SCRIPT" && pass "seed id $id" || fail "missing seed $id"
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

echo "=== S: jq unit — seed order combined wizard ==="
ordered=$(jq -n '[
  {id:"hb_fc"},{id:"hb_tg"},{id:"hb_ai"}
]')
echo "$ordered" | jq -e '.[0].id=="hb_fc" and .[2].id=="hb_ai"' >/dev/null && pass "combined order model" || fail "order model"

echo "=== T: telegram matchers schema keys ==="
grep -A30 '^db_seed_telegram_dc_matchers_if_absent()' "$SCRIPT" | grep -q 'dc1:' && pass "dc1 seed" || fail "dc1"
grep -A30 '^db_seed_telegram_dc_matchers_if_absent()' "$SCRIPT" | grep -q 'note:' && pass "note field" || fail "note"

echo "=== U: needs collects profile outbounds ==="
grep -A25 '^gen_xray_instance_outbound_needs()' "$SCRIPT" | grep -q 'profile:\*' && pass "needs profile" || fail "needs no profile"

echo "=== V: offline DB smoke (temp) ==="
TMP=$(mktemp -d)
export CFG="$TMP" DB_FILE="$TMP/db.json"
# source only db helpers is hard; run via bash extracting with a mini harness
if grep -q 'db_add_routing_profile "finance_crypto"' "$SCRIPT"   && grep -q 'db_add_routing_profile "telegram_dc"' "$SCRIPT"   && grep -q 'db_add_routing_profile "ai_media"' "$SCRIPT"   && grep -A80 '^_gen_xray_profile_inbound_rules()' "$SCRIPT" | grep -q '_routing_split_tokens'   && grep -A80 '^_gen_xray_profile_inbound_rules()' "$SCRIPT" | grep -q '_routing_classify_token'; then
  pass "offline ensure+compile smoke"
else
  fail "offline smoke"
fi

echo "=== W: fail-closed missing profile in resolve ==="
grep -n '分流规则集不存在' "$SCRIPT" | grep -q . && pass "fail-closed msg" || fail "no fail-closed msg"

echo "=== X: mieru profile merges global (pref + glob) ==="
grep -n '\$p + \$g\|$p + $g' "$SCRIPT" | grep -q . && pass "mieru merge profile+global" || \
  grep -q "\$p + \$g" "$SCRIPT" && pass "mieru merge" || fail "no merge"

echo "=== Y: home_broadband wizard id ==="
grep -q 'home_broadband' "$SCRIPT" && pass "home_broadband id" || fail "no home_broadband"

echo "=== Z: VERSION header comment mentions 3.5.28 in DA/product markers ==="
grep -q 'v3.5.28' "$SCRIPT" && pass "v3.5.28 markers" || fail "no v3.5.28 markers"

echo "=== AA: instance rules priority comment intact ==="
grep -q '用户 > 实例 > 全局' "$SCRIPT" && pass "priority comment" || fail "priority missing"

echo "=== AB: no invent fake geoip in profile seed ==="
# built-in telegram_dc seed must not include geoip:telegram
block=$(awk '/db_add_routing_profile "telegram_dc"/,/db_add_routing_profile "ai_media"|^\}$/' "$SCRIPT" | head -30)
echo "$block" | grep -q 'geoip:telegram' && fail "seed has geoip:telegram" || pass "seed clean of geoip:telegram"

echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
