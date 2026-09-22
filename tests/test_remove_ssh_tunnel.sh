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
  local start end
  start=$(grep -n "^${name}()" "$SCRIPT" | head -1 | cut -d: -f1)
  [[ -n "$start" ]] || return 1
  end=$(tail -n +"$((start+1))" "$SCRIPT" | grep -n '^}' | head -1 | cut -d: -f1)
  # That still hits first }; use next top-level function or section comment instead
  end=$(awk -v s="$start" 'NR>s && (/^[a-zA-Z_][a-zA-Z0-9_]*\(\)/ || /^#══/) {print NR; exit}' "$SCRIPT")
  [[ -n "$end" ]] || end=$((start+200))
  sed -n "${start},$((end-1))p" "$SCRIPT"
}

echo "=== A: bash -n ==="
if bash -n "$SCRIPT"; then pass "bash -n"; else fail "bash -n"; fi

echo "=== B: select_protocol no longer offers ssh-tunnel / choice 18 gone ==="
SEL=$(extract_fn select_protocol)
echo "$SEL" | grep -qE '_item "18"|SELECTED_PROTOCOL="ssh-tunnel"|选择协议 \[0-18\]' \
  && fail "select_protocol still offers ssh-tunnel / 18" || pass "select_protocol no ssh-tunnel / no 18"
echo "$SEL" | grep -q '选择协议 \[0-17\]' && pass "prompt [0-17]" || fail "prompt not [0-17]"
echo "$SEL" | grep -q '_item "9" "SOCKS5"' && pass "item 9 SOCKS5" || fail "item 9 changed"
echo "$SEL" | grep -q '_item "10" "Snell v4"' && pass "item 10 Snell v4" || fail "item 10 changed"
echo "$SEL" | grep -q '_item "17" "mieru' && pass "item 17 mieru" || fail "item 17 missing"

echo "=== C: STANDALONE_PROTOCOLS / PROTO table lack ssh-tunnel ==="
SP=$(grep -m1 '^STANDALONE_PROTOCOLS=' "$SCRIPT")
echo "$SP" | grep -q 'ssh-tunnel' && fail "STANDALONE still has ssh-tunnel" || pass "STANDALONE without ssh-tunnel"
grep -qE 'PROTO_SVC\[ssh-tunnel\]|PROTO_KIND\[ssh-tunnel\]|PROTO_BIN\[ssh-tunnel\]|PROTO_EXEC\[ssh-tunnel\]' "$SCRIPT" \
  && fail "PROTO_* still has ssh-tunnel" || pass "PROTO table without ssh-tunnel"

echo "=== D: cleanup exists; create paths gated ==="
grep -q '^cleanup_legacy_ssh_tunnel()' "$SCRIPT" && pass "cleanup_legacy_ssh_tunnel defined" || fail "missing cleanup"
grep -q '^detect_legacy_ssh_tunnel()' "$SCRIPT" && pass "detect_legacy_ssh_tunnel defined" || fail "missing detect"
GEN=$(extract_fn gen_ssh_tunnel_server_config)
APP=$(extract_fn apply_ssh_tunnel_config)
echo "$GEN" | grep -q '已从产品移除' && pass "gen refuses create" || fail "gen not gated"
echo "$APP" | grep -q '已从产品移除' && pass "apply refuses create" || fail "apply not gated"
# no create UI calling gen with args
if grep -nE 'gen_ssh_tunnel_server_config ' "$SCRIPT" | grep -v '_err\|已从产品'; then
  fail "gen_ssh_tunnel still called as create entrypoint"
else
  pass "no gen create call sites"
fi
grep -n 'ask_port "ssh-tunnel"' "$SCRIPT" && fail "ask_port ssh-tunnel still present" || pass "no ask_port ssh-tunnel"

echo "=== E: detect legacy / DB key xray/ssh-tunnel ==="
DET=$(extract_fn detect_legacy_ssh_tunnel)
echo "$DET" | grep -q 'db_exists "xray" "ssh-tunnel"' && pass "detect reads xray/ssh-tunnel" || fail "detect missing db key"
echo "$DET" | grep -qE 'dropin|_ssh_tunnel_dropin_live|SSH_TUNNEL_DROPIN' && pass "detect checks drop-in" || fail "detect missing drop-in"
echo "$DET" | grep -q 'CFG/ssh-tunnel' && pass "detect checks CFG/ssh-tunnel" || fail "detect missing CFG tree"

echo "=== F: refuse arbitrary user delete ==="
OWN=$(extract_fn _ssh_tunnel_user_proven_owned)
CLEAN=$(extract_fn cleanup_legacy_ssh_tunnel)
echo "$OWN" | grep -q '_ssh_tunnel_reserved_username' && pass "refuses reserved users" || fail "no reserved check"
echo "$OWN" | grep -q 'SSH_TUNNEL_GROUP' && pass "requires tunnel group" || fail "no group check"
echo "$OWN" | grep -q 'nologin' && pass "requires nologin shell" || fail "no nologin check"
echo "$CLEAN" | grep -q '_ssh_tunnel_user_proven_owned' && pass "cleanup uses proven ownership" || fail "cleanup skips proven check"

echo "=== G: only exact drop-in name ==="
grep -q 'SSH_TUNNEL_DROPIN_NAME="99-vless-ssh-tunnel.conf"' "$SCRIPT" && pass "fixed drop-in name" || fail "drop-in name wrong"
echo "$CLEAN" | grep -q 'SSH_TUNNEL_DROPIN_NAME' && pass "cleanup checks drop-in name" || fail "cleanup unrestricted drop-in"

echo "=== H: never systemctl stop/disable sshd in cleanup ==="
RELOAD=$(extract_fn _ssh_tunnel_reload)
REMOVE=$(extract_fn _ssh_tunnel_remove_runtime)
if echo "$CLEAN$RELOAD$REMOVE" | grep -qE 'systemctl (stop|disable) sshd|systemctl (stop|disable) ssh[^a-z]|rc-service sshd stop|rc-service ssh stop'; then
  fail "cleanup/reload stops or disables sshd"
else
  pass "no stop/disable sshd in cleanup paths"
fi
echo "$RELOAD" | grep -qE 'systemctl reload sshd|systemctl reload ssh' && pass "reload-only sshd" || fail "missing reload"

echo "=== I: path delete scoped to CFG/ssh-tunnel ==="
if echo "$CLEAN" | grep -E 'rm -rf' | grep -v 'CFG/ssh-tunnel'; then
  fail "cleanup rm -rf outside CFG/ssh-tunnel"
else
  pass "cleanup rm -rf scoped to CFG/ssh-tunnel"
fi

echo "=== J: schema-lock order snapshot → DB delete → keys/drop-in ==="
GET_LINE=$(echo "$CLEAN" | grep -n 'db_get "xray" "ssh-tunnel"' | head -1 | cut -d: -f1)
DEL_LINE=$(echo "$CLEAN" | grep -n 'db_del "xray" "ssh-tunnel"' | head -1 | cut -d: -f1)
RM_LINE=$(echo "$CLEAN" | grep -n 'rm -rf "\$CFG/ssh-tunnel"' | head -1 | cut -d: -f1)
if [[ -n "$GET_LINE" && -n "$DEL_LINE" && -n "$RM_LINE" && "$GET_LINE" -lt "$DEL_LINE" && "$DEL_LINE" -lt "$RM_LINE" ]]; then
  pass "order snapshot(db_get) → db_del → rm CFG/ssh-tunnel"
else
  fail "bad order get=$GET_LINE del=$DEL_LINE rm=$RM_LINE"
fi
for f in username port mode authorized_keys_path bind_addr target; do
  echo "$CLEAN" | grep -q "\.$f" && pass "snapshot field $f" || fail "missing snapshot field $f"
done

echo "=== K: write kills on register/db_* ==="
grep -A12 '^register_protocol()' "$SCRIPT" | grep -q 'ssh-tunnel' && pass "register_protocol refuses ssh-tunnel" || fail "register missing refuse"
grep -A8 '^db_add()' "$SCRIPT" | grep -q 'ssh-tunnel' && pass "db_add refuses ssh-tunnel" || fail "db_add missing refuse"
grep -A8 '^db_update_port()' "$SCRIPT" | grep -q 'ssh-tunnel' && pass "db_update_port refuses ssh-tunnel" || fail "db_update_port missing refuse"
grep -A8 '^db_add_port()' "$SCRIPT" | grep -q 'ssh-tunnel' && pass "db_add_port refuses ssh-tunnel" || fail "db_add_port missing refuse"

echo "=== L: create_service refuses ssh-tunnel ==="
CS=$(extract_fn create_service)
echo "$CS" | head -40 | grep -q '已从产品移除' && pass "create_service refuses ssh-tunnel" || fail "create_service still applies"

echo "=== M: no raw key material in cleanup ==="
echo "$CLEAN" | grep -qiE 'BEGIN OPENSSH|PRIVATE KEY|st_pubkey' && fail "cleanup references raw keys" || pass "cleanup has no raw key material"

echo "=== N: opt-in confirm present; force only for confirmed callers ==="
echo "$CLEAN" | grep -q '确认清理遗留 SSH Tunnel' && pass "interactive confirm present" || fail "missing confirm prompt"
echo "$CLEAN" | grep -q 'mode" != "force"' && pass "force mode gated" || fail "force mode missing"
# main_menu one-shot prompt
grep -A20 '_SSH_TUNNEL_LEGACY_PROMPTED' "$SCRIPT" | grep -q 'cleanup_legacy_ssh_tunnel force' && pass "menu opt-in wires cleanup" || fail "menu prompt missing"

echo "=== O: VERSION left for Documentor ==="
VER=$(grep -m1 '^readonly VERSION=' "$SCRIPT" | cut -d'"' -f2)
pass "VERSION=$VER (Documentor may bump)"

echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
