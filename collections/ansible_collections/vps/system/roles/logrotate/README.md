# Role: vps.system.logrotate

## 概述
该角色用于配置系统级日志轮转策略，并允许其他角色通过变量声明服务特定的轮转规则。

## 变量
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `logrotate_fact_path` | `/etc/ansible/facts.d/logrotate.fact` | 部署前基线持久化路径。 |
| `logrotate_managed_file` | `/etc/logrotate.conf` | 受管主配置文件。 |
| `logrotate_managed_dir` | `/etc/logrotate.d` | 受管服务配置目录。 |
| `logrotate_rotate_count` | `3` | 全局 rotate 副本数。 |
| `logrotate_enable_compress` | `true` | 是否开启全局 `compress`。 |
| `logrotate_configs_to_deploy` | `[]` | 包含 `name` 和配置内容的列表，用于生成 `/etc/logrotate.d/` 下的文件。 |

## 当前口径
- `check` 只跑只读 preflight。
- deploy 前必须先写入 `logrotate_fact_path`。
- verify 同时验证 deploy 结果和 rollback 前提。
- rollback 成功后删除 `logrotate_fact_path`。
- role 只接管 `/etc/logrotate.conf` 中自己的 `rotate` / `compress` 修改，以及本轮 `logrotate_configs_to_deploy` 对应的服务配置文件。
- rollback 恢复部署前的主配置内容，并按基线恢复或删除服务配置文件。

## 维护与排查
- 查看基线：`sudo cat /etc/ansible/facts.d/logrotate.fact`
- 查看主配置：`sudo cat /etc/logrotate.conf`
- 查看服务配置：`sudo ls -l /etc/logrotate.d`
- 强制轮转：`logrotate -f /etc/logrotate.conf`
- 调试服务配置：`logrotate -d /etc/logrotate.d/<service_name>`

## 依赖与边界
- 角色只接管 `/etc/logrotate.conf` 的 `rotate`/`compress` 与 `/etc/logrotate.d/` 下由 `logrotate_configs_to_deploy` 生成的服务配置；不安装 logrotate 自身，依赖基础系统已存在并启用 logrotate。
- 基线持久化依赖目录 `/etc/ansible/facts.d`（由本角色首次运行时创建）。
- `logrotate_configs_to_deploy` 默认 `[]`，由调用方通过 `include_role` 的 `vars:` 传入（如 `vps.system.firewall` 的 `tasks/setup.yml` 传入 ufw），或由 inventory/vars 提供；每次调用只部署当次传入的条目。
- 回滚依赖基线 fact 文件存在；基线缺失且 `/etc/logrotate.conf` 仍存在时拒绝回滚，基线缺失且无受管文件时则跳过（`tasks/rollback.yml`）。
