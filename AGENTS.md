# Agent notes (vless-all-in-one)

## Scope
- Fat installer: `vless-server.sh` (table-driven, mozisen/surge style). Prefer porting named upstream hunks; do not redesign.
- Companion: `nft.sh`. Docs: `README.md` / `README_CN.md` (keep minimal).

## Version sync (CI blocking)
- `readonly VERSION="…"` in `vless-server.sh` must match:
  - `Current script version: **v…**` in `README.md`
  - `当前脚本版本：**v…**` in `README_CN.md`
- Workflow: `.github/workflows/shell-check.yml` (`bash -n` + `VERSION_SYNC`).

## v3.5.24 product notes (docs surface)
- **smart-apply:** `_regenerate_proxy_configs [xray|singbox|mieru|all]` — candidate→validate→diff→restart only if changed; `configure_direct_outbound` uses it (no stop→gen→start). Kill-switch `VLESS_SMART_APPLY=0`. Count log: `VLESS_COUNT_REGEN=1` → `restart:` / `skip_restart:` / `validate_fail:`.
- Local matrix: `tests/test_smart_apply.sh` / `./vless-server.sh --smart-apply-selftest`.

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
