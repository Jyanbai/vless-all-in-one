# 更新日志

[English](./CHANGELOG.md) | [简体中文](./CHANGELOG_CN.md)

版本条目从 README_CN.md 原样迁移。历史开发说明保留原文，见 [英文更新日志](./CHANGELOG.md) 的对应版本。

## v3.5.31

- **v3.5.31：** 修复安装与隧道删除的错误处理、节点计数，清理无用代码，并将回归测试纳入 CI。

## v3.5.30

- **v3.5.30：**
  - 实例出口（「实例出口管理」、安装与管理、Xray 与 Mieru）简化为 继承 / 直连 / WARP / 链式 / 负载均衡
  - 旧版本已有的分流规则仅作为兼容保留：原样保留、可继续使用或切换掉
  - 修复缺少 `jq` 时全新安装启动失败（现在会先安装 `jq` 再读写数据库）
  - 干净系统启动时不再初始化旧分流数据

## v3.5.29

- **v3.5.29：** 「实例出口管理」列出 Mieru（含状态列表；绝不把 mieru 加入 XRAY_PROTOCOLS）。自更新以配置的 `SCRIPT_SOURCE_REPO`/`REF`/`PATH` 为准（手动「脚本更新」忽略 1h 缓存；不以过期 tag/release 盖住源分支 VERSION）。本版的分流选择改动 **已被 v3.5.30 取代**

## v3.5.28

- **v3.5.28：** 实例级分流选择 — **已被 v3.5.30 取代**（仅作旧版兼容保留）

## v3.5.27

- **v3.5.27：** Mieru **实例级**运行时与出口 — 每个 port/`portRange` = 一个 mita（独立 JSON/UDS/unit/metrics，状态目录 `/var/lib/vless-mieru/<slug>`）；库字段 `.xray.mieru[].instance_outbound`（缺省/空=继承；从不写入字面量 `inherit`）；最终模型 **无** `.service_outbound.mieru`（菜单启动时 fail-closed 迁移）；「实例出口管理」按端口列出 mieru（无「Mieru（全部实例）」）

## v3.5.26

- **v3.5.26：** 从产品面移除 **SSH Tunnel**（选择/安装/创建）；仅保留可选遗留清理（`cleanup_legacy_ssh_tunnel`）；永不 stop/disable 系统 sshd

## v3.5.25

- **v3.5.25：** Mieru 服务级出口（`.service_outbound.mieru` +「Mieru（全部实例）」）— **已被 v3.5.27 取代**

## v3.5.24

- **智能应用（v3.5.24）：** 重新生成代理配置时先校验，仅在 live 配置确有变化时才重启 Xray / Sing-box / mieru（`VLESS_SMART_APPLY=0` 恢复为每次生成后都重启）

## v3.5.23

- **v3.5.23：** 实例级 Xray 出口（`instance_outbound`）；菜单「实例出口管理」；默认继承全局；优先级 用户 > 实例 > 全局；仅 Xray 共享核心

## v3.5.22

- **v3.5.22：** Mieru 回退路径复用同一套路由 token helpers（修复混合自定义规则导致 Xray 异常）

## v3.5.21

- **v3.5.21：** 添加链式节点时延迟/批量 regenerate（未使用仅写库；添加+路由 ≤1 次 regen）；自定义路由 token 解析器，支持混合 geosite/域名/IP（Xray + Sing-box）

## v3.5.20

- **mieru**（v3.5.20）：TCP/UDP、`port`/`portRange`、流量模式默认关闭；官方 `mierus://` 分享链接
