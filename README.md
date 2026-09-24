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
- **v3.5.26:** remove **SSH Tunnel** from product surface (select/install/create). Legacy installs: opt-in `cleanup_legacy_ssh_tunnel` only (detect → confirm → scoped cleanup); never stop/disable system sshd
- **v3.5.21:** deferred/batched regen when adding chain nodes (unused = DB-only; add+route ≤1 regen); custom routing token parser for mixed geosite/domain/IP (Xray + Sing-box)
- **v3.5.22:** Mieru fallback path uses the same routing token helpers (fixes mixed custom rules breaking Xray)
- **v3.5.23:** per-instance Xray outbound (`instance_outbound`); menu 实例出口管理; inherit global by default; priority user > instance > global; Xray shared-core only
- **Smart apply (v3.5.24):** regenerating proxy configs validates first, then restarts Xray / Sing-box / mieru only when the live config actually changed (`VLESS_SMART_APPLY=0` restores always-restart)
- **v3.5.25:** Mieru **service-wide** outbound (not per-port) in 实例出口管理 as one row「Mieru（全部实例）」; DB `.service_outbound.mieru`; empty/missing=inherit global; priority service override > global > default; fail-closed; smart-apply via `_regenerate_proxy_configs all`

## Quick Install

```bash
wget -O vless-server.sh https://raw.githubusercontent.com/Jyanbai/vless-all-in-one/main/vless-server.sh && chmod +x vless-server.sh && ./vless-server.sh
```

Current script version: **v3.5.26**

## Sing-box custom build for traffic stats

Starting from **v3.5.3**, Sing-box user traffic statistics for **Hysteria2 / TUIC / AnyTLS** require a custom Sing-box build with `with_v2ray_api` enabled.

The default upstream Sing-box binary usually does **not** include this capability.

For users who need Sing-box traffic sync / quota / expiry workflows, download the custom Sing-box asset attached to the corresponding GitHub Release and replace your current `/usr/local/bin/sing-box` binary.

A step-by-step installation note is provided in the release asset:

- `README-sing-box-with-v2ray-api.md`

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Jyanbai/vless-all-in-one&type=Date)](https://www.star-history.com/#Jyanbai/vless-all-in-one&Date)
