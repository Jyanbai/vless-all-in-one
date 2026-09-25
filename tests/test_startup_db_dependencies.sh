#!/usr/bin/env bash
# v3.5.30 startup DB dependency tests (cases A-F).
# Package managers are MOCKED: PATH is restricted to a stub dir containing fake
# apt-get/apk/yum/dnf (and optionally a fake jq). Real apt/apk are never reachable.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/vless-server.sh"
PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
command -v jq >/dev/null || { echo "jq required"; exit 1; }
REAL_JQ=$(command -v jq)
MSG='缺少数据库依赖 jq，自动安装失败。请安装 jq 后重新运行脚本。'

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
H="$WORK/h.sh"; CFGD="$WORK/cfg"; BIN="$WORK/bin"; CALLS="$WORK/calls"
CASEL=$(grep -n '^case "\${1:-}" in' "$SCRIPT" | tail -1 | cut -d: -f1)
head -n $((CASEL-1)) "$SCRIPT" \
  | sed -e 's|^readonly CFG="/etc/vless-reality"|readonly CFG="${VLESS_TEST_CFG:?}"|' > "$H"

# mk_bin <mode>: mode = ok (installer drops a jq shim) | fail (installer exits 1) | noop (exit 0, no jq)
mk_bin() {
  rm -rf "$BIN"; mkdir -p "$BIN"; : > "$CALLS"
  local pm
  for pm in apt-get apk yum dnf; do
    cat > "$BIN/$pm" <<PM
#!$BASH
echo "$pm \$*" >> "$CALLS"
case "\$*" in *install*jq*|*add*jq*)
  case "$1" in
    ok)   printf '#!%s\nexec %s "\$@"\n' "$BASH" "$REAL_JQ" > "$BIN/jq"; /bin/chmod +x "$BIN/jq" ;;
    fail) exit 1 ;;
  esac ;;
esac
exit 0
PM
    /bin/chmod +x "$BIN/$pm"
  done
}
with_jq() { printf '#!%s\nexec %s "$@"\n' "$BASH" "$REAL_JQ" > "$BIN/jq"; /bin/chmod +x "$BIN/jq"; }
only() { local k; for k in "$BIN"/*; do case "$(basename "$k")" in jq|"$@") ;; *) rm -f "$k" ;; esac; done; }
# ens DISTRO: source real script, then restrict PATH to stubs and call ensure_startup_db_dependencies
ens() {
  rm -rf "$CFGD"; mkdir -p "$CFGD"
  VLESS_TEST_CFG="$CFGD" bash -c "source '$H'; DISTRO='$1'; PATH='$BIN'; hash -r; ensure_startup_db_dependencies" 2>&1
}

echo "=== A: jq present -> no install attempted ==="
mk_bin ok; with_jq
out=$(ens debian); rc=$?
[[ $rc -eq 0 ]] && pass "A rc0" || fail "A rc=$rc"
[[ ! -s "$CALLS" ]] && pass "A no package manager invoked" || fail "A calls: $(tr '\n' ';' < "$CALLS")"

echo "=== B: jq absent, debian -> apt-get update + install jq, then verified ==="
mk_bin ok
out=$(ens debian); rc=$?
[[ $rc -eq 0 ]] && pass "B rc0" || fail "B rc=$rc out=$out"
grep -qx 'apt-get update' "$CALLS" && grep -qx 'apt-get install -y jq' "$CALLS" && pass "B apt-get update + install -y jq" || fail "B calls: $(tr '\n' ';' < "$CALLS")"
grep -qE '^(apk|yum|dnf) ' "$CALLS" && fail "B other PMs touched" || pass "B only apt-get used"
[[ -x "$BIN/jq" ]] && echo "$out" | grep -q 'jq 已安装' && pass "B verified after install" || fail "B not verified"
echo "$out" | grep -q "$MSG" && fail "B failure msg on success" || pass "B no failure msg"

echo "=== C: apk / dnf / yum / unknown-distro paths ==="
mk_bin ok; out=$(ens alpine); rc=$?
[[ $rc -eq 0 ]] && grep -qx 'apk add --no-cache jq' "$CALLS" && ! grep -q '^apt-get' "$CALLS" && pass "C alpine -> apk add --no-cache jq" || fail "C alpine rc=$rc calls=$(tr '\n' ';' < "$CALLS")"
mk_bin ok; out=$(ens centos); rc=$?
[[ $rc -eq 0 ]] && grep -qx 'dnf install -y jq' "$CALLS" && ! grep -q '^yum' "$CALLS" && pass "C centos+dnf -> dnf install" || fail "C centos dnf calls=$(tr '\n' ';' < "$CALLS")"
mk_bin ok; only yum; out=$(ens centos); rc=$?
[[ $rc -eq 0 ]] && grep -qx 'yum install -y jq' "$CALLS" && pass "C centos no dnf -> yum install" || fail "C centos yum calls=$(tr '\n' ';' < "$CALLS")"
mk_bin ok; only apk; out=$(ens unknown); rc=$?
[[ $rc -eq 0 ]] && grep -qx 'apk add --no-cache jq' "$CALLS" && pass "C unknown distro falls back to available PM" || fail "C unknown calls=$(tr '\n' ';' < "$CALLS")"

echo "=== D: install fails -> exact message, non-zero, no migration error ==="
mk_bin fail; out=$(ens debian); rc=$?
[[ $rc -ne 0 ]] && pass "D ensure rc!=0" || fail "D ensure rc0"
echo "$out" | grep -qF "$MSG" && pass "D exact error message" || fail "D msg: $out"
mk_bin noop; out=$(ens debian); rc=$?
[[ $rc -ne 0 ]] && echo "$out" | grep -qF "$MSG" && pass "D installer rc0 but no jq -> still fails (verify-after)" || fail "D noop rc=$rc"
# Full main_menu with failing installer: must exit non-zero before init_db/migrations
mk_bin fail; rm -rf "$CFGD"; mkdir -p "$CFGD"
out=$(VLESS_TEST_CFG="$CFGD" bash -c "source '$H'; DISTRO=debian
  check_root(){ :; }; init_log(){ :; }
  init_db(){ echo INIT_DB_CALLED; }
  PATH='$BIN'; hash -r; main_menu" </dev/null 2>&1); rc=$?
[[ $rc -ne 0 ]] && pass "D main_menu exits non-zero" || fail "D main_menu rc0"
echo "$out" | grep -qF "$MSG" && pass "D main_menu prints exact message" || fail "D main_menu msg: $out"
echo "$out" | grep -q '分流规则集迁移失败' && fail "D migration error text shown" || pass "D no 分流规则集迁移失败"
echo "$out" | grep -q 'INIT_DB_CALLED' && fail "D init_db ran without jq" || pass "D init_db not reached"
[[ ! -e "$CFGD/db.json" ]] && pass "D no db.json written" || fail "D db.json created"

echo "=== E: order check_root -> init_log -> ensure -> init_db -> migrations ==="
body=$(awk '/^main_menu\(\)/{f=1} f{print} f && /^    while true/{exit}' "$SCRIPT")
ln() { echo "$body" | grep -n "$1" | grep -v '^[0-9]*: *#' | head -1 | cut -d: -f1; }
a=$(ln '^ *check_root'); b=$(ln '^ *init_log'); c=$(ln 'ensure_startup_db_dependencies'); d=$(ln '^ *init_db'); e=$(ln 'db_migrate_mieru_service_outbound_to_instances'); f=$(ln 'db_migrate_routing_profiles_v3529')
[[ -n "$a$b$c$d$e$f" && $a -lt $b && $b -lt $c && $c -lt $d && $d -lt $e && $e -lt $f ]] && pass "E static order in main_menu" || fail "E static order a=$a b=$b c=$c d=$d e=$e f=$f"
mk_bin ok; with_jq; rm -rf "$CFGD"; mkdir -p "$CFGD"
seq=$(VLESS_TEST_CFG="$CFGD" bash -c "source '$H'
  for fn in check_root init_log ensure_startup_db_dependencies init_db db_migrate_to_multiuser db_migrate_mieru_service_outbound_to_instances db_migrate_routing_profiles_v3529; do
    eval \"\$fn(){ echo \$fn; return 0; }\"
  done
  ensure_singbox_runtime_consistency(){ exit 0; }
  main_menu" </dev/null 2>/dev/null | tr '\n' ' ')
[[ "$seq" == "check_root init_log ensure_startup_db_dependencies init_db db_migrate_to_multiuser db_migrate_mieru_service_outbound_to_instances db_migrate_routing_profiles_v3529 " ]] \
  && pass "E runtime call order" || fail "E runtime order: $seq"

echo "=== F: full check_dependencies not called at menu start ==="
echo "$body" | grep -v '^ *#' | grep -q 'check_dependencies' && fail "F main_menu pre-loop calls check_dependencies" || pass "F static: not in main_menu startup"
mk_bin ok; with_jq; rm -rf "$CFGD"; mkdir -p "$CFGD"
out=$(printf '0\n' | VLESS_TEST_CFG="$CFGD" bash -c "source '$H'; DISTRO=debian
  check_root(){ :; }
  check_dependencies(){ echo CHECK_DEPS_CALLED; }; configure_dns64(){ echo DNS64_CALLED; }
  _auto_update_system_script(){ :; }; repair_scheduled_jobs(){ :; }; _init_version_cache(){ :; }
  _update_all_versions_async(){ :; }; _check_script_update_async(){ :; }; _sync_tunnel_config(){ :; }
  detect_legacy_ssh_tunnel(){ return 1; }; ensure_singbox_runtime_consistency(){ :; }
  _header(){ :; }; clear(){ :; }; systemctl(){ :; }
  main_menu" 2>&1); rc=$?
echo "$out" | grep -q 'CHECK_DEPS_CALLED\|DNS64_CALLED' && fail "F check_dependencies ran at menu start" || pass "F runtime: check_dependencies not called"
[[ $rc -eq 0 ]] && pass "F menu opened and exited on 0" || fail "F menu rc=$rc: $(echo "$out" | tail -3)"
jq -e 'has("routing_profiles")|not' "$CFGD/db.json" >/dev/null 2>&1 && pass "F startup DB valid, no routing_profiles" || fail "F startup DB invalid/has routing_profiles"
grep -q '分流规则集迁移失败' <<<"$out" && fail "F migration failure at startup" || pass "F no migration failure text"

echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
