# Role: vps.system.journald

## 1. 概述
该角色用于优化 Systemd Journald 的日志存储策略，防止日志占用过多的磁盘空间，并优化资源使用。

## 2. 变量说明
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `journald_fact_path` | `/etc/ansible/facts.d/journald.fact` | 部署前基线持久化路径。 |
| `journald_managed_dir` | `/etc/systemd/journald.conf.d` | 受管 override 目录。 |
| `journald_managed_file` | `/etc/systemd/journald.conf.d/override.conf` | 受管 override 文件。 |
| `journald_system_max_use` | `10M` | journald 总磁盘占用上限。 |
| `journald_rate_limit_interval` | `30s` | journald 限流时间窗口。 |
| `journald_rate_limit_burst` | `1000` | journald 限流突发数。 |
| `journald_storage` | `persistent` | journald 存储模式。 |
| `journald_sync_interval` | `5m` | journald 落盘同步间隔。 |
| `journald_forward_to_syslog` | `no` | 是否转发到 syslog。 |

## 3. 内部逻辑
- **生命周期结构**: `preflight -> apply -> verify -> rollback`，`check` 只跑只读 preflight。
- **基线持久化**: 部署前把 `journald_managed_dir` / `journald_managed_file` 的原始状态写入 `journald_fact_path`。
- **受管边界**: 只接管 role 自己的 `journald_managed_file`，不改别的 journald 配置入口。
- **回滚语义**: 若部署前该 override 文件已存在，则按基线恢复原内容；若原先不存在，则删除 role 自己创建的文件和目录。
- **资源优化**: 默认设置 `SystemMaxUse=10M`、`Storage=persistent`、`ForwardToSyslog=no` 等 journald 参数。

## 4. 依赖关系
- 核心模块: `ansible.builtin.copy`。

## 5. 维护与排查
- **查看配置**: `sudo cat /etc/systemd/journald.conf.d/override.conf`
- **查看基线**: `sudo cat /etc/ansible/facts.d/journald.fact`
- **查看日志占用**: `journalctl --disk-usage`
- **清理日志**: `journalctl --vacuum-size=10M`
- **配置生效**: `systemctl restart systemd-journald`
