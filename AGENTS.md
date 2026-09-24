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

## v3.5.27 product notes (docs surface)
- **Mieru per-instance runtime + outbound:** one DB row (port OR portRange) = one mita = own JSON/UDS/unit/outbound/metrics state. portRange is ONE logical instance.
- Layout: `$CFG/mieru/<slug>.json`, UDS `/run/mita/<slug>/mita.sock`, unit `vless-mieru-<slug>`, state `/var/lib/vless-mieru/<slug>` bind-mounted over `/var/lib/mita` (metrics.pb hardcoded — systemd `BindPaths=` / OpenRC `unshare -m`+bind).
- DB: `.xray.mieru[].instance_outbound` via `db_get/set/clear_instance_outbound xray mieru <port|range>`; empty/missing = inherit (never store literal `inherit`). FINAL model has NO `.service_outbound.mieru` (DA migrate: `db_migrate_mieru_service_outbound_to_instances`).
- Compile: `_mieru_compile_egress_plan <key>` reads instance_outbound only (not service getter). Fail-closed on missing warp/chain/balancer.
- UI: `manage_instance_outbound` lists mieru like Xray via `db_list_ports` — no「Mieru（全部实例）」. Same-value → no regen. smart_apply restarts only changed instances.
- Local matrix: `tests/test_mieru_per_instance.sh` + `tests/test_mieru_instance_outbound_migrate.sh` + `tests/test_smart_apply.sh`.

## v3.5.25 product notes (superseded by 3.5.27)
- Was: one service-wide Mieru egress (`.service_outbound.mieru` + single `mieru.json`/`vless-mieru`). Replaced by per-instance model above.

## v3.5.24 product notes (docs surface)
- **smart-apply:** `_regenerate_proxy_configs [xray|singbox|mieru|all]` — candidate→validate→diff→restart only if changed; snap restore fail-closed (`restore_fail:`, never false `skip_restart`). `configure_direct_outbound` writes `$CFG/direct_ip_version` then calls it (no private stop→gen→start). Kill-switch `VLESS_SMART_APPLY=0` (always restart after gen). Count: `VLESS_COUNT_REGEN=1` → `VLESS_REGEN_LOG` (default `/tmp/vless-regen.count`) lines `restart:` / `skip_restart:` / `validate_fail:` / `restore_fail:`.
- Local matrix: `tests/test_smart_apply.sh` (A–K) / `./vless-server.sh --smart-apply-selftest`.

## v3.5.23 product notes (docs surface)
- **instance_outbound (Xray shared-core only):** per-port field; absent/empty = inherit global (never store literal `inherit`); vocab `direct|warp|chain:…|balancer:…`.
- Menu `9) 实例出口管理`; install prompt only when routing is meaningfully configured; same-port replace preserves the field.
- Emit `inboundTag` rules as user → instance → global (API rule prepended). Multi-IP: base tag + `ip-in-*-$port` clones get the instance override; more-specific multi-IP rules stay higher.
- Fail-closed on missing chain/WARP/balancer targets (no silent DIRECT). Deleting a referenced chain/balancer asks to clear refs → inherit (never auto-DIRECT).
- Not on Xray-inboundTag path for mieru (mieru uses own instance_outbound as of 3.5.27); not on standalone / Snell / Naive / SSH-Tunnel engine path. Sing-box per-inbound detour needs inbound matchers — follow-up, not this patch.
- Local matrix: `tests/test_instance_outbound.sh`.

## v3.5.20 product notes (docs surface)
- **mieru:** TCP|UDP; exclusive `port` or `port_range`; Traffic Pattern Advanced default off (UI Off/Conservative/Custom → store `off`/`conservative`/`unlocked`); `mierus://`; no port→user ACL; runtime-only `trafficPattern` object (not in db.json).
- **SSH Tunnel:** system OpenSSH only; Match Group; key-only; client TCP `-N -L/-D/-R`; no shell/exec/TTY/SFTP; no native UDP; no `ssh://` URI; keys on disk `0600` via `authorized_keys_path` only (never raw keys in db.json); candidate → `sshd -t/-T` → reload → admin verify → commit else rollback.

## Do not
- Force-push / FF `main` from feature work unless explicitly ordered.
- Store SSH private/public key material in `db.json`.
