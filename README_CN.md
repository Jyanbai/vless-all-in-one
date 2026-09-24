# vless-all-in-one

[English](./README.md) | [简体中文](./README_CN.md)

Linux 服务器一体化代理部署脚本。

它可以帮助你快速部署和管理多种协议，包括 **VLESS**、**VMess**、**Trojan**、**Hysteria2**、**TUIC**、**NaiveProxy**、**Snell**、**SOCKS5**、**SS2022**、**VLESS Encryption + FinalMask (Sudoku)**、**mieru**。

## 功能特性

- 一键安装与管理
- 支持多协议共存部署
- 适配 Debian、Ubuntu、CentOS 和 Alpine
- 基于 Xray + Sing-box 双核心架构
- 提供用户管理、路由、订阅与故障排查文档
- **mieru**（v3.5.20）：TCP/UDP、`port`/`portRange`、流量模式默认关闭；官方 `mierus://` 分享链接
- **v3.5.26：** 从产品面移除 **SSH Tunnel**（选择/安装/创建）；仅保留可选遗留清理（`cleanup_legacy_ssh_tunnel`）；永不 stop/disable 系统 sshd
- **v3.5.28：** 实例级**分流规则集**（`profile:<id>`）— 内置 `ai_media` / `finance_crypto` / `telegram_dc`（matchers + Telegram 回退；禁止伪造 `geoip:telegram`）；菜单「分流规则集」；「家宽+直出备用」向导；共享规则集 smart-apply
- **v3.5.27：** Mieru **实例级**运行时与出口 — 每个 port/`portRange` = 一个 mita（独立 JSON/UDS/unit/metrics，状态目录 `/var/lib/vless-mieru/<slug>`）；库字段 `.xray.mieru[].instance_outbound`（缺省/空=继承；从不写入字面量 `inherit`）；最终模型 **无** `.service_outbound.mieru`（菜单启动时 fail-closed 迁移）；「实例出口管理」按端口列出 mieru（无「Mieru（全部实例）」）
- **v3.5.21：** 添加链式节点时延迟/批量 regenerate（未使用仅写库；添加+路由 ≤1 次 regen）；自定义路由 token 解析器，支持混合 geosite/域名/IP（Xray + Sing-box）
- **v3.5.22：** Mieru 回退路径复用同一套路由 token helpers（修复混合自定义规则导致 Xray 异常）
- **v3.5.23：** 实例级 Xray 出口（`instance_outbound`）；菜单「实例出口管理」；默认继承全局；优先级 用户 > 实例 > 全局；仅 Xray 共享核心
- **智能应用（v3.5.24）：** 重新生成代理配置时先校验，仅在 live 配置确有变化时才重启 Xray / Sing-box / mieru（`VLESS_SMART_APPLY=0` 恢复为每次生成后都重启）
- **v3.5.25：** Mieru 服务级出口（`.service_outbound.mieru` +「Mieru（全部实例）」）— **已被 v3.5.27 取代**

## 快速安装

```bash
wget -O vless-server.sh https://raw.githubusercontent.com/Jyanbai/vless-all-in-one/main/vless-server.sh && chmod +x vless-server.sh && ./vless-server.sh
```

当前脚本版本：**v3.5.28**

## 用于流量统计的自定义 Sing-box 构建

从 **v3.5.3** 开始，**Hysteria2 / TUIC / AnyTLS** 的用户流量统计功能需要启用 `with_v2ray_api` 的自定义 Sing-box 构建。

默认的上游 Sing-box 二进制通常 **不包含** 此能力。

如果你需要使用 Sing-box 的流量同步 / 配额 / 到期等功能，请下载对应 GitHub Release 附件中的自定义 Sing-box，并替换当前的 `/usr/local/bin/sing-box`。

Release 附件中已提供安装说明：

- `README-sing-box-with-v2ray-api.md`

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Jyanbai/vless-all-in-one&type=Date)](https://www.star-history.com/#Jyanbai/vless-all-in-one&Date)
