# Sub-collection: vps.system

## 1. 概述
该子集合包含了 VPS 的基础系统配置角色，涵盖初始化、内核调优、安全增强及备份管理。

## 2. 包含的角色

### 核心基线 (Phase 0)
- **[init](./roles/init/README.md)**: 基础包安装、主机名设置、时区配置。
- **[sysctl](./roles/sysctl/README.md)**: 内核参数调优（网络、内存、IO）。
- **[firewall](./roles/firewall/README.md)**: 基于 UFW 的防火墙管理与 NAT 转发。
- **[ssh](./roles/ssh/README.md)**: SSH 安全增强与连接加速。

### 系统服务
- **[journald](./roles/journald/README.md)**: 日志持久化与大小限制。
- **[systemd_priority](./roles/systemd_priority/README.md)**: 动态管理原生服务的 OOM 与 CPU 优先级。
- **[logrotate](./roles/logrotate/README.md)**: 日志轮转配置。
- **[fail2ban](./roles/fail2ban/README.md)**: 入侵防御自动封禁。

### 自动化运维 (Phase 6)
- **[backup_service](./roles/backup_service/README.md)**: 数据备份核心逻辑。
- **[cleanup](./roles/cleanup/README.md)**: 空间清理脚本。
- **[audit](./roles/audit/README.md)**: 系统安全审计。

## 3. 使用方法
通常通过 `playbooks/system/main.yml` 调用，或使用 `make deploy-phase0` 标签触发。
