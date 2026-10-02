# vless-all-in-one

[English](./README.md) | [简体中文](./README_CN.md)

## 简介

这是一个面向 Linux 服务器的一体化代理部署脚本，基于 Zyx0rx 的原作和 mozisen/surge 的维护版。目前处于维护模式：只修复 bug、加固测试，不增加新功能。

## 支持的协议

支持 **VLESS**、**VMess**、**Trojan**、**Hysteria2**、**TUIC**、**NaiveProxy**、**Snell**、**SOCKS5**、**SS2022**、**VLESS Encryption + FinalMask (Sudoku)** 和 **mieru**。

## 支持的系统

适配 Debian、Ubuntu、CentOS 和 Alpine。

## 快速安装

请使用 root 身份运行以下命令：

```bash
wget -O vless-server.sh https://raw.githubusercontent.com/Jyanbai/vless-all-in-one/main/vless-server.sh && chmod +x vless-server.sh && ./vless-server.sh
```

当前脚本版本：**v3.5.31**

## nftables 端口转发

可以从主菜单 `10) 端口转发` 进入，再选择 `2) nftables 转发`。

也可以单独下载本仓库的脚本并以 root 身份运行：

```bash
wget -O nft.sh https://raw.githubusercontent.com/Jyanbai/vless-all-in-one/main/nft.sh && chmod +x nft.sh && ./nft.sh
```

安装后的快捷命令是 `nftm`。本仓库的 `nft.sh` 与上游保持一致。

## 已知限制

Hysteria2 / TUIC / AnyTLS 的用户流量统计需要带 `with_v2ray_api` 的 Sing-box 构建。本仓库目前不提供这样的构建。

## 版本说明

本仓库的 3.5.x 是独立的版本线，与上游 3.6 或 3.7 没有对应关系。

## 更新日志

请参阅 [CHANGELOG_CN.md](./CHANGELOG_CN.md)。

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Jyanbai/vless-all-in-one&type=Date)](https://www.star-history.com/#Jyanbai/vless-all-in-one&Date)
