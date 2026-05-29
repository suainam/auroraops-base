# Role: vps.system.base

## 1. 概述
本角色负责系统的基础通用配置，包括时区、字符编码、NTP 时间同步、DNS 解析以及针对不同介质（SSD/NVMe/HDD）的 I/O 调度器持久化优化。

## 2. 变量说明 (Defaults)
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `system_timezone` | `Asia/Shanghai` | 系统时区设置。 |
| `system_locale` | `en_US.UTF-8` | 系统语言和字符编码设置。 |
| `ntp_servers` | `[0.debian.pool.ntp.org, ...]` | NTP 时间同步服务器列表（Debian Pool）。 |
| `dns_servers` | `[8.8.8.8, 1.1.1.1, ...]` | `/etc/resolv.conf` DNS 列表，默认混合 Google 与 Cloudflare 以提高可用性。 |

## 3. 内部逻辑
- **本地化**: 设置时区和生成指定的 locale。
- **时间同步**: 安装并启动 `systemd-timesyncd`，并配置 NTP 同步源。
- **DNS 配置**: 通过模板生成 `/etc/resolv.conf`。
- **服务优化**: 禁用非必要的 `exim4` (MTA) 和 `packagekit` 服务以节省资源。
- **性能优化 (I/O)**:
  - **持久化配置**: 部署 `/etc/udev/rules.d/60-io-scheduler.rules`，确保重启后调度器策略依然生效。
  - **NVMe/SSD**: 自动应用 `none` 或 `mq-deadline` 策略，减少软件开销。
  - **机械硬盘 (HDD)**: 自动识别 `rotational=1` 设备并加载 `bfq` 模块，优化高负载下的响应延迟。
  - **磁盘挂载**: 为 ext4 分区添加 `noatime,commit=30` 选项，减少元数据写入。

## 4. 依赖关系
- 本角色完全使用 `ansible.builtin` 核心模块实现，无外部 Collection 依赖。
- (Legacy) 曾依赖 `community.general` 集合，现已重构移除以增强兼容性。

## 5. 维护与排查
- **检查时间同步状态**: `timedatectl status`。
- **检查 DNS**: `nslookup google.com`。
- **检查 I/O 调度器**: `cat /sys/block/sdX/queue/scheduler`。
- **验证 udev 规则**: `cat /etc/udev/rules.d/60-io-scheduler.rules`。
