# Role: vps.system.unattended_upgrades

## 1. 概述
该角色负责配置 Debian/Ubuntu 系统的 `unattended-upgrades` 服务，实现安全补丁的自动安装。

## 2. 变量说明
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `unattended_upgrades_origins` | `["origin=Debian,codename=${distro_codename},label=Debian-Security"]` | 允许自动更新的源列表 |
| `unattended_upgrades_auto_reboot` | `true` | 是否在需要时自动重启 |
| `unattended_upgrades_reboot_time` | `"04:00"` | 自动重启的时间 |

## 3. 内部逻辑
1.  **包安装**: 安装 `unattended-upgrades` 和 `apt-listchanges`。
2.  **配置**: 渲染 `/etc/apt/apt.conf.d/50unattended-upgrades` 和 `20auto-upgrades`。
3.  **黑名单**: 可配置禁止自动升级的包（Variables pattern）。

## 4. 依赖关系
*   `system/base`: 需确保 APT 源已配置正确。

## 5. 维护与排查
*   **日志位置**: `/var/log/unattended-upgrades/`
*   **手动测试**: `sudo unattended-upgrade -d` (Dry run)
