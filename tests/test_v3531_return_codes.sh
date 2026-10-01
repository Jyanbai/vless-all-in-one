#!/usr/bin/env bash
# v3.5.31 regression tests: return codes, scoped cleanup, exact node counts.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/vless-server.sh"
PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
command -v jq >/dev/null || { echo "jq required"; exit 1; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
H="$WORK/harness.sh"; BIN="$WORK/bin"
mkdir -p "$BIN" "$WORK/cfg/cloudflared"
export VLESS_TEST_CALLS="$WORK/calls" VLESS_TEST_CLOUD_CALLS="$WORK/cloud-calls"
export VLESS_TEST_CFG="$WORK/cfg"
export VLESS_TEST_STATS_TMP="$WORK/stats.tmp"
for cmd in apt apt-get apk systemctl curl wget; do
  cat > "$BIN/$cmd" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${0##*/} $*" >> "$VLESS_TEST_CALLS"
exit 1
STUB
done
cat > "$BIN/uname" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' riscv64
STUB
cat > "$BIN/cloudflared" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$VLESS_TEST_CLOUD_CALLS"
case "$*" in
  'tunnel list')
    echo 'ID NAME CREATED CONNECTIONS'
    echo 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee demo 2026-01-01 00:00:00 0'
    ;;
  'tunnel cleanup demo') exit 0 ;;
  'tunnel delete demo')
    echo 'deleted success text from stdout'
    echo 'mock deletion diagnostic from stderr' >&2
    exit "${CLOUDFLARED_STUB_RC:-1}"
    ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"

{
  cat <<'HARNESS'
CFG="$VLESS_TEST_CFG"; DB_FILE="$CFG/db.json"
CLOUDFLARED_BIN=cloudflared; CLOUDFLARED_EDGE_OPTS=''
CLOUDFLARED_DIR="$CFG/cloudflared"; CLOUDFLARED_CONFIG="$CLOUDFLARED_DIR/config.yml"
DISTRO=alpine; XRAY_PROTOCOLS=vless; SINGBOX_PROTOCOLS=''; STANDALONE_PROTOCOLS=''
R=''; G=''; Y=''; C=''; W=''; D=''; NC=''
_ok(){ :; }; _info(){ :; }; _err(){ echo "ERR: $*" >&2; }
_header(){ :; }; _line(){ :; }; _pause(){ :; }
_is_cloudflared_installed(){ return 0; }
_get_tunnel_name(){ echo demo; }; _stop_tunnel_service(){ :; }
svc(){ return 1; }; is_paused(){ return 1; }
warp_status(){ echo unavailable; }; access_restriction_enabled(){ return 1; }
get_protocol_name(){ echo "$1"; }
_ensure_singbox_default_users(){ :; }; _pgrep(){ return 1; }
_install_binary(){ curl mock-download; wget mock-download; return 0; }
HARNESS
  awk '
    /^(_map_arch|install_xray|install_singbox|install_shadowtls|_cloudflared_delete_tunnel_and_cleanup|delete_tunnel|show_status|get_all_traffic_stats)\(\) *\{/ { want=1 }
    want { print }
    want && /^\}$/ { want=0 }
  ' "$SCRIPT"
} > "$H"
run() { bash -c 'source "$1"; shift; "$@"' _ "$H" "$@"; }

echo "=== A: unsupported architecture fails before package/download commands ==="
for fn in install_xray install_singbox install_shadowtls; do
  : > "$VLESS_TEST_CALLS"
  out=$(run "$fn" 2>&1); rc=$?
  [[ $rc -eq 1 ]] && pass "$fn returns 1 on riscv64" || fail "$fn rc=$rc out=$out"
  [[ ! -s "$VLESS_TEST_CALLS" ]] && pass "$fn no package/download calls" || fail "$fn calls: $(cat "$VLESS_TEST_CALLS")"
done

make_credentials() {
  printf '%s\n' tunnel_name=demo > "$WORK/cfg/cloudflared/tunnel.info"
  printf '%s\n' tunnel:demo > "$WORK/cfg/cloudflared/config.yml"
  printf '%s\n' '{"mock":true}' > "$WORK/cfg/cloudflared/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.json"
  printf '%s\n' '{"other":true}' > "$WORK/cfg/cloudflared/other.json"
}
credentials_present() {
  [[ -f "$WORK/cfg/cloudflared/tunnel.info" && -f "$WORK/cfg/cloudflared/config.yml" &&
     -f "$WORK/cfg/cloudflared/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.json" ]]
}
credentials_absent() {
  [[ ! -e "$WORK/cfg/cloudflared/tunnel.info" && ! -e "$WORK/cfg/cloudflared/config.yml" &&
     ! -e "$WORK/cfg/cloudflared/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.json" ]]
}

echo "=== B: tunnel deletion follows exit code, including misleading success text ==="
make_credentials; : > "$VLESS_TEST_CLOUD_CALLS"
before=$(sha256sum "$WORK/cfg/cloudflared/"*)
export CLOUDFLARED_STUB_RC=1
out=$(run _cloudflared_delete_tunnel_and_cleanup demo aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee demo 2>&1); rc=$?
[[ $rc -eq 1 ]] && pass "delete failure returns 1" || fail "delete failure rc=$rc"
credentials_present && [[ "$(sha256sum "$WORK/cfg/cloudflared/"*)" == "$before" ]] && pass "failure preserves credentials byte-for-byte" || fail "failure changed credentials"
[[ "$out" == *'deleted success text from stdout'* && "$out" == *'mock deletion diagnostic from stderr'* ]] && pass "failure prints stdout and stderr" || fail "missing diagnostic: $out"
grep -qx 'tunnel delete demo' "$VLESS_TEST_CLOUD_CALLS" && pass "real delete command reaches stub" || fail "delete command missing"

export CLOUDFLARED_STUB_RC=0
run _cloudflared_delete_tunnel_and_cleanup demo aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee another >/dev/null 2>&1
rc=$?
[[ $rc -eq 0 ]] && credentials_present && pass "non-local success preserves local credentials" || fail "non-local success changed local files"
run _cloudflared_delete_tunnel_and_cleanup demo aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee demo >/dev/null 2>&1
rc=$?
[[ $rc -eq 0 ]] && credentials_absent && pass "local success removes credentials" || fail "local success rc=$rc or files remain"
[[ -f "$WORK/cfg/cloudflared/other.json" ]] && pass "unrelated credentials kept" || fail "unrelated credentials removed"

echo "=== C: interactive deletion delegates to the tested helper ==="
make_credentials; export CLOUDFLARED_STUB_RC=1
out=$(run delete_tunnel <<< $'1\ny' 2>&1)
credentials_present && [[ "$out" == *'mock deletion diagnostic from stderr'* ]] && pass "UI failure retains credentials and prints error" || fail "UI failure handling"
export CLOUDFLARED_STUB_RC=0
run delete_tunnel <<< $'1\ny' >/dev/null 2>&1
credentials_absent && pass "UI success removes credentials" || fail "UI success cleanup"

echo "=== D: exact node names and unchanged status text ==="
printf '%s\n' '{"xray":{"vless":[{"port":443}]},"routing_rules":[{"outbound":"chain:hk2"},{"outbound":"chain:hk"},{"outbound":"chain:hk2"}]}' > "$WORK/cfg/db.json"
out=$(run show_status 2>&1); rc=$?
[[ $rc -eq 0 && "$out" == *'  分流: 3条规则→2个节点'* ]] && pass "hk2 + hk + hk2 count as 2 nodes" || fail "node count rc=$rc out=$out"
printf '%s\n' '{"xray":{"vless":[{"port":443}]},"routing_rules":[{"outbound":"chain:hk"},{"outbound":"chain:hk"},{"outbound":"warp"},{"outbound":"block"}]}' > "$WORK/cfg/db.json"
out=$(run show_status 2>&1)
[[ "$out" == *'  分流: 4条规则→hk,WARP,屏蔽'* ]] && pass "single node and WARP/block format preserved" || fail "single node display: $out"

echo "=== E: RETURN cleanup does not leak to the caller ==="
out=$(bash -c 'source "$1"
  mktemp(){ : > "$VLESS_TEST_STATS_TMP"; echo "$VLESS_TEST_STATS_TMP"; }
  get_all_traffic_stats >/dev/null || exit 1
  [[ ! -e "$VLESS_TEST_STATS_TMP" ]] || exit 2
  [[ -z "$(trap -p RETURN)" ]] || exit 3
  printf keep > "$VLESS_TEST_STATS_TMP"
  unrelated(){ :; }; unrelated
  [[ -f "$VLESS_TEST_STATS_TMP" ]]
' _ "$H" 2>&1); rc=$?
[[ $rc -eq 0 ]] && pass "temporary file cleaned and RETURN trap cleared" || fail "RETURN cleanup rc=$rc out=$out"

echo "=== F: no local declarations masking checked return codes ==="
out=$(grep -nE '^\s*local [A-Za-z_][A-Za-z0-9_]*=\$\(.*\)\s*\|\|' "$SCRIPT"); rc=$?
[[ $rc -eq 1 && -z "$out" ]] && pass "no local assignment followed by ||" || fail "local || check rc=$rc: $out"
out=$(awk 'p ~ /^[[:space:]]*local [A-Za-z_]+=\$\(/ && $0 ~ /\$\?/ {print NR-1} {p=$0}' "$SCRIPT"); rc=$?
[[ $rc -eq 0 && -z "$out" ]] && pass "no local assignment before status capture" || fail "local status check rc=$rc: $out"

echo "=== G: unreachable AnyTLS installer removed; legacy uninstall hint kept ==="
install_case=$(awk '
  /^do_install_server\(\)/ { in_fn=1 }
  in_fn && /^    # 根据协议安装对应软件/ { want=1 }
  want { print }
  want && /^    esac/ { exit }
' "$SCRIPT")
if [[ -n "$install_case" ]] && ! grep -qE '^[[:space:]]*anytls\)' <<< "$install_case"; then
  pass "no standalone AnyTLS install branch"
else
  fail "standalone AnyTLS install branch or missing installation case"
fi
grep -q 'hy2|tuic|anytls)' <<< "$install_case" && pass "AnyTLS still installs via Sing-box" || fail "shared AnyTLS branch missing"
grep -qE '^install_anytls\(\)' "$SCRIPT" && fail "install_anytls still defined" || pass "install_anytls not defined"
grep -q 'install_anytls' "$SCRIPT" && fail "install_anytls reference remains" || pass "no remaining install_anytls callers"
grep -qF 'anytls-*' "$SCRIPT" && pass "legacy anytls-* uninstall hint kept" || fail "legacy uninstall hint removed"

[[ ! -s "$VLESS_TEST_CALLS" ]] && pass "no forbidden external commands called" || fail "forbidden calls: $(cat "$VLESS_TEST_CALLS")"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
