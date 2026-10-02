# Changelog

[English](./CHANGELOG.md) | [简体中文](./CHANGELOG_CN.md)

Version entries are preserved verbatim from README.md. Archived development notes describe the indicated past version.

## v3.5.31

- **v3.5.31:** Fix installation and tunnel deletion error handling, correct node counts, remove unused code, and run regression tests in CI.

## v3.5.30

- **v3.5.30:**
  - Instance outbound (实例出口管理, install and manage, Xray and Mieru) is simplified to inherit / direct / WARP / chain / balancer
  - Existing routing rules from older versions keep working as legacy compatibility only; they are kept as-is and can be left in place or switched off
  - Fixed fresh installs failing at startup when `jq` is missing (`jq` is now installed before the database is touched)
  - Clean systems no longer initialize old routing data at startup

## v3.5.29

- **v3.5.29:** Mieru rows in 实例出口管理 (+ status list; never add mieru to XRAY_PROTOCOLS). Self-updater SoT: configured `SCRIPT_SOURCE_REPO`/`REF`/`PATH` (manual 脚本更新 ignores 1h cache; not stale tag/release). Routing-choice changes in this release are **superseded by v3.5.30**

### Archived development notes

- **NEW surface — only via `9) 实例出口管理` picker:** inherit / direct / WARP / chain / balancer / 家宽 / 直出备用 / 配置重建 wizard. Stable ASCII ids `home` / `direct_backup` (`instance_outbound` stores `profile:home` | `profile:direct_backup`; no nested `profile:*`). Chinese names are UI-only — never emphasize internal ids in user-facing docs.
- **Wizard:** upserts BOTH `home` + `direct_backup` (finance+TG same on both; AI JP on home / DIRECT on direct_backup).

## v3.5.28

- **v3.5.28:** Per-instance routing choices — **superseded by v3.5.30** (kept only as legacy compatibility)

### Archived development notes

- **Built-ins** (`db_ensure_routing_profiles_defaults`): originally seeded once `finance_crypto` → `telegram_dc` → `ai_media` as profiles (finance/TG above AI/media for wizard/combined). **v3.5.29:** those packs are templates (matchers-only); wizard profiles are only `home` + `direct_backup`. Top-level UI「分流规则集」**withdrawn** — picker surface is `9) 实例出口管理` (家宽 / 直出备用 / 配置重建 wizard); shared-profile edit backend still goes through validate/apply + smart-apply.
- **Helpers:** `db_list/get/add/update/delete/copy_routing_profile`, rule helpers, `db_get/set/seed_telegram_dc_matchers*`, `db_ensure_routing_profiles_defaults`.

## v3.5.27

- **v3.5.27:** Mieru **per-instance** runtime + outbound — each port/`portRange` = one mita (own JSON/UDS/unit/metrics under `/var/lib/vless-mieru/<slug>`); DB `.xray.mieru[].instance_outbound` (empty/missing=inherit; never store `inherit`); **no** `.service_outbound.mieru` in final model (fail-closed migrate on menu start); 实例出口管理 lists mieru like Xray (no「Mieru（全部实例）」)

## v3.5.26

- **v3.5.26:** remove **SSH Tunnel** from product surface (select/install/create); opt-in legacy cleanup only (`cleanup_legacy_ssh_tunnel`); never stop/disable system sshd

## v3.5.25

- **v3.5.25:** Mieru service-wide outbound (`.service_outbound.mieru` +「Mieru（全部实例）」) — **superseded by v3.5.27**

## v3.5.24

- **Smart apply (v3.5.24):** regenerating proxy configs validates first, then restarts Xray / Sing-box / mieru only when the live config actually changed (`VLESS_SMART_APPLY=0` restores always-restart)

## v3.5.23

- **v3.5.23:** per-instance Xray outbound (`instance_outbound`); menu 实例出口管理; inherit global by default; priority user > instance > global; Xray shared-core only

## v3.5.22

- **v3.5.22:** Mieru fallback path uses the same routing token helpers (fixes mixed custom rules breaking Xray)

## v3.5.21

- **v3.5.21:** deferred/batched regen when adding chain nodes (unused = DB-only; add+route ≤1 regen); custom routing token parser for mixed geosite/domain/IP (Xray + Sing-box)

## v3.5.20

- **mieru** (v3.5.20): TCP/UDP, `port`/`portRange`, Traffic Pattern default Off; official `mierus://` links

### Archived development notes

- **SSH Tunnel:** system OpenSSH only; Match Group; key-only; client TCP `-N -L/-D/-R`; no shell/exec/TTY/SFTP; no native UDP; no `ssh://` URI; keys on disk `0600` via `authorized_keys_path` only (never raw keys in db.json); candidate → `sshd -t/-T` → reload → admin verify → commit else rollback.
