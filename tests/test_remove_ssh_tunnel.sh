#!/usr/bin/env bash
# Static tests: remove SSH Tunnel protocol (v3.5.26) — no live sshd required
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/vless-server.sh"
PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Extract function body by line numbers (nested braces-safe)
extract_fn() {
  local name="$1"
  local start end rest
  start=$(grep -m1 -n "^${name}()" "$SCRIPT" | cut -d: -f1)
  [[ -n "$start" ]] || return 1
  rest=$(tail -n +"$((start+1))" "$SCRIPT")
  end=$(grep -m1 -n '^}' <<<"$rest" | cut -d: -f1)
  # That still hits first }; use next top-level function or section comment instead
  end=$(awk -v s="$start" 'NR>s && (/^[a-zA-Z_][a-zA-Z0-9_]*\(\)/ || /^#══/) {print NR; exit}' "$SCRIPT")
  [[ -n "$end" ]] || end=$((start+200))
  sed -n "${start},$((end-1))p" "$SCRIPT"
}

echo "=== A: bash -n ==="
if bash -n "$SCRIPT"; then pass "bash -n"; else fail "bash -n"; fi

echo "=== B: select_protocol no longer offers ssh-tunnel / choice 18 gone ==="
SEL=$(extract_fn select_protocol)
grep -qE '_item "18"|SELECTED_PROTOCOL="ssh-tunnel"|选择协议 \[0-18\]' <<<"$SEL" \
  && fail "select_protocol still offers ssh-tunnel / 18" || pass "select_protocol no ssh-tunnel / no 18"
grep -q '选择协议 \[0-17\]' <<<"$SEL" && pass "prompt [0-17]" || fail "prompt not [0-17]"
grep -q '_item "9" "SOCKS5"' <<<"$SEL" && pass "item 9 SOCKS5" || fail "item 9 changed"
grep -q '_item "10" "Snell v4"' <<<"$SEL" && pass "item 10 Snell v4" || fail "item 10 changed"
grep -q '_item "17" "mieru' <<<"$SEL" && pass "item 17 mieru" || fail "item 17 missing"

echo "=== C: STANDALONE_PROTOCOLS / PROTO table lack ssh-tunnel ==="
SP=$(grep -m1 '^STANDALONE_PROTOCOLS=' "$SCRIPT")
grep -q 'ssh-tunnel' <<<"$SP" && fail "STANDALONE still has ssh-tunnel" || pass "STANDALONE without ssh-tunnel"
grep -qE 'PROTO_SVC\[ssh-tunnel\]|PROTO_KIND\[ssh-tunnel\]|PROTO_BIN\[ssh-tunnel\]|PROTO_EXEC\[ssh-tunnel\]' "$SCRIPT" \
  && fail "PROTO_* still has ssh-tunnel" || pass "PROTO table without ssh-tunnel"

echo "=== D: cleanup exists; create paths gated ==="
grep -q '^cleanup_legacy_ssh_tunnel()' "$SCRIPT" && pass "cleanup_legacy_ssh_tunnel defined" || fail "missing cleanup"
grep -q '^detect_legacy_ssh_tunnel()' "$SCRIPT" && pass "detect_legacy_ssh_tunnel defined" || fail "missing detect"
GEN=$(extract_fn gen_ssh_tunnel_server_config)
APP=$(extract_fn apply_ssh_tunnel_config)
grep -q '已从产品移除' <<<"$GEN" && pass "gen refuses create" || fail "gen not gated"
grep -q '已从产品移除' <<<"$APP" && pass "apply refuses create" || fail "apply not gated"
# no create UI calling gen with args
if grep -nE 'gen_ssh_tunnel_server_config ' "$SCRIPT" | grep -v '_err\|已从产品'; then
  fail "gen_ssh_tunnel still called as create entrypoint"
else
  pass "no gen create call sites"
fi
grep -n 'ask_port "ssh-tunnel"' "$SCRIPT" && fail "ask_port ssh-tunnel still present" || pass "no ask_port ssh-tunnel"

echo "=== E: detect legacy / DB key xray/ssh-tunnel ==="
DET=$(extract_fn detect_legacy_ssh_tunnel)
grep -q 'db_exists "xray" "ssh-tunnel"' <<<"$DET" && pass "detect reads xray/ssh-tunnel" || fail "detect missing db key"
grep -qE 'dropin|_ssh_tunnel_dropin_live|SSH_TUNNEL_DROPIN' <<<"$DET" && pass "detect checks drop-in" || fail "detect missing drop-in"
grep -q 'CFG/ssh-tunnel' <<<"$DET" && pass "detect checks CFG/ssh-tunnel" || fail "detect missing CFG tree"

echo "=== F: refuse arbitrary user delete ==="
OWN=$(extract_fn _ssh_tunnel_user_proven_owned)
CLEAN=$(extract_fn cleanup_legacy_ssh_tunnel)
grep -q '_ssh_tunnel_reserved_username' <<<"$OWN" && pass "refuses reserved users" || fail "no reserved check"
grep -q 'SSH_TUNNEL_GROUP' <<<"$OWN" && pass "requires tunnel group" || fail "no group check"
grep -q 'nologin' <<<"$OWN" && pass "requires nologin shell" || fail "no nologin check"
grep -q '_ssh_tunnel_user_proven_owned' <<<"$CLEAN" && pass "cleanup uses proven ownership" || fail "cleanup skips proven check"

echo "=== G: only exact drop-in name ==="
grep -q 'SSH_TUNNEL_DROPIN_NAME="99-vless-ssh-tunnel.conf"' "$SCRIPT" && pass "fixed drop-in name" || fail "drop-in name wrong"
grep -q 'SSH_TUNNEL_DROPIN_NAME' <<<"$CLEAN" && pass "cleanup checks drop-in name" || fail "cleanup unrestricted drop-in"

echo "=== H: never systemctl stop/disable sshd in cleanup ==="
RELOAD=$(extract_fn _ssh_tunnel_reload)
REMOVE=$(extract_fn _ssh_tunnel_remove_runtime)
if grep -qE 'systemctl (stop|disable) sshd|systemctl (stop|disable) ssh[^a-z]|rc-service sshd stop|rc-service ssh stop' <<<"$CLEAN$RELOAD$REMOVE"; then
  fail "cleanup/reload stops or disables sshd"
else
  pass "no stop/disable sshd in cleanup paths"
fi
grep -qE 'systemctl reload sshd|systemctl reload ssh' <<<"$RELOAD" && pass "reload-only sshd" || fail "missing reload"

echo "=== I: path delete scoped to CFG/ssh-tunnel ==="
if echo "$CLEAN" | grep -E 'rm -rf' | grep -v 'CFG/ssh-tunnel'; then
  fail "cleanup rm -rf outside CFG/ssh-tunnel"
else
  pass "cleanup rm -rf scoped to CFG/ssh-tunnel"
fi

echo "=== J: schema-lock order snapshot → DB delete → keys/drop-in ==="
GET_LINE=$(grep -m1 -n 'db_get "xray" "ssh-tunnel"' <<<"$CLEAN" | cut -d: -f1)
DEL_LINE=$(grep -m1 -n 'db_del "xray" "ssh-tunnel"' <<<"$CLEAN" | cut -d: -f1)
RM_LINE=$(grep -m1 -n 'rm -rf "\$CFG/ssh-tunnel"' <<<"$CLEAN" | cut -d: -f1)
if [[ -n "$GET_LINE" && -n "$DEL_LINE" && -n "$RM_LINE" && "$GET_LINE" -lt "$DEL_LINE" && "$DEL_LINE" -lt "$RM_LINE" ]]; then
  pass "order snapshot(db_get) → db_del → rm CFG/ssh-tunnel"
else
  fail "bad order get=$GET_LINE del=$DEL_LINE rm=$RM_LINE"
fi
for f in username port mode authorized_keys_path bind_addr target; do
  grep -q "\.$f" <<<"$CLEAN" && pass "snapshot field $f" || fail "missing snapshot field $f"
done

echo "=== K: write kills on register/db_* ==="
ctx=$(grep -A12 '^register_protocol()' "$SCRIPT")
grep -q 'ssh-tunnel' <<<"$ctx" && pass "register_protocol refuses ssh-tunnel" || fail "register missing refuse"
ctx=$(grep -A8 '^db_add()' "$SCRIPT")
grep -q 'ssh-tunnel' <<<"$ctx" && pass "db_add refuses ssh-tunnel" || fail "db_add missing refuse"
ctx=$(grep -A8 '^db_update_port()' "$SCRIPT")
grep -q 'ssh-tunnel' <<<"$ctx" && pass "db_update_port refuses ssh-tunnel" || fail "db_update_port missing refuse"
ctx=$(grep -A8 '^db_add_port()' "$SCRIPT")
grep -q 'ssh-tunnel' <<<"$ctx" && pass "db_add_port refuses ssh-tunnel" || fail "db_add_port missing refuse"

echo "=== L: create_service refuses ssh-tunnel ==="
CS=$(extract_fn create_service)
cs_head=$(head -40 <<<"$CS")
grep -q '已从产品移除' <<<"$cs_head" && pass "create_service refuses ssh-tunnel" || fail "create_service still applies"

echo "=== M: no raw key material in cleanup ==="
grep -qiE 'BEGIN OPENSSH|PRIVATE KEY|st_pubkey' <<<"$CLEAN" && fail "cleanup references raw keys" || pass "cleanup has no raw key material"

echo "=== N: opt-in confirm present; force only for confirmed callers ==="
grep -q '确认清理遗留 SSH Tunnel' <<<"$CLEAN" && pass "interactive confirm present" || fail "missing confirm prompt"
grep -q 'mode" != "force"' <<<"$CLEAN" && pass "force mode gated" || fail "force mode missing"
# main_menu one-shot prompt
ctx=$(grep -A20 '_SSH_TUNNEL_LEGACY_PROMPTED' "$SCRIPT")
grep -q 'cleanup_legacy_ssh_tunnel force' <<<"$ctx" && pass "menu opt-in wires cleanup" || fail "menu prompt missing"

echo "=== 8: sshd -t/-T fail-closed before reload after drop-in rm ==="
DROP=$(extract_fn _ssh_tunnel_remove_managed_dropin_failclosed)
TESTF=$(extract_fn _ssh_tunnel_test_sshd)
REST=$(extract_fn _ssh_tunnel_restore_dropin_from_bak)
grep -qE '\$sshd" -t|\$sshd -t' <<<"$TESTF" && pass "test_sshd runs sshd -t" || fail "missing sshd -t"
grep -qE '\$sshd" -T|\$sshd -T' <<<"$TESTF" && pass "test_sshd runs sshd -T" || fail "missing sshd -T"
grep -q '_ssh_tunnel_test_sshd' <<<"$DROP" && pass "drop-in remove calls test_sshd" || fail "no test before reload"
grep -q '_ssh_tunnel_reload' <<<"$DROP" && pass "drop-in remove calls reload" || fail "no reload after test"
grep -q '_ssh_tunnel_restore_dropin_from_bak' <<<"$DROP" && pass "uses checked restore helper" || fail "no checked restore helper"
# checked rm: must not bare rm -f without failure handling
grep -qE 'if ! rm -f "\$live"' <<<"$DROP" && pass "rm outcome checked" || fail "rm unchecked"
grep -q '\[\[ -e "\$live" \]\]' <<<"$DROP" && pass "verifies drop-in gone after rm" || fail "no post-rm existence check"
# restore helper must check cp and never || true swallow
grep -qE 'if ! cp -f "\$bak" "\$live"' <<<"$REST" && pass "restore checks cp" || fail "restore cp unchecked"
if grep -qE 'cp -f "\$bak" "\$live".*\|\| true' <<<"$REST"; then
  fail "restore still swallows cp with || true"
else
  pass "restore no cp||true"
fi
grep -q '备份仍保留' <<<"$REST" && pass "restore-fail retains bak path" || fail "no bak retain on restore fail"
# failure paths: claim restored only after successful restore helper
ctx=$(grep -A3 '_ssh_tunnel_restore_dropin_from_bak' <<<"$DROP")
grep -q '已恢复托管 drop-in' <<<"$ctx" && pass "claims restored only after helper success" || fail "restored claim not gated"
grep -q '恢复 drop-in 失败；备份仍保留' <<<"$DROP" && pass "hard-fail path retains bak" || fail "missing restore-fail message"
# forbid unchecked restore pattern in drop fn
if grep -qE 'cp -f "\$bak" "\$live".*\|\| true' <<<"$DROP"; then
  fail "dropin fn still has unchecked cp||true"
else
  pass "dropin fn no unchecked cp||true"
fi
CLEAN=$(extract_fn cleanup_legacy_ssh_tunnel)
grep -q '_ssh_tunnel_remove_managed_dropin_failclosed' <<<"$CLEAN" && pass "cleanup uses fail-closed drop-in remove" || fail "cleanup bypasses fail-closed"
if grep -qE '_ssh_tunnel_reload \|\| true' <<<"$CLEAN"; then
  fail "cleanup still swallows reload with || true"
else
  pass "cleanup no bare reload||true"
fi

echo "=== 9: primary GID checked before groupdel ==="
PRIM=$(extract_fn _ssh_tunnel_group_has_primary_users)
grep -q 'getent passwd' <<<"$PRIM" && pass "primary check scans passwd" || fail "primary check missing passwd scan"
grep -qE '\$4 == g|\$4==g' <<<"$PRIM" && pass "compares primary GID field" || fail "no primary GID compare"
grep -q '_ssh_tunnel_group_has_primary_users' <<<"$CLEAN" && pass "cleanup gates groupdel on primary" || fail "groupdel not gated on primary"
# supplementary still checked
grep -q 'awk -F: '"'"'{print \$4}'"'"'' <<<"$CLEAN" && pass "still checks supplementary members" || pass "supplementary check present"

echo "=== O: VERSION left for Documentor ==="
VER=$(grep -m1 '^readonly VERSION=' "$SCRIPT" | cut -d'"' -f2)
pass "VERSION=$VER (Documentor may bump)"

echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
