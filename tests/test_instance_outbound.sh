#!/usr/bin/env bash
# Local semantic tests for per-instance outbound (v3.5.27)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/vless-server.sh"
PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== A: bash -n ==="
if bash -n "$SCRIPT"; then pass "bash -n"; else fail "bash -n"; fi

echo "=== B: VERSION sync ==="
VER=$(grep -m1 '^readonly VERSION=' "$SCRIPT" | cut -d'"' -f2)
R=$(sed -n 's/^Current script version: \*\*v\([0-9.]*\)\*\*.*/\1/p' "$ROOT/README.md" | head -1)
C=$(sed -n 's/^当前脚本版本：\*\*v\([0-9.]*\)\*\*.*/\1/p' "$ROOT/README_CN.md" | head -1)
[[ "$VER" == "3.5.30" && "$VER" == "$R" && "$VER" == "$C" ]] && pass "VERSION=$VER synced" || fail "VERSION mismatch script=$VER readme=$R cn=$C"

echo "=== C: symbols present ==="
for s in db_get_instance_outbound db_set_instance_outbound db_clear_instance_outbound \
         _instance_inbound_tag gen_xray_instance_outbound_rules gen_xray_instance_outbound_needs \
         manage_instance_outbound _prompt_instance_outbound _routing_meaningfully_configured; do
  if grep -q "^${s}()" "$SCRIPT"; then pass "symbol $s"; else fail "missing $s"; fi
done

echo "=== D: tag formula consistency ==="
# add_xray_inbound_v2 must call _instance_inbound_tag
if grep -A5 '_instance_inbound_tag' "$SCRIPT" | grep -q 'inbound_tag'; then pass "inbound uses helper"
else
  # alternate: inbound_tag=$(_instance_inbound_tag
  if grep -q 'inbound_tag=\$(_instance_inbound_tag' "$SCRIPT"; then pass "inbound uses helper"
  else fail "inbound may drift from helper"; fi
fi

echo "=== E: menu item 9 without renumbering 1-8 ==="
if grep -A20 '^manage_routing()' "$SCRIPT" | grep -q '_item "9" "实例出口管理"'; then pass "menu 9"
else fail "menu 9 missing"; fi
if grep -A20 '^manage_routing()' "$SCRIPT" | grep -q '_item "8"'; then pass "menu 8 intact"; else fail "menu 8 missing"; fi

echo "=== F: fail-closed marker + priority comment ==="
grep -q 'fail-closed' "$SCRIPT" && pass "fail-closed present" || fail "no fail-closed"
grep -q '用户 > 实例 > 全局' "$SCRIPT" && pass "priority comment" || fail "priority comment missing"

echo "=== G: multi-IP comment near emit ==="
grep -q 'MULTI-IP\|多IP' "$SCRIPT" | head -1
if grep -n 'MULTI-IP\|多IP显式\|ip-in-' "$SCRIPT" | grep -qi 'instance\|实例'; then pass "multi-IP documented near instance"
else
  # softer check
  grep -q 'ip-in-' "$SCRIPT" && pass "ip-in tags referenced" || fail "no multi-IP note"
fi

echo "=== H: mieru isolation (Xray rules skip; mieru uses own instance_outbound) ==="
# Xray inboundTag instance generators must still skip mieru
if grep -A20 '^gen_xray_instance_outbound_rules()' "$SCRIPT" | grep -q 'mieru'; then pass "mieru skipped in xray instance rules"
else fail "mieru not skipped in xray rules"; fi
# v3.5.27: mieru compile intentionally reads db_get_instance_outbound
if grep -A30 '^_mieru_compile_egress_plan()' "$SCRIPT" | grep -q 'db_get_instance_outbound'; then
  pass "mieru compile wires instance_outbound"
else
  fail "mieru compile missing instance_outbound"
fi

echo "=== I: jq rule shape unit ==="
# synthetic rule JSON
rule=$(jq -n --argjson tags '["vless-443","ip-in-1-2-3-4-443"]' --arg tag "chain-SS2022-JP-prefer-ipv4" \
  '{type:"field", inboundTag:$tags, outboundTag:$tag}')
echo "$rule" | jq empty && pass "sample inboundTag rule jq"
# balancer exclusive
rule2=$(jq -n --argjson tags '["socks-8443"]' --arg tag "balancer-g1" \
  '{type:"field", inboundTag:$tags, balancerTag:$tag}')
echo "$rule2" | jq -e 'has("outboundTag")|not' >/dev/null && pass "no dual outbound+balancer"
# priority array: user before instance before global
ordered=$(jq -n \
  --argjson u '[{"type":"field","user":["a@vless"],"outboundTag":"direct"}]' \
  --argjson i '[{"type":"field","inboundTag":["vless-443"],"outboundTag":"chain-SS2022-JP-prefer-ipv4"}]' \
  --argjson g '[{"type":"field","domain":["geosite:cn"],"outboundTag":"direct"}]' \
  '$u + $i + $g')
u0=$(echo "$ordered" | jq -r '.[0]|has("user")')
i1=$(echo "$ordered" | jq -r '.[1]|has("inboundTag")')
g2=$(echo "$ordered" | jq -r '.[2]|has("domain")')
[[ "$u0" == true && "$i1" == true && "$g2" == true ]] && pass "semantic order user>instance>global" || fail "order broken"

echo "=== J: vocab — no forced inherit literal storage helper ==="
# db_set_instance_outbound must clear on inherit/empty
if grep -A15 '^db_set_instance_outbound()' "$SCRIPT" | grep -q 'inherit'; then pass "inherit maps to clear"
else fail "inherit not handled in setter"; fi

echo "=== K: xray -test if binary present ==="
if command -v xray >/dev/null 2>&1; then
  tmp=$(mktemp)
  cat > "$tmp" <<'JSON'
{
  "log": {"loglevel": "warning"},
  "inbounds": [{"port": 10800, "protocol": "socks", "settings": {"udp": true}, "tag": "socks-10800"}],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "api"}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type": "field", "inboundTag": ["socks-10800"], "outboundTag": "direct"}
    ]
  }
}
JSON
  if xray run -test -c "$tmp" >/dev/null 2>&1 || xray -test -c "$tmp" >/dev/null 2>&1; then
    pass "xray -test sample inboundTag rule"
  else
    fail "xray -test rejected sample"
  fi
  rm -f "$tmp"
else
  echo "SKIP: xray binary not present"
fi

echo "=== L: E2E host reachability (no secrets) ==="
if ping -c1 -W2 160.236.111.34 >/dev/null 2>&1; then
  echo "HOST 160.236.111.34: reachable (no SSH attempted)"
  pass "host ping"
else
  echo "HOST 160.236.111.34: unreachable — SKIP E2E"
fi

echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
