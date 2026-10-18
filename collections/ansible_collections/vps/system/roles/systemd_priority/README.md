# Role: vps.system.systemd_priority

## 1. 概述
该角色用于动态管理原生 Systemd 服务的优先级配置。它通过创建 Systemd Drop-in 覆盖文件，提升关键服务在系统高负载下的稳定性。

## 2. 变量说明
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `systemd_priority_fact_path` | `/etc/ansible/facts.d/systemd_priority.fact` | 角色基线 fact 文件路径。 |
| `systemd_priority_services` | `[{name: "ssh", oom_score_adj: -500, nice: -5}]` | 需要配置优先级的服务列表及其参数。 |

## 3. 生命周期
- `preflight`: 采集现状，读取/校验 baseline，记录 `pre_deploy_*` 与 managed service map。
- `apply`: 落盘 baseline，创建 override 目录并写入 `priority.conf`。
- `verify`: 只做只读验收，验证 baseline、文件存在和内容。
- `rollback`: 按 baseline 恢复/删除 override，并清理 fact。

## 4. 维护与排查
- 查看配置: `cat /etc/systemd/system/<service>.service.d/priority.conf`
- 查看 baseline: `cat /etc/ansible/facts.d/systemd_priority.fact`

### 内部逻辑
- 角色不修改单元文件本体，而是为 `systemd_priority_services` 中每个服务创建 `/etc/systemd/system/<service>.service.d/priority.conf` drop-in，写入 `OOMScoreAdjust` 与 `Nice`（来自各服务的 `oom_score_adj`/`nice`）。
- apply 前先落地基线 fact（`systemd_priority.fact`，含 `managed_services`），rollback 按基线恢复或删除 drop-in 目录并清理 fact。
- 修改后通知 systemd 重载并重启受管服务。
