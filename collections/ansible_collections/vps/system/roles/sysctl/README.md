# Role: vps.system.sysctl

## 1. 概述
该角色用于优化 Linux 内核参数，涵盖网络栈性能（BBR/BBR2）、缓冲区大小、队列长度以及关键的网络安全加固设置。

## 2. 变量说明 (Defaults)
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `net.ipv4.tcp_congestion_control` | `bbr2` | 拥塞控制算法。若内核不支持 BBR2，角色会自动回退至 BBR。 |
| `net.core.rmem_max` | `33554432` (32MB) | 最大 TCP 接收缓冲区（针对长肥管道优化）。 |
| `net.core.somaxconn` | `8192` | 最大监听队列。 |
| `net.ipv4.tcp_syncookies` | `1` | 开启 SYN Cookies 防御 SYN Flood 攻击。 |

## 3. 内部逻辑
- **生命周期结构**: `preflight -> apply -> verify -> rollback`，`check` 只跑只读 preflight。
- **基线持久化**: 部署前把当前 sysctl 值和 role 自己的持久化文件状态写到 `/etc/ansible/facts.d/sysctl.fact`。
- **内核模块检查**: 检查 `tcp_bbr2` 和 `nf_conntrack` 可用性，并只管理 role 自己的 `99-auroraops-*.conf`。
- **自动回退机制**: 使用 `modinfo tcp_bbr2` 检查支持情况，若不支持则改用 `bbr`。
- **参数应用**: 持久化到 `/etc/sysctl.d/99-auroraops.conf`，再只重载该文件。
- **安全加固**:
  - 禁用 ICMP 重定向（防路由欺骗）。
  - 忽略广播 ICMP 请求（防 Smurf 攻击）。
  - 开启 TCP SYN Cookies。
  - 开启 RFC1337 (TIME-WAIT Assassination Protection)。
  - 限制路由转发重定向。

## 4. 依赖关系
- `ansible.posix` 集合。

## 5. 维护与排查
- **参数验证**: `sysctl -p`。
- **日志查看**: `journalctl -u systemd-sysctl`。
- **内核支持**: `modinfo tcp_bbr2` 检查 BBR2 支持情况。
- **持久化**: 配置文件位于 `/etc/sysctl.d/99-auroraops.conf`。
- **回滚基线**: `/etc/ansible/facts.d/sysctl.fact`。
