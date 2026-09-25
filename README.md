# vless-all-in-one

[English](./README.md) | [简体中文](./README_CN.md)

An all-in-one proxy deployment script for Linux servers.

It helps you quickly deploy and manage multiple protocols in one place, including **VLESS**, **VMess**, **Trojan**, **Hysteria2**, **TUIC**, **NaiveProxy**, **Snell**, **SOCKS5**, **SS2022**, **VLESS Encryption + FinalMask (Sudoku)**, **mieru**.

## Features

- One-click installation and management
- Supports multiple protocols on the same server
- Built for Debian, Ubuntu, CentOS, and Alpine
- Xray + Sing-box dual-core architecture
- User management, routing, subscriptions, and troubleshooting docs
- **mieru** (v3.5.20): TCP/UDP, `port`/`portRange`, Traffic Pattern default Off; official `mierus://` links
- **v3.5.26:** remove **SSH Tunnel** from product surface (select/install/create); opt-in legacy cleanup only (`cleanup_legacy_ssh_tunnel`); never stop/disable system sshd
- **v3.5.30:**
  - Instance outbound (实例出口管理, install and manage, Xray and Mieru) is simplified to inherit / direct / WARP / chain / balancer
  - Existing routing rules from older versions keep working as legacy compatibility only; they are kept as-is and can be left in place or switched off
  - Fixed fresh installs failing at startup when `jq` is missing (`jq` is now installed before the database is touched)
  - Clean systems no longer initialize old routing data at startup
- **v3.5.29:** Mieru rows in 实例出口管理 (+ status list; never add mieru to XRAY_PROTOCOLS). Self-updater SoT: configured `SCRIPT_SOURCE_REPO`/`REF`/`PATH` (manual 脚本更新 ignores 1h cache; not stale tag/release). Routing-choice changes in this release are **superseded by v3.5.30**
- **v3.5.28:** Per-instance routing choices — **superseded by v3.5.30** (kept only as legacy compatibility)
- **v3.5.27:** Mieru **per-instance** runtime + outbound — each port/`portRange` = one mita (own JSON/UDS/unit/metrics under `/var/lib/vless-mieru/<slug>`); DB `.xray.mieru[].instance_outbound` (empty/missing=inherit; never store `inherit`); **no** `.service_outbound.mieru` in final model (fail-closed migrate on menu start); 实例出口管理 lists mieru like Xray (no「Mieru（全部实例）」)
- **v3.5.21:** deferred/batched regen when adding chain nodes (unused = DB-only; add+route ≤1 regen); custom routing token parser for mixed geosite/domain/IP (Xray + Sing-box)
- **v3.5.22:** Mieru fallback path uses the same routing token helpers (fixes mixed custom rules breaking Xray)
- **v3.5.23:** per-instance Xray outbound (`instance_outbound`); menu 实例出口管理; inherit global by default; priority user > instance > global; Xray shared-core only
- **Smart apply (v3.5.24):** regenerating proxy configs validates first, then restarts Xray / Sing-box / mieru only when the live config actually changed (`VLESS_SMART_APPLY=0` restores always-restart)
- **v3.5.25:** Mieru service-wide outbound (`.service_outbound.mieru` +「Mieru（全部实例）」) — **superseded by v3.5.27**

## Quick Install

```bash
wget -O vless-server.sh https://raw.githubusercontent.com/Jyanbai/vless-all-in-one/main/vless-server.sh && chmod +x vless-server.sh && ./vless-server.sh
```

Current script version: **v3.5.30**

## Sing-box custom build for traffic stats

Starting from **v3.5.3**, Sing-box user traffic statistics for **Hysteria2 / TUIC / AnyTLS** require a custom Sing-box build with `with_v2ray_api` enabled.

The default upstream Sing-box binary usually does **not** include this capability.

For users who need Sing-box traffic sync / quota / expiry workflows, download the custom Sing-box asset attached to the corresponding GitHub Release and replace your current `/usr/local/bin/sing-box` binary.

A step-by-step installation note is provided in the release asset:

- `README-sing-box-with-v2ray-api.md`

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Jyanbai/vless-all-in-one&type=Date)](https://www.star-history.com/#Jyanbai/vless-all-in-one&Date)
