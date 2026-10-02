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
R=$(sed -n 's/^Current script version: \*\*v\([0-9.]*\)\*\*.*/\1/p' "$ROOT/README.md")
R=$(head -1 <<<"$R")
C=$(sed -n 's/^当前脚本版本：\*\*v\([0-9.]*\)\*\*.*/\1/p' "$ROOT/README_CN.md")
C=$(head -1 <<<"$C")
[[ "$VER" == "$R" && "$VER" == "$C" ]] && pass "VERSION=$VER synced" || fail "VERSION mismatch script=$VER readme=$R cn=$C"

echo "=== C: symbols present ==="
for s in _smart_snapshot_config _smart_validate_config _smart_apply_core _smart_apply_selftest _regenerate_proxy_configs; do
  if grep -q "^${s}()" "$SCRIPT"; then pass "symbol $s"; else fail "missing $s"; fi
done

echo "=== D: configure_direct_outbound uses smart regen ==="
ctx=$(grep -A40 '^configure_direct_outbound()' "$SCRIPT")
if grep -q '_regenerate_proxy_configs' <<<"$ctx"; then
  pass "direct_outbound → _regenerate_proxy_configs"
else
  fail "direct_outbound missing smart regen"
fi
ctx=$(grep -A40 '^configure_direct_outbound()' "$SCRIPT")
if grep -qE 'svc stop|generate_xray_config|generate_singbox_config' <<<"$ctx"; then
  fail "direct_outbound still has stop/gen path"
else
  pass "direct_outbound no stop/gen/start"
fi

echo "=== E: core hints accepted ==="
ctx=$(grep -A20 '^_regenerate_proxy_configs()' "$SCRIPT")
grep -q 'xray|singbox|mieru|all' <<<"$ctx" && pass "hints case" || fail "hints missing"
ctx=$(grep -n '_regenerate_proxy_configs xray' "$SCRIPT")
grep -q . <<<"$ctx" && pass "instance_outbound uses xray hint" || fail "no xray hint call"

echo "=== F: rebuild_* use smart apply ==="
ctx=$(grep -A8 '^rebuild_and_reload_xray()' "$SCRIPT")
grep -q '_smart_apply_core' <<<"$ctx" && pass "rebuild xray smart" || fail "rebuild xray"
ctx=$(grep -A8 '^rebuild_and_reload_singbox()' "$SCRIPT")
grep -q '_smart_apply_core' <<<"$ctx" && pass "rebuild singbox smart" || fail "rebuild singbox"

echo "=== G: validate engines referenced ==="
ctx=$(grep -A30 '^_smart_validate_config()' "$SCRIPT")
grep -q 'xray run -test' <<<"$ctx" && pass "xray -test" || fail "xray -test"
ctx=$(grep -A30 '^_smart_validate_config()' "$SCRIPT")
grep -q 'sing-box check' <<<"$ctx" && pass "sing-box check" || fail "sing-box check"
ctx=$(grep -A20 '^_smart_validate_config()' "$SCRIPT")
grep -q '_mieru_validate_candidate\|jq empty' <<<"$ctx" && pass "mieru validate" || fail "mieru validate"

echo "=== H: instrumentation lines ==="
grep -q 'skip_restart:' "$SCRIPT" && pass "skip_restart log" || fail "skip_restart"
grep -q 'validate_fail:' "$SCRIPT" && pass "validate_fail log" || fail "validate_fail"
grep -q 'VLESS_SMART_APPLY' "$SCRIPT" && pass "kill-switch" || fail "kill-switch"

echo "=== I: offline selftest (unchanged/changed/invalid) ==="
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
export VLESS_SMART_XRAY_CALLS="$WORK/xray.calls"
cat > "$WORK/bin/xray" <<'XRAY'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$VLESS_SMART_XRAY_CALLS"
if [[ "${1:-}" == run ]]; then
  shift
fi
[[ "$#" -eq 3 && "$1" == -test && "$2" == -c ]] || exit 1
jq empty "$3" >/dev/null 2>&1
XRAY
chmod +x "$WORK/bin/xray"
PATH="$WORK/bin:$PATH"
export PATH
if bash "$SCRIPT" --smart-apply-selftest; then
  pass "selftest"
else
  fail "selftest"
fi
if grep -q -- '-test' "$VLESS_SMART_XRAY_CALLS"; then
  pass "selftest xray validation path"
else
  fail "selftest xray validation path not executed"
fi

echo "=== J: diff proves skip-restart path exists ==="
ctx=$(grep -A80 '^_smart_apply_core()' "$SCRIPT")
if grep -q 'cmp -s' <<<"$ctx"; then pass "cmp diff gate"; else fail "no cmp"; fi

echo "=== K: snap restore fail-closed (no false skip_restart) ==="
ctx=$(grep -A12 'fail-closed: snap' "$SCRIPT")
if grep -q 'restore_fail' <<<"$ctx"; then pass "restore_fail on snap cp fail"
else fail "missing restore_fail abort after snap restore failure"; fi
ctx=$(grep -A12 'fail-closed: snap' "$SCRIPT")
if grep -q 'return 1' <<<"$ctx"; then pass "snap restore failure returns 1"
else fail "snap restore failure does not return 1"; fi
ctx=$(awk '/fail-closed: snap/{f=1} f{print} /_smart_validate_config/{if(f){exit}}' "$SCRIPT")
if grep -q '|| true' <<<"$ctx"; then
  fail "critical snap restore still has || true"
else
  pass "critical snap restore has no || true"
fi

echo "=== smart-cand .json suffix (xray -test format) ==="
ctx=$(grep -n 'vless-smart-cand.XXXXXX.json' "$SCRIPT")
grep -q . <<<"$ctx" && pass "smart-cand .json" || fail "smart-cand missing .json suffix"

echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
