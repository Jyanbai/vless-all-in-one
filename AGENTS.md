# Agent notes (vless-all-in-one)

## Scope
- Fat installer: `vless-server.sh` (table-driven, mozisen/surge style). Prefer porting named upstream hunks; do not redesign.
- Companion: `nft.sh`. Docs: `README.md` / `README_CN.md` (keep minimal).

## Version sync (CI blocking)
- `readonly VERSION="…"` in `vless-server.sh` must match:
  - `Current script version: **v…**` in `README.md`
  - `当前脚本版本：**v…**` in `README_CN.md`
- Workflow: `.github/workflows/shell-check.yml` (`bash -n` + `VERSION_SYNC`).

## v3.5.26 product notes (docs surface)
- **Remove SSH Tunnel** from supported product surface (select menu, STANDALONE/PROTO tables, install/create). No new `ssh-tunnel` DB writes (`db_add`/`db_add_port`/`db_update_port` reject).
- Legacy: opt-in `cleanup_legacy_ssh_tunnel` only — schema-lock snapshot → DB delete → scoped drop-in + `$CFG/ssh-tunnel`; proven-ownership `userdel`; never stop/disable system `sshd`.
- Local matrix: `tests/test_remove_ssh_tunnel.sh`.

## v3.5.25 product notes (docs surface)
- **Mieru service outbound (NOT per-port):** one service-wide egress for the whole mieru service (`db.json` → `xray.mieru` instances/portBindings → one `mieru.json` → one `vless-mieru`/`mita`).
- DB: `.service_outbound.mieru` via `db_get/set/clear_service_outbound_mieru`. Vocab: empty/missing = inherit | `direct` | `warp` | `chain:<n>` | `balancer:<n>`. Never persist literal `inherit`.
- Semantics: explicit service outbound > global `routing_rules` > default direct. inherit = exact v3.5.24 `_mieru_compile_egress_plan` path. Fail-closed on missing chain/balancer/warp (no silent DIRECT for those).
- UI: `manage_instance_outbound` keeps Xray per-port rows; if `db_exists xray/mieru` show one row「Mieru（全部实例）」 / status「Mieru 服务: 全部实例 → …」— never list every port/portRange.
- Apply: prefer `_regenerate_proxy_configs all` (bridge may move); no manual `vless-mieru`/`xray` restart. Same-value select → no DB/regen/restart. Chain/balancer delete/rename guards Mieru service refs.
- Local matrix: `tests/test_mieru_service_outbound.sh` (A–M) + regression `tests/test_smart_apply.sh`.

## v3.5.24 product notes (docs surface)
- **smart-apply:** `_regenerate_proxy_configs [xray|singbox|mieru|all]` — candidate→validate→diff→restart only if changed; snap restore fail-closed (`restore_fail:`, never false `skip_restart`). `configure_direct_outbound` writes `$CFG/direct_ip_version` then calls it (no private stop→gen→start). Kill-switch `VLESS_SMART_APPLY=0` (always restart after gen). Count: `VLESS_COUNT_REGEN=1` → `VLESS_REGEN_LOG` (default `/tmp/vless-regen.count`) lines `restart:` / `skip_restart:` / `validate_fail:` / `restore_fail:`.
- Local matrix: `tests/test_smart_apply.sh` (A–K) / `./vless-server.sh --smart-apply-selftest`.

## v3.5.23 product notes (docs surface)
- **instance_outbound (Xray shared-core only):** per-port field; absent/empty = inherit global (never store literal `inherit`); vocab `direct|warp|chain:…|balancer:…`.
- Menu `9) 实例出口管理`; install prompt only when routing is meaningfully configured; same-port replace preserves the field.
- Emit `inboundTag` rules as user → instance → global (API rule prepended). Multi-IP: base tag + `ip-in-*-$port` clones get the instance override; more-specific multi-IP rules stay higher.
- Fail-closed on missing chain/WARP/balancer targets (no silent DIRECT). Deleting a referenced chain/balancer asks to clear refs → inherit (never auto-DIRECT).
- Not on mieru / standalone / Snell / Naive / SSH-Tunnel engine path. Sing-box per-inbound detour needs inbound matchers — follow-up, not this patch.
- Local matrix: `tests/test_instance_outbound.sh`.

## v3.5.20 product notes (docs surface)
- **mieru:** TCP|UDP; exclusive `port` or `port_range`; Traffic Pattern Advanced default off (UI Off/Conservative/Custom → store `off`/`conservative`/`unlocked`); `mierus://`; no port→user ACL; runtime-only `trafficPattern` object (not in db.json).
- **SSH Tunnel:** system OpenSSH only; Match Group; key-only; client TCP `-N -L/-D/-R`; no shell/exec/TTY/SFTP; no native UDP; no `ssh://` URI; keys on disk `0600` via `authorized_keys_path` only (never raw keys in db.json); candidate → `sshd -t/-T` → reload → admin verify → commit else rollback.

## Do not
- Force-push / FF `main` from feature work unless explicitly ordered.
- Store SSH private/public key material in `db.json`.
