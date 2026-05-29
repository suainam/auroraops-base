# Role: vps.system.fail2ban

## 1. 概述
该角色用于部署 Fail2Ban，通过监控日志防止暴力破解攻击。

## 2. 变量说明
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `fail2ban_bantime` | `1h` | 封禁时长。 |
| `fail2ban_findtime` | `10m` | 统计时间范围。 |
| `fail2ban_maxretry` | `5` | 最大重试次数。 |
| `fail2ban_ignoreip` | `[127.0.0.1/8]` | 忽略的 IP 列表。 |

## 3. 内部逻辑
- **安装**: 确保 `fail2ban` 软件包已安装。
- **配置**: 渲染 `jail.local.j2` 以覆盖默认设置。
- **服务**: 确保服务已启用并正在运行。

## 4. 依赖关系
- 操作系统: Debian / Ubuntu。

## 5. 维护与排查
- **查看状态**: `fail2ban-client status`。
- **查看 SSH 封禁**: `fail2ban-client status sshd`。
- **手动解封**: `fail2ban-client set sshd unbanip <IP>`。
- **日志查看**: `tail -f /var/log/fail2ban.log`。
