# Role: vps.system.limits

## 1. 概述
该角色用于管理 `nofile` 限制，默认将 `/etc/security/limits.d/99-nofile.conf` 设为 `1048576`。

## 2. 变量说明
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `limits_fact_path` | `/etc/ansible/facts.d/limits.fact` | 部署前基线持久化路径。 |
| `limits_managed_file` | `/etc/security/limits.d/99-nofile.conf` | 受管 limits 文件。 |
| `limits_nofile` | `1048576` | 目标 nofile 值。 |

## 3. 内部逻辑
- `check` 只跑只读 preflight。
- deploy 前必须先写入 `limits_fact_path`。
- rollback 仅恢复或删除角色自己管理的 `limits_managed_file`，再清理 baseline。
- verify 同时验证 deploy 结果和 rollback 前提。
- 只接管 `limits_managed_file`，不改其他 PAM 或 shell 限制入口。
- 遇到已有同路径文件时，先读取为基线，再按 rollback 语义恢复。

## 4. 维护与排查
- 查看配置: `cat /etc/security/limits.d/99-nofile.conf`
- 查看基线: `sudo cat /etc/ansible/facts.d/limits.fact`
- 生效方式: 需要重新登录后再看 `ulimit -n`
- 验证优先看文件与 facts，`ulimit` 只能作为登录态补充证据。
