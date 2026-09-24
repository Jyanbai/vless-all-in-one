#!/usr/bin/env bash
# Local semantic tests for smart-apply (v3.5.25)
# Hook: ./vless-server.sh --smart-apply-selftest  (VLESS_COUNT_REGEN stubs, no systemd)
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
for s in _smart_snapshot_config _smart_validate_config _smart_apply_core _smart_apply_selftest _regenerate_proxy_configs; do
  if grep -q "^${s}()" "$SCRIPT"; then pass "symbol $s"; else fail "missing $s"; fi
done

echo "=== D: configure_direct_outbound uses smart regen ==="
if grep -A40 '^configure_direct_outbound()' "$SCRIPT" | grep -q '_regenerate_proxy_configs'; then
  pass "direct_outbound → _regenerate_proxy_configs"
else
  fail "direct_outbound missing smart regen"
fi
if grep -A40 '^configure_direct_outbound()' "$SCRIPT" | grep -qE 'svc stop|generate_xray_config|generate_singbox_config'; then
  fail "direct_outbound still has stop/gen path"
else
  pass "direct_outbound no stop/gen/start"
fi

echo "=== E: core hints accepted ==="
grep -A20 '^_regenerate_proxy_configs()' "$SCRIPT" | grep -q 'xray|singbox|mieru|all' && pass "hints case" || fail "hints missing"
grep -n '_regenerate_proxy_configs xray' "$SCRIPT" | grep -q . && pass "instance_outbound uses xray hint" || fail "no xray hint call"

echo "=== F: rebuild_* use smart apply ==="
grep -A8 '^rebuild_and_reload_xray()' "$SCRIPT" | grep -q '_smart_apply_core' && pass "rebuild xray smart" || fail "rebuild xray"
grep -A8 '^rebuild_and_reload_singbox()' "$SCRIPT" | grep -q '_smart_apply_core' && pass "rebuild singbox smart" || fail "rebuild singbox"

echo "=== G: validate engines referenced ==="
grep -A30 '^_smart_validate_config()' "$SCRIPT" | grep -q 'xray run -test' && pass "xray -test" || fail "xray -test"
grep -A30 '^_smart_validate_config()' "$SCRIPT" | grep -q 'sing-box check' && pass "sing-box check" || fail "sing-box check"
grep -A20 '^_smart_validate_config()' "$SCRIPT" | grep -q '_mieru_validate_candidate\|jq empty' && pass "mieru validate" || fail "mieru validate"

echo "=== H: instrumentation lines ==="
grep -q 'skip_restart:' "$SCRIPT" && pass "skip_restart log" || fail "skip_restart"
grep -q 'validate_fail:' "$SCRIPT" && pass "validate_fail log" || fail "validate_fail"
grep -q 'VLESS_SMART_APPLY' "$SCRIPT" && pass "kill-switch" || fail "kill-switch"

echo "=== I: offline selftest (unchanged/changed/invalid) ==="
if bash "$SCRIPT" --smart-apply-selftest; then pass "selftest"; else fail "selftest"; fi

echo "=== J: diff proves skip-restart path exists ==="
if grep -A80 '^_smart_apply_core()' "$SCRIPT" | grep -q 'cmp -s'; then pass "cmp diff gate"; else fail "no cmp"; fi

echo "=== K: snap restore fail-closed (no false skip_restart) ==="
if grep -A12 'fail-closed: snap' "$SCRIPT" | grep -q 'restore_fail'; then pass "restore_fail on snap cp fail"
else fail "missing restore_fail abort after snap restore failure"; fi
if grep -A12 'fail-closed: snap' "$SCRIPT" | grep -q 'return 1'; then pass "snap restore failure returns 1"
else fail "snap restore failure does not return 1"; fi
if awk '/fail-closed: snap/{f=1} f{print} /_smart_validate_config/{if(f){exit}}' "$SCRIPT" | grep -q '|| true'; then
  fail "critical snap restore still has || true"
else
  pass "critical snap restore has no || true"
fi

echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
