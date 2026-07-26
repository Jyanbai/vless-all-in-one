# vless-all-in-one

[English](./README.md) | [简体中文](./README_CN.md)

An all-in-one proxy deployment script for Linux servers.

It helps you quickly deploy and manage multiple protocols in one place, including **VLESS**, **VMess**, **Trojan**, **Hysteria2**, **TUIC**, **NaiveProxy**, **Snell**, **SOCKS5**, and **SS2022**.

## Documentation

- **Website:** https://docs.vaiox.de/
- **Telegram Group:** https://t.me/vless_vaio
- **Telegram Channel:** https://t.me/vaio_channel

## Features

- One-click installation and management
- Supports multiple protocols on the same server
- Built for Debian, Ubuntu, CentOS, and Alpine
- Xray + Sing-box dual-core architecture
- User management, routing, subscriptions, and troubleshooting docs

## Quick Install

```bash
wget -O vless-server.sh https://raw.githubusercontent.com/Jyanbai/vless-all-in-one/main/vless-server.sh && chmod +x vless-server.sh && ./vless-server.sh
```

## Documents

- [Website Docs](https://docs.vaiox.de/)

## Sing-box custom build for traffic stats

Starting from **v3.5.3**, Sing-box user traffic statistics for **Hysteria2 / TUIC / AnyTLS** require a custom Sing-box build with `with_v2ray_api` enabled.

The default upstream Sing-box binary usually does **not** include this capability.

For users who need Sing-box traffic sync / quota / expiry workflows, download the custom Sing-box asset attached to the corresponding GitHub Release and replace your current `/usr/local/bin/sing-box` binary.

A step-by-step installation note is provided in the release asset:

- `README-sing-box-with-v2ray-api.md`

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Jyanbai/vless-all-in-one&type=Date)](https://www.star-history.com/#Jyanbai/vless-all-in-one&Date)
