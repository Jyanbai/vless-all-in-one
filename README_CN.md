# vless-all-in-one

[English](./README.md) | [简体中文](./README_CN.md)

Linux 服务器一体化代理部署脚本。

它可以帮助你快速部署和管理多种协议，包括 **VLESS**、**VMess**、**Trojan**、**Hysteria2**、**TUIC**、**NaiveProxy**、**Snell**、**SOCKS5** 和 **SS2022**。

## 文档

- **网站文档：** https://docs.vaiox.de/
- **Telegram 群组：** https://t.me/vless_vaio
- **Telegram 频道：** https://t.me/vaio_channel

## 功能特性

- 一键安装与管理
- 支持多协议共存部署
- 适配 Debian、Ubuntu、CentOS 和 Alpine
- 基于 Xray + Sing-box 双核心架构
- 提供用户管理、路由、订阅与故障排查文档

## 快速安装

```bash
wget -O vless-server.sh https://raw.githubusercontent.com/Jyanbai/vless-all-in-one/main/vless-server.sh && chmod +x vless-server.sh && ./vless-server.sh
```

## 文档入口

- [网站文档](https://docs.vaiox.de/)

## 用于流量统计的自定义 Sing-box 构建

从 **v3.5.3** 开始，**Hysteria2 / TUIC / AnyTLS** 的用户流量统计功能需要启用 `with_v2ray_api` 的自定义 Sing-box 构建。

默认的上游 Sing-box 二进制通常 **不包含** 此能力。

如果你需要使用 Sing-box 的流量同步 / 配额 / 到期等功能，请下载对应 GitHub Release 附件中的自定义 Sing-box，并替换当前的 `/usr/local/bin/sing-box`。

Release 附件中已提供安装说明：

- `README-sing-box-with-v2ray-api.md`

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Jyanbai/vless-all-in-one&type=Date)](https://www.star-history.com/#Jyanbai/vless-all-in-one&Date)
