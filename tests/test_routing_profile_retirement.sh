#!/usr/bin/env bash
# v3.5.30 routing-profile retirement: behavioural tests (cases A-N).
# Sources the real vless-server.sh (minus the CLI dispatcher) with CFG redirected
# to a temp dir; service/restart side effects are stubbed and counted.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/vless-server.sh"
PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
command -v jq >/dev/null || { echo "jq required"; exit 1; }
HAVE_SCRIPT_PTY=0; command -v script >/dev/null 2>&1 && HAVE_SCRIPT_PTY=1

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
H="$WORK/h.sh"; STUBS="$WORK/stubs.sh"; CFGD="$WORK/cfg"; CALLS="$WORK/calls"
CASEL=$(grep -n '^case "\${1:-}" in' "$SCRIPT" | tail -1 | cut -d: -f1)
head -n $((CASEL-1)) "$SCRIPT" \
  | sed -e 's|^readonly CFG="/etc/vless-reality"|readonly CFG="${VLESS_TEST_CFG:?}"|' > "$H"
grep -q 'VLESS_TEST_CFG' "$H" || { echo "harness: CFG rewrite failed"; exit 1; }

cat > "$STUBS" <<STUB
_header(){ :; }; _pause(){ :; }; clear(){ :; }
warp_status(){ echo configured; }
_routing_meaningfully_configured(){ return 0; }
_regenerate_proxy_configs(){ echo "regen \$*" >> "$CALLS"; }
restart_service(){ echo "restart \$*" >> "$CALLS"; }
svc(){ echo "svc \$*" >> "$CALLS"; }
systemctl(){ echo "systemctl \$*" >> "$CALLS"; }
rc-service(){ echo "rc \$*" >> "$CALLS"; }
_limited_change_begin(){ return 0; }; _limited_change_rollback(){ :; }
STUB

reset_db() { rm -rf "$CFGD"; mkdir -p "$CFGD"; : > "$CALLS"; [[ -n "${1:-}" ]] && printf '%s\n' "$1" > "$CFGD/db.json"; }
# run BODY [stdin via pipe]
run() { VLESS_TEST_CFG="$CFGD" bash -c "source '$H'; source '$STUBS'; $1"; }
# run BODY under a pseudo-tty (for [[ -t 0 ]] install-time prompts); $2 = keystrokes
run_pty() {
  printf '%s\n' "source '$H'; source '$STUBS'; $1" > "$WORK/pty.sh"
  printf "$2" | VLESS_TEST_CFG="$CFGD" script -qec "bash '$WORK/pty.sh'" /dev/null
}
db() { cat "$CFGD/db.json"; }
dbq() { jq -e "$1" "$CFGD/db.json" >/dev/null; }
h() { md5sum < "$CFGD/db.json"; }
strip() { sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r//g'; }
opts() { strip | sed -n 's/^ *\([0-9k]\)) .*/\1/p' | tr '\n' ' '; }
ncalls() { [[ -s "$CALLS" ]] && wc -l < "$CALLS" | tr -d ' ' || echo 0; }

PROFILE_HOME='{"id":"home","name":"家宽","fallback":"inherit","rules":[{"id":"r1","type":"custom","domains":"geosite:netflix","outbound":"direct","ip_version":"prefer_ipv4"}]}'
EXTRA='"chain_proxy":{"nodes":[{"name":"JP","type":"socks","server":"127.0.0.1","port":1080}]},"balancer_groups":[{"name":"g1","strategy":"random","nodes":["JP"]}]'
LEGACY="{\"version\":\"4.0.0\",\"xray\":{\"vless\":[{\"port\":443,\"uuid\":\"U\",\"instance_outbound\":\"profile:home\"}],\"mieru\":[{\"schema_version\":2,\"port\":4405,\"transport\":\"TCP\",\"users\":[{\"name\":\"m\",\"password\":\"P\",\"enabled\":true}],\"instance_outbound\":\"profile:home\"}]},\"singbox\":{},\"meta\":{},$EXTRA,\"routing_profiles\":[$PROFILE_HOME]}"
PLAIN="{\"version\":\"4.0.0\",\"xray\":{\"vless\":[{\"port\":443,\"uuid\":\"U\"}],\"mieru\":[{\"schema_version\":2,\"port_range\":\"20000-20010\",\"transport\":\"TCP\",\"users\":[{\"name\":\"m\",\"password\":\"P\",\"enabled\":true}]}]},\"singbox\":{},\"meta\":{},$EXTRA}"

echo "=== A: manage prompt (Xray) offers exactly 1-5 + 0 ==="
reset_db "$PLAIN"
out=$(printf '0\n' | run '_prompt_instance_outbound vless 443 ""' 2>&1)
[[ "$(echo "$out" | opts)" == "1 2 3 4 5 0 " ]] && pass "A xray options 1-5,0" || fail "A xray options: $(echo "$out" | opts)"
echo "$out" | strip | grep -qE '家宽|直出备用|规则集|profile' && fail "A legacy/profile items leaked" || pass "A no 家宽/直出备用/规则集 items"

echo "=== B: manage prompt (Mieru) offers exactly 1-5 + 0 ==="
out=$(printf '0\n' | run '_prompt_instance_outbound mieru 20000-20010 ""' 2>&1)
[[ "$(echo "$out" | opts)" == "1 2 3 4 5 0 " ]] && pass "B mieru options 1-5,0" || fail "B mieru options: $(echo "$out" | opts)"
out=$(printf '1\n0\n0\n' | run 'manage_instance_outbound' 2>&1)
echo "$out" | strip | grep -q 'Mieru.*20000-20010\|mieru.*20000-20010' && pass "B mieru row in manage menu" || fail "B mieru row missing"

echo "=== C: install-time Xray prompt (register_protocol, tty) ==="
if [[ $HAVE_SCRIPT_PTY == 1 ]]; then
  reset_db; run 'init_db' 2>/dev/null
  out=$(run_pty 'register_protocol vless "{\"port\":8443,\"uuid\":\"U\"}"' '2\n' 2>&1)
  [[ "$(echo "$out" | opts)" == "1 2 3 4 5 0 " ]] && pass "C install prompt 1-5,0" || fail "C install options: $(echo "$out" | opts)"
  dbq '.xray.vless.instance_outbound=="direct"' && pass "C install choice 2 -> direct" || fail "C install write: $(jq -c .xray "$CFGD/db.json")"
else
  fail "C needs util-linux script(1) for pty"
fi

echo "=== D: install-time Mieru prompt; portRange stays one row ==="
if [[ $HAVE_SCRIPT_PTY == 1 ]]; then
  reset_db; run 'init_db' 2>/dev/null
  out=$(run_pty 'gen_mieru_server_config m Pw12345678 20000-20010 TCP off ""' '3\n' 2>&1)
  [[ "$(echo "$out" | opts)" == "1 2 3 4 5 0 " ]] && pass "D mieru install prompt 1-5,0" || fail "D mieru install options: $(echo "$out" | opts)"
  dbq '(.xray.mieru|type=="array" and length==1) and .xray.mieru[0].port_range=="20000-20010" and .xray.mieru[0].instance_outbound=="warp"' \
    && pass "D portRange one row, choice 3 -> warp" || fail "D mieru row: $(jq -c '.xray.mieru|map({port,port_range,instance_outbound})' "$CFGD/db.json" 2>/dev/null)"
  keys=$(run 'db_list_ports xray mieru' 2>/dev/null | wc -l)
  [[ "$keys" == 1 ]] && pass "D db_list_ports mieru = 1 key" || fail "D mieru keys=$keys"
else
  fail "D needs util-linux script(1) for pty"
fi

echo "=== E: deleted functions absent; no other profile-creation UI ==="
dead=$(run 'for f in wizard_home_broadband_direct_backup _select_instance_outbound_policy manage_routing_profiles _edit_routing_profile _show_routing_profile_users _routing_profile_validate_and_apply db_ensure_routing_profiles_defaults; do declare -F $f >/dev/null && echo $f; done' 2>/dev/null)
[[ -z "$dead" ]] && pass "E deleted functions absent (declare -F)" || fail "E still defined: $dead"
ui_callers=$(awk '/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/{fn=$1} /db_add_routing_profile[ "]|db_copy_routing_profile[ "]|db_add_routing_profile_rule[ "]/ && !/^[[:space:]]*#/ && fn !~ /^_?db_/ {print NR": "fn}' "$SCRIPT")
[[ -z "$ui_callers" ]] && pass "E no non-DB caller creates profiles" || fail "E profile creation callers: $ui_callers"
grep -nE 'SELECTED_INSTANCE_OUTBOUND="profile:' "$SCRIPT" >/dev/null && fail "E UI assigns profile:*" || pass "E UI never assigns profile:*"

echo "=== F: every new UI choice writes non-profile vocabulary ==="
declare -A want=([1]='(.xray.vless[0]|has("instance_outbound"))|not' [2]='.xray.vless[0].instance_outbound=="direct"' [3]='.xray.vless[0].instance_outbound=="warp"' [4]='.xray.vless[0].instance_outbound=="chain:JP"' [5]='.xray.vless[0].instance_outbound=="balancer:g1"')
declare -A keys=([1]='1\n' [2]='2\n' [3]='3\n' [4]='4\n1\n' [5]='5\n1\n')
for c in 1 2 3 4 5; do
  reset_db "$PLAIN"; run 'db_set_instance_outbound xray vless 443 direct' 2>/dev/null
  [[ $c == 2 ]] && run 'db_clear_instance_outbound xray vless 443' 2>/dev/null
  printf "1\n${keys[$c]}0\n" | run 'manage_instance_outbound' >/dev/null 2>&1
  if dbq "${want[$c]}" && ! grep -q '"profile:' "$CFGD/db.json"; then pass "F choice $c ok"; else fail "F choice $c: $(jq -c '.xray.vless' "$CFGD/db.json")"; fi
done

echo "=== G: db_set_instance_outbound profile:* vocabulary ==="
reset_db "$LEGACY"; b=$(h)
run 'db_set_instance_outbound xray vless 443 profile:other' 2>/dev/null && fail "G accepted new profile:other" || pass "G rejects new profile:other"
run 'db_set_instance_outbound xray vless 443 profile:home' 2>/dev/null && pass "G same stored profile:home rc0" || fail "G same stored rejected"
[[ "$(h)" == "$b" ]] && pass "G no write on reject/no-op" || fail "G DB changed"
run 'db_set_instance_outbound xray vless 443 direct' 2>/dev/null
run 'db_set_instance_outbound xray vless 443 profile:home' 2>/dev/null && fail "G re-binding profile:home after switch accepted" || pass "G cannot re-bind profile after switch"
run 'db_set_instance_outbound xray mieru 4405 profile:home' 2>/dev/null && pass "G mieru legacy keep rc0" || fail "G mieru keep rejected"

echo "=== H: legacy profile:home (家宽) shows 旧规则集: 家宽 without id ==="
reset_db "$LEGACY"
out=$(printf '1\nk\n0\n' | run 'manage_instance_outbound' 2>&1 | strip)
echo "$out" | grep -q '旧规则集: 家宽' && pass "H shows 旧规则集: 家宽" || fail "H no 旧规则集: 家宽"
echo "$out" | grep -qE 'profile:|\bhome\b' && fail "H internal id leaked" || pass "H no internal id"
if [[ $HAVE_SCRIPT_PTY == 1 ]]; then
  pout=$(run_pty '_prompt_instance_outbound vless 443 profile:home; echo "SEL=[$SELECTED_INSTANCE_OUTBOUND]"' '\n' 2>&1 | strip)
  echo "$pout" | grep -q '请选择 \[k\]' && pass "H default choice is k" || fail "H default not k"
  echo "$pout" | grep -q 'SEL=\[profile:home\]' && pass "H <enter> keeps stored value" || fail "H enter did not keep"
else
  fail "H needs script(1) for pty"
fi
lopts=$(printf '0\n' | run '_prompt_instance_outbound vless 443 profile:home' 2>&1 | opts)
[[ "$lopts" == "k 1 2 3 4 5 0 " ]] && pass "H legacy options k,1-5,0" || fail "H legacy options: $lopts"
disp=$(run '_get_outbound_display_name profile:home' 2>/dev/null)
[[ "$disp" == "旧规则集: 家宽" ]] && pass "H display name" || fail "H display: $disp"

echo "=== I: k keeps (Xray + Mieru): DB byte-identical, no restart ==="
for sel in 1 2; do
  for key in 'k' ''; do
    reset_db "$LEGACY"; b=$(h)
    printf "$sel\n$key\n0\n" | run 'manage_instance_outbound' >/dev/null 2>&1
    lbl="row$sel key='${key:-<enter>}'"
    [[ "$(h)" == "$b" ]] && pass "I $lbl DB byte-identical" || fail "I $lbl DB changed"
    [[ "$(ncalls)" == 0 ]] && pass "I $lbl no restart/regen" || fail "I $lbl calls: $(tr '\n' ';' < "$CALLS")"
  done
done

echo "=== J: switching to direct keeps profile object (orphan) ==="
reset_db "$LEGACY"
printf '1\n2\n0\n' | run 'manage_instance_outbound' >/dev/null 2>&1
dbq '.xray.vless[0].instance_outbound=="direct"' && pass "J vless -> direct" || fail "J vless not direct"
dbq '.routing_profiles[0].id=="home" and .routing_profiles[0].name=="家宽" and (.routing_profiles[0].rules|length)==1' && pass "J profile object preserved" || fail "J profile removed/changed"
grep -q '^regen xray' "$CALLS" && pass "J regen xray once on real change" || fail "J no regen on change"
printf '2\n2\n0\n' | run 'manage_instance_outbound' >/dev/null 2>&1
dbq '.xray.mieru[0].instance_outbound=="direct" and (.routing_profiles|length)==1' && pass "J last ref gone, orphan kept" || fail "J orphan handling"

echo "=== K: missing profile -> 已缺失, compilers fail closed ==="
reset_db "$(echo "$LEGACY" | jq -c '.routing_profiles=[] | .xray.vless[0].instance_outbound="profile:ghost" | .xray.mieru[0].instance_outbound="profile:ghost"')"
out=$(printf '1\nk\n0\n' | run 'manage_instance_outbound' 2>&1 | strip)
echo "$out" | grep -q '旧规则集: 已缺失' && pass "K shows 旧规则集: 已缺失" || fail "K no 已缺失"
echo "$out" | grep -q 'ghost' && fail "K id leaked" || pass "K no id in UI"
err=$(run 'gen_xray_instance_outbound_rules' 2>&1 >/dev/null); rc=$?
[[ $rc -ne 0 ]] && echo "$err" | grep -q '分流规则集不存在: profile:ghost' && pass "K xray fail-closed msg" || fail "K xray rc=$rc err=$err"
run '_mieru_compile_egress_plan 4405' >/dev/null 2>&1 && fail "K mieru compiled on missing profile" || pass "K mieru fail-closed"

echo "=== L: clean DB: init_db + migrations -> no routing_profiles, idempotent, no snapshot ==="
reset_db; run 'init_db' 2>/dev/null; b=$(h)
run 'db_migrate_to_multiuser; db_migrate_mieru_service_outbound_to_instances && db_migrate_routing_profiles_v3529' >/dev/null 2>&1 && pass "L migrations rc0" || fail "L migrations rc!=0"
dbq 'has("routing_profiles")|not' && pass "L no .routing_profiles" || fail "L routing_profiles created"
[[ "$(h)" == "$b" ]] && pass "L clean DB byte-identical" || fail "L clean DB changed"
extra=$(ls -A "$CFGD" | grep -vxE 'db.json|\.db\.lock' || true)
[[ -z "$extra" ]] && pass "L no snapshot/residue" || fail "L residue: $extra"
reset_db "$PLAIN"; b=$(h); run 'db_migrate_routing_profiles_v3529' >/dev/null 2>&1
[[ "$(h)" == "$b" ]] && pass "L populated profile-free DB byte-identical" || fail "L populated DB changed"

echo "=== M: legacy DB migration keeps profile; Xray + Mieru compile ==="
reset_db "$LEGACY"
run 'db_migrate_routing_profiles_v3529' >/dev/null 2>&1 && pass "M migrate rc0" || fail "M migrate rc"
dbq '.routing_profiles[0].id=="home" and .routing_profiles[0].name=="家宽" and .xray.vless[0].instance_outbound=="profile:home" and .xray.mieru[0].instance_outbound=="profile:home"' && pass "M profile + refs kept" || fail "M legacy altered"
xr=$(run 'gen_xray_instance_outbound_rules' 2>/dev/null)
echo "$xr" | jq -e 'any(.[]; (.inboundTag|index("vless-443")!=null) and ((.domain//[])|index("geosite:netflix")!=null))' >/dev/null && pass "M xray profile rules compiled" || fail "M xray rules: $xr"
mp=$(run '_mieru_compile_egress_plan 4405' 2>/dev/null)
echo "$mp" | jq -e 'type=="object" and (tostring|contains("netflix"))' >/dev/null && pass "M mieru profile plan compiled" || fail "M mieru plan: $(echo "$mp" | head -c 300)"

echo "=== N: mieru not in XRAY_PROTOCOLS; profile-free generation works ==="
xp=$(run 'echo " $XRAY_PROTOCOLS "' 2>/dev/null)
[[ "$xp" != *" mieru "* ]] && pass "N mieru not in XRAY_PROTOCOLS" || fail "N mieru in XRAY_PROTOCOLS"
reset_db "$PLAIN"; run 'db_set_instance_outbound xray vless 443 balancer:g1; db_set_instance_outbound xray mieru 20000-20010 direct' 2>/dev/null
xr=$(run 'gen_xray_instance_outbound_rules' 2>/dev/null)
echo "$xr" | jq -e 'length==1 and .[0].balancerTag=="balancer-g1"' >/dev/null && pass "N xray balancer rule" || fail "N xray rules: $xr"
mp=$(run '_mieru_compile_egress_plan 20000-20010' 2>/dev/null) && pass "N mieru direct plan rc0" || fail "N mieru plan failed"
reset_db "$PLAIN"
xr=$(run 'gen_xray_instance_outbound_rules' 2>/dev/null)
[[ "$(echo "$xr" | jq -c .)" == "[]" ]] && pass "N no overrides -> []" || fail "N inherit rules: $xr"
dbq 'has("routing_profiles")|not' && pass "N generation did not create routing_profiles" || fail "N key created"

echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
