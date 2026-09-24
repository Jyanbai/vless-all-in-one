#!/usr/bin/env bash
# Local semantic tests for Mieru per-instance runtime + outbound (v3.5.27)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/vless-server.sh"
PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== A: bash -n ==="
if bash -n "$SCRIPT"; then pass "bash -n"; else fail "bash -n"; fi

echo "=== B: VERSION pin (VERSION 3.5.28) ==="
VER=$(grep -m1 '^readonly VERSION=' "$SCRIPT" | cut -d'"' -f2)
R=$(sed -n 's/^Current script version: \*\*v\([0-9.]*\)\*\*.*/\1/p' "$ROOT/README.md" | head -1)
C=$(sed -n 's/^当前脚本版本：\*\*v\([0-9.]*\)\*\*.*/\1/p' "$ROOT/README_CN.md" | head -1)
[[ "$VER" == "3.5.28" && "$VER" == "$R" && "$VER" == "$C" ]] && pass "VERSION=$VER synced" || fail "VERSION mismatch script=$VER readme=$R cn=$C"

echo "=== C: per-instance symbols ==="
for s in _mieru_instance_slug _mieru_instance_config_path _mieru_instance_svc_name \
         _mieru_instance_uds_path _mieru_instance_state_dir create_mieru_instance_service \
         create_mieru_services _smart_apply_mieru_instances generate_mieru_config \
         _mieru_compile_egress_plan db_get_instance_outbound db_list_ports \
         db_migrate_mieru_service_outbound_to_instances manage_instance_outbound; do
  if grep -qE "^${s}\(\)|_${s}\(\)" "$SCRIPT" || grep -q "^${s}()" "$SCRIPT"; then
    pass "symbol $s"
  else
    fail "missing $s"
  fi
done

echo "=== D: UI lists mieru via db_list_ports; no 全部实例 ==="
ui=$(awk '/^manage_instance_outbound\(\)/{f=1} f{print} /^\}$/{if(f&&++c==1) exit}' "$SCRIPT")
if echo "$ui" | grep -q 'Mieru（全部实例）'; then fail "still has Mieru（全部实例）"; else pass "no Mieru（全部实例）"; fi
if echo "$ui" | grep -q '\[\[ "\$proto" == "mieru" \]\] && continue'; then
  fail "mieru still skipped in loop"
else
  pass "mieru included in per-port/portRange loop"
fi
if echo "$ui" | grep -q 'db_list_ports "xray" "\$proto"'; then pass "db_list_ports in UI loop"; else fail "no db_list_ports in UI"; fi
if echo "$ui" | grep -q 'db_get_service_outbound_mieru\|db_set_service_outbound_mieru'; then
  fail "UI still uses service_outbound APIs"
else
  pass "UI uses instance_outbound only"
fi

echo "=== E: compile reads instance_outbound; not service in final path ==="
# First 40 lines of compile must mention db_get_instance_outbound and NOT db_get_service_outbound_mieru
head_block=$(awk '/^_mieru_compile_egress_plan\(\)/{f=1} f{print; if(++n>=45) exit}' "$SCRIPT")
if echo "$head_block" | grep -q 'db_get_instance_outbound'; then pass "compile reads instance_outbound"; else fail "compile missing instance_outbound"; fi
# Ignore comment lines that mention the forbidden symbol by name
if echo "$head_block" | grep -v '^[[:space:]]*#' | grep -qE 'db_get_service_outbound_mieru[[:space:]]*($|\|)|\$\(db_get_service_outbound_mieru'; then
  fail "compile still calls db_get_service_outbound_mieru"
else
  pass "compile final path has no service_outbound read"
fi
if grep -q 'Do NOT call db_get_service_outbound_mieru' "$SCRIPT"; then pass "explicit no-service comment"; else fail "missing no-service comment"; fi

echo "=== F: layout — config/UDS/svc/state helpers ==="
grep -q 'CFG/mieru/\${slug}.json\|CFG/mieru/${slug}.json' "$SCRIPT" && pass "config path \$CFG/mieru/<slug>.json" || fail "config path"
grep -q '/run/mita/\${slug}/mita.sock\|/run/mita/${slug}/mita.sock' "$SCRIPT" && pass "UDS /run/mita/<slug>/" || fail "UDS path"
grep -q 'vless-mieru-\${slug}\|vless-mieru-${slug}' "$SCRIPT" && pass "svc vless-mieru-<slug>" || fail "svc name"
grep -q '/var/lib/vless-mieru/\${slug}\|/var/lib/vless-mieru/${slug}' "$SCRIPT" && pass "state dir" || fail "state dir"

echo "=== G: metrics isolation (BindPaths + unshare bind) ==="
if grep -q 'BindPaths=\${state_dir}:/var/lib/mita\|BindPaths=${state_dir}:/var/lib/mita' "$SCRIPT"; then
  pass "systemd BindPaths metrics isolation"
else
  fail "missing systemd BindPaths"
fi
if grep -q 'unshare' "$SCRIPT" && grep -q 'mount --bind' "$SCRIPT"; then
  pass "OpenRC unshare+bind metrics isolation"
else
  fail "missing OpenRC metrics isolation"
fi

echo "=== H: fail-closed ==="
for needle in '需要 WARP 但未就绪（fail-closed）' '链式节点不存在: $routing（fail-closed）' '负载组不存在: $routing（fail-closed）'; do
  if grep -q "$needle" "$SCRIPT"; then pass "fail-closed: $needle"; else fail "missing $needle"; fi
done

echo "=== I: same-value no-op in UI ==="
if echo "$ui" | grep -q 'new_ob" == "\$cur_ob"'; then pass "same-value short-circuit"; else fail "no same-value check"; fi
if echo "$ui" | awk '/未变更/{p=1} p&&/continue/{ok=1} p&&/_regenerate_proxy_configs/{if(!ok){bad=1}} END{exit bad||!ok}'; then
  pass "same-value continues before regen"
else
  fail "same-value does not continue before regen"
fi

echo "=== J: smart_apply per-instance ==="
if grep -q '_smart_apply_mieru_instances' "$SCRIPT"; then pass "smart_apply_mieru_instances wired"; else fail "missing smart apply loop"; fi
if awk '/^_regenerate_proxy_configs\(\)/{f=1} f{print} /^\}$/{if(f&&++c==1) exit}' "$SCRIPT" | grep -q '_smart_apply_mieru_instances'; then
  pass "regen hint mieru → per-instance"
else
  fail "regen still single-file apply"
fi
if awk '/^_regenerate_proxy_configs\(\)/{f=1} f{print} /^\}$/{if(f&&++c==1) exit}' "$SCRIPT" | grep -q 'CFG/mieru.json.*vless-mieru'; then
  fail "regen still uses legacy single mieru.json"
else
  pass "no legacy single-file smart_apply"
fi

echo "=== K: portRange = one process (no per-port spawn inside range) ==="
# generate loops db_list_ports keys; slug from full key including range
if grep -A5 '_mieru_instance_slug' "$SCRIPT" | grep -q 'sed'; then pass "slug from full key"; else fail "slug helper"; fi
# Must NOT expand portRange into individual ports for service creation
if grep -n 'create_mieru_instance_service\|generate_mieru_config' "$SCRIPT" | head -5 >/dev/null; then
  # ensure no loop that splits ranges like {start..end} for mita spawn
  if grep -E 'for .* in \{\$[a-z_]+-\$[a-z_]+\}\|seq .*port_range' "$SCRIPT" | grep -i mieru; then
    fail "possible per-port spawn inside range"
  else
    pass "no per-port spawn inside portRange"
  fi
fi

echo "=== L: two-instance isolation naming ==="
# svc name and config path differ by slug
grep -q 'vless-mieru-\${slug}\|vless-mieru-${slug}' "$SCRIPT" && \
  grep -q 'mieru/\${slug}.json\|mieru/${slug}.json' "$SCRIPT" && \
  pass "distinct config+svc per slug" || fail "isolation naming"

echo "=== M: migration symbol present (DA) ==="
grep -q '^db_migrate_mieru_service_outbound_to_instances()' "$SCRIPT" && pass "migrate symbol" || fail "migrate missing"

echo "=== N: no manual svc restart in manage_instance_outbound ==="
if echo "$ui" | grep -qE 'svc (restart|stop|start) '; then
  fail "manual svc in manage_instance_outbound"
else
  pass "no manual svc in UI (uses regenerate)"
fi

echo "=== O: inherit via empty instance_outbound (db_set inherit→clear) ==="
if grep -A12 '^db_set_instance_outbound()' "$SCRIPT" | grep -q 'inherit'; then pass "inherit→clear"; else fail "inherit not cleared"; fi

echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
