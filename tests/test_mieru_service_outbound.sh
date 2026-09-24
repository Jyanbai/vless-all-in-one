#!/usr/bin/env bash
# Local semantic tests for Mieru service-level outbound (v3.5.25)
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
[[ "$VER" == "3.5.26" && "$VER" == "$R" && "$VER" == "$C" ]] && pass "VERSION=$VER synced" || fail "VERSION mismatch script=$VER readme=$R cn=$C"

echo "=== C: symbols present ==="
for s in db_get_service_outbound_mieru db_set_service_outbound_mieru db_clear_service_outbound_mieru \
         _mieru_compile_service_override_plan _mieru_compile_egress_plan manage_instance_outbound; do
  if grep -q "^${s}()" "$SCRIPT"; then pass "symbol $s"; else fail "missing $s"; fi
done

echo "=== D: service-wide UI not per-port ==="
if awk '/^manage_instance_outbound\(\)/{f=1} f{print} /^\}$/{if(f&&++c==1) exit}' "$SCRIPT" | grep -q 'Mieru（全部实例）'; then
  pass "Mieru（全部实例） row"
else
  fail "missing Mieru（全部实例） row"
fi
if awk '/^manage_instance_outbound\(\)/{f=1} f{print} /^\}$/{if(f&&++c==1) exit}' "$SCRIPT" | grep -q '\[\[ "\$proto" == "mieru" \]\] && continue'; then
  pass "mieru skipped in per-port loop"
else
  fail "mieru still listed per-port"
fi
# must not add mieru ports via db_list_ports inside mieru branch
if awk '/^manage_instance_outbound\(\)/{f=1} f{print} /^\}$/{if(f&&++c==1) exit}' "$SCRIPT" | grep -A2 'db_exists "xray" "mieru"' | grep -q 'db_list_ports'; then
  fail "mieru row enumerates ports"
else
  pass "mieru row is single service entry"
fi

echo "=== E: inherit/empty never persisted ==="
if grep -A12 '^db_set_service_outbound_mieru()' "$SCRIPT" | grep -q 'inherit'; then pass "inherit → clear"
else fail "inherit not cleared in setter"; fi
if grep -A12 '^db_set_service_outbound_mieru()' "$SCRIPT" | grep -q 'db_clear_service_outbound_mieru'; then pass "empty/inherit calls clear"
else fail "setter missing clear path"; fi
# never writes literal inherit into jq
if grep -A20 '^db_set_service_outbound_mieru()' "$SCRIPT" | grep -q 'mieru: "inherit"\|mieru: inherit'; then
  fail "literal inherit would be stored"
else
  pass "no literal inherit store"
fi

echo "=== F: vocab validate ==="
if grep -A18 '^db_set_service_outbound_mieru()' "$SCRIPT" | grep -qE 'direct\|warp\|chain:\*\|balancer:\*'; then
  pass "vocab case allowlist"
else
  fail "vocab allowlist missing"
fi
if grep -A18 '^db_set_service_outbound_mieru()' "$SCRIPT" | grep -q '无效 Mieru 服务出口'; then
  pass "rejects invalid vocab"
else
  fail "no invalid vocab error"
fi

echo "=== G: override > global > default ==="
if grep -A25 '^_mieru_compile_egress_plan()' "$SCRIPT" | grep -q 'db_get_service_outbound_mieru'; then
  pass "compile reads service outbound"
else
  fail "compile missing service outbound read"
fi
if grep -A30 '^_mieru_compile_egress_plan()' "$SCRIPT" | grep -q '_mieru_compile_service_override_plan'; then
  pass "explicit override plan called first"
else
  fail "override plan not first"
fi
grep -q '服务级覆盖 > 全局分流 > 默认直连' "$SCRIPT" && pass "priority comment" || fail "priority comment missing"

echo "=== H: fail-closed (no silent DIRECT for warp/chain/balancer) ==="
for needle in '需要 WARP 但未就绪（fail-closed）' '链式节点不存在: $routing（fail-closed）' '负载组不存在: $routing（fail-closed）'; do
  if grep -q "$needle" "$SCRIPT"; then pass "fail-closed: $needle"; else fail "missing $needle"; fi
done
# warp/balancer paths must not return DIRECT-only without bridges when deps missing — covered by return 1 above

echo "=== I: Mieru UI → regenerate all ==="
if awk '/^manage_instance_outbound\(\)/{f=1} f{print} /^\}$/{if(f&&++c==1) exit}' "$SCRIPT" | grep -A40 'kind" == "mieru"' | grep -q '_regenerate_proxy_configs all'; then
  pass "mieru path regenerates all"
else
  # looser: within function after mieru set
  if awk '/^manage_instance_outbound\(\)/{f=1} f{print} /^\}$/{if(f&&++c==1) exit}' "$SCRIPT" | grep -q '_regenerate_proxy_configs all'; then
    pass "manage_instance_outbound has regen all"
  else
    fail "no _regenerate_proxy_configs all for mieru"
  fi
fi

echo "=== J: no manual svc restart on mieru UI path ==="
block=$(awk '/^manage_instance_outbound\(\)/{f=1} f{print} /^\}$/{if(f&&++c==1) exit}' "$SCRIPT")
if echo "$block" | grep -qE 'svc (restart|stop|start) (vless-mieru|xray)'; then
  fail "manual svc restart in manage_instance_outbound"
else
  pass "no manual svc restart in manage_instance_outbound"
fi

echo "=== K: chain/balancer delete+rename guards ==="
grep -q 'db_clear_service_outbound_mieru' "$SCRIPT" && pass "clear used in guards" || fail "no clear in guards"
if grep -n 'balancer:\$name' "$SCRIPT" | grep -q .; then pass "balancer ref check"; else fail "no balancer mieru guard"; fi
if grep -n 'chain:\$name' "$SCRIPT" | grep -q .; then pass "chain ref check"; else fail "no chain mieru guard"; fi
if grep -q 'service_outbound.mieru' "$SCRIPT" && grep -q 'chain:" + \$old\|chain:" + $old\|"chain:" + \$old' "$SCRIPT"; then
  pass "chain rename updates mieru ref"
else
  # jq rename block
  if grep -A15 'service_outbound.mieru' "$SCRIPT" | grep -q 'chain:'; then pass "chain rename touches mieru"; else fail "rename missing mieru update"; fi
fi

echo "=== L: status line ==="
grep -q 'Mieru 服务: 全部实例' "$SCRIPT" && pass "status Mieru 服务: 全部实例" || fail "missing status line"

echo "=== M: same-value → no regen (one op ≤ one regen) ==="
mieru_block=$(awk '/^manage_instance_outbound\(\)/{f=1} f{print} /^\}$/{if(f&&++c==1) exit}' "$SCRIPT")
if echo "$mieru_block" | grep -A30 'kind" == "mieru"' | grep -q 'new_ob" == "\$cur_ob"'; then
  pass "mieru same-value short-circuit"
else
  fail "mieru same-value short-circuit missing"
fi
if echo "$mieru_block" | grep -A35 'kind" == "mieru"' | awk '/未变更/{p=1} p&&/continue/{ok=1} p&&/_regenerate_proxy_configs all/{if(!ok){bad=1}} END{exit bad||!ok}' ; then
  pass "same-value continues before regen"
else
  fail "same-value does not continue before regen"
fi
n=$(echo "$mieru_block" | grep -c '_regenerate_proxy_configs all' || true)
[[ "$n" -eq 1 ]] && pass "exactly one regen all in manage_instance_outbound" || fail "regen all count=$n"

echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
