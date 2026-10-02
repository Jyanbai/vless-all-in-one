# vless-all-in-one

[English](./README.md) | [简体中文](./README_CN.md)

## Introduction

This is an all-in-one proxy deployment script for Linux servers, based on Zyx0rx's original work and the mozisen/surge maintenance version. It is currently in maintenance mode: only bug fixes and stronger tests are planned; no new features are being added.

## Supported protocols

The supported protocols are **VLESS**, **VMess**, **Trojan**, **Hysteria2**, **TUIC**, **NaiveProxy**, **Snell**, **SOCKS5**, **SS2022**, **VLESS Encryption + FinalMask (Sudoku)**, and **mieru**.

## Supported systems

Built for Debian, Ubuntu, CentOS, and Alpine.

## Quick install

Run the following command as root:

```bash
wget -O vless-server.sh https://raw.githubusercontent.com/Jyanbai/vless-all-in-one/main/vless-server.sh && chmod +x vless-server.sh && ./vless-server.sh
```

Current script version: **v3.5.31**

## nftables port forwarding

You can open it from the main menu through `10) 端口转发` (Port forwarding) and then `2) nftables 转发` (nftables forwarding).

To run it separately, download this repository's script and run it as root:

```bash
wget -O nft.sh https://raw.githubusercontent.com/Jyanbai/vless-all-in-one/main/nft.sh && chmod +x nft.sh && ./nft.sh
```

The installed shortcut command is `nftm`. The repository's `nft.sh` is kept identical to upstream.

## Known limitations

User traffic statistics for Hysteria2 / TUIC / AnyTLS require a Sing-box build with `with_v2ray_api`. This repository does not provide such a build.

## Version notes

This repository's 3.5.x releases are an independent version line and have no correspondence with upstream 3.6 or 3.7.

## Changelog

See [CHANGELOG.md](./CHANGELOG.md).

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Jyanbai/vless-all-in-one&type=Date)](https://www.star-history.com/#Jyanbai/vless-all-in-one&Date)
