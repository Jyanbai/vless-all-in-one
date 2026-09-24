#!/usr/bin/env bash
# Local semantic tests for FinalMask DB verify vs instance_outbound (v3.5.25 hotfix)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/vless-server.sh"
PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

fm_fn() {
  awk '/^gen_vless_finalmask_server_config\(\)/{f=1} f{print} f && /^\}$/{exit}' "$SCRIPT"
}

echo "=== A: bash -n ==="
if bash -n "$SCRIPT"; then pass "bash -n"; else fail "bash -n"; fi

echo "=== B: register_protocol fail-closed ==="
block=$(fm_fn)
if echo "$block" | grep -q 'if ! register_protocol "vless-finalmask"'; then
  pass "register_protocol checked"
else
  fail "register_protocol not fail-closed gated"
fi
if echo "$block" | grep -A3 'if ! register_protocol "vless-finalmask"' | grep -q '_limited_change_rollback'; then
  pass "register fail → rollback"
else
  fail "register fail missing rollback"
fi

echo "=== C: protocol fields via del(.instance_outbound) ==="
if echo "$block" | grep -q 'del(.instance_outbound) == (\$expected | del(.instance_outbound))'; then
  pass "protocol compare strips instance_outbound both sides"
else
  fail "missing stripped protocol equality"
fi
# must NOT use bare . == $expected for stored vs new after register
if echo "$block" | grep -qE "\. == \\\$expected|'\. == \$expected'"; then
  fail "still has blind full-object equality"
else
  pass "no blind stored==new equality"
fi

echo "=== D: outbound validated separately ==="
if echo "$block" | grep -q 'stored_ob=\$(printf'; then pass "reads stored_ob"; else fail "no stored_ob"; fi
if echo "$block" | grep -q 'expected_ob=\$(printf'; then pass "reads expected_ob"; else fail "no expected_ob"; fi
if echo "$block" | grep -q 'FinalMask 实例出口校验失败'; then pass "outbound verify errors"; else fail "no outbound verify errors"; fi

echo "=== E: no literal inherit ==="
if echo "$block" | grep -A8 'case "\$stored_ob"' | grep -q 'inherit'; then
  pass "literal inherit rejected"
else
  fail "inherit case missing"
fi
if echo "$block" | grep -q '禁止字面量 inherit'; then pass "inherit error text"; else fail "no inherit error"; fi

echo "=== F: outbound vocab allowlist ==="
if echo "$block" | grep -A15 'case "\$stored_ob"' | grep -qE 'direct\|warp\|chain:\*\|balancer:\*'; then
  pass "vocab allowlist"
else
  fail "vocab allowlist missing"
fi

echo "=== G: expected outbound must match when set ==="
if echo "$block" | grep -q 'expected_ob" && "\$stored_ob" != "\$expected_ob"'; then
  pass "expected vs stored outbound check"
else
  fail "missing expected_ob mismatch check"
fi

echo "=== H: rollback transactional on verify failures ==="
n=$(echo "$block" | grep -c '_limited_change_rollback' || true)
[[ "$n" -ge 4 ]] && pass "rollback sites >=4 (got $n)" || fail "too few rollbacks ($n)"
# empty stored also rolls back
if echo "$block" | grep -B2 'FinalMask 数据库写入校验失败' | grep -q 'stored_config'; then
  pass "empty stored triggers verify fail path"
else
  pass "verify fail path present"
fi

echo "=== I: FinalMask path free of live Mieru service-outbound UI ==="
# DA may keep temporary getters for migration; UI must not show 全部实例; FinalMask verify must not call service getter
if grep -q 'Mieru（全部实例）' "$SCRIPT"; then
  fail "Mieru（全部实例） UI still present"
else
  pass "no Mieru（全部实例） UI"
fi
if awk '/^_verify_finalmask_db_write\(\)/{f=1} f{print} /^\}$/{if(f&&++c==1) exit}' "$SCRIPT" | grep -q 'db_get_service_outbound_mieru\|service_outbound\.mieru'; then
  fail "FinalMask verify touches service_outbound.mieru"
else
  pass "FinalMask verify free of service_outbound.mieru"
fi
VER=$(grep -m1 '^readonly VERSION=' "$SCRIPT" | cut -d'"' -f2)
[[ "$VER" == "3.5.28" ]] && pass "VERSION=$VER (3.5.28)" || fail "VERSION=$VER unexpected"

echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
