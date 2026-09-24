# Agent notes (vless-all-in-one)

## Scope
- Fat installer: `vless-server.sh` (table-driven, mozisen/surge style). Prefer porting named upstream hunks; do not redesign.
- Companion: `nft.sh`. Docs: `README.md` / `README_CN.md` (keep minimal).

## Version sync (CI blocking)
- `readonly VERSION="…"` in `vless-server.sh` must match:
  - `Current script version: **v…**` in `README.md`
  - `当前脚本版本：**v…**` in `README_CN.md`
- Workflow: `.github/workflows/shell-check.yml` (`bash -n` + `VERSION_SYNC`).

## v3.5.29 product notes (docs surface)
- **Mieru in 实例出口管理:** `manage_instance_outbound` lists mieru after the Xray loop via `db_exists`/`db_list_ports` (xray + mieru). NEVER add mieru to `XRAY_PROTOCOLS`. One `portRange` row = one listed instance.
- **Templates vs profiles:** Templates = matchers-only packs. Wizard creates TWO profiles only: `home`/家宽 + `direct_backup`/直出备用 (Chinese names UI-only; stable ASCII ids). `instance_outbound` stores `profile:home` | `profile:direct_backup`; no nested `profile:*`. Migrate seed/legacy `home_broadband`. Remove duplicate routing menu #11. DA helpers for templates + migration. Stop auto-seeding `finance_crypto`/`telegram_dc`/`ai_media` as profiles (those stay templates).
- **Self-updater SoT:** configured `SCRIPT_SOURCE_REPO`/`REF`/`PATH`. Manual「脚本更新」ignores 1h cache; cache-bust raw fetch; keep blob SHA + `bash -n`. Tag/release must not mask a newer source-ref `VERSION`.
- **VERSION sync:** `3.5.29` in `vless-server.sh` + both READMEs.

## v3.5.28 product notes (docs surface)
- **Per-instance routing profiles:** DB `.routing_profiles[]` — stable `id`, editable `name`, ordered `rules[]`, `fallback` always `"inherit"` (unmatched traffic continues to global routing; never a profile catch-all DIRECT). Missing keys on old DBs ⇒ identical to 3.5.27 (no migrate).
- **`instance_outbound` vocab (extends 3.5.23):** `direct` | `warp` | `chain:…` | `balancer:…` | `profile:<stable_id>`. Empty/missing = inherit global (never store literal `inherit`). Missing `profile:<id>` fail-closed.
- **inherit vs direct vs chain vs profile:**
  - **inherit** (empty field): use global routing only.
  - **direct / warp / chain / balancer:** single outbound override for that inbound (same as 3.5.23).
  - **profile:<id>:** expand the named rule set in order onto that instance’s inboundTag scope (Xray) or per-instance Mieru egress plan — not a service-wide Mieru switch.
- **Compile:** Xray `_gen_xray_profile_inbound_rules` — inboundTag-scoped, preserve rule order (DIRECT does not reorder), no catch-all → inherit global. Mieru `_mieru_expand_profile_rules` inside `_mieru_compile_egress_plan` only (per-instance). Chain/balancer/WARP guards include profile refs; delete profile refused while in use (`db_list_instances_using_profile`).
- **Telegram DC (Choice A):** `.telegram_dc_matchers` versioned best-effort known-endpoint seed (IPv4/IPv6) — NOT a full CIDR DB / not permanent. Rule `type=telegram_dc` expands matchers; misses use Telegram fallback (`geosite:telegram` in built-in). **Forbidden in profiles:** fake `geoip:telegram`.
- **Built-ins** (`db_ensure_routing_profiles_defaults`): originally seeded once `finance_crypto` → `telegram_dc` → `ai_media` as profiles (finance/TG above AI/media for wizard/combined). **v3.5.29:** those packs are templates (matchers-only); wizard profiles are only `home` + `direct_backup`. UI「分流规则集」; wizard「家宽 + 直出备用」; shared-profile edit goes through validate/apply + smart-apply.
- **Helpers:** `db_list/get/add/update/delete/copy_routing_profile`, rule helpers, `db_get/set/seed_telegram_dc_matchers*`, `db_ensure_routing_profiles_defaults`.
- Local matrix: `tests/test_instance_routing_profiles.sh` (A–AB) + regressions (smart_apply, instance_outbound, mieru_per_instance, mieru_migrate, finalmask, remove_ssh, bash -n).

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
- **instance_outbound (Xray shared-core only):** per-port field; absent/empty = inherit global (never store literal `inherit`); vocab `direct|warp|chain:…|balancer:…` (v3.5.28 adds `profile:<id>` — see above).
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
