# Role: vps.system.swap

## 概述

该角色管理单一磁盘 swap 文件，默认目标为 `/swapfile`。

## 变量

| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `swap_multiplier` | `2.0` | 内存倍数。 |
| `swapfile_path` | `/swapfile` | 受管 swap 文件路径。 |
| `swap_fact_path` | `/etc/ansible/facts.d/swap.fact` | 部署前基线持久化路径。 |
| `swapfile_priority` | `10` | `/etc/fstab` 中受管 swapfile 的优先级。 |
| `swap_desired_bytes` | `undefined` | 显式指定目标大小（字节）。 |

## 当前口径

- 角色只管理自己的 `swapfile_path`，不接管其他 swap 设备。
- 若部署前已存在未被 AuroraOps 接管的 `swapfile_path` 文件，直接失败。
- 若部署前只残留 `swapfile_path` 的 `/etc/fstab` 条目、但文件本体不存在，允许接管，并在 rollback 时恢复原始 fstab 行。
- 若部署前已有其他 active swap 设备，但没有受管 `swapfile_path`，允许补充创建受管 swapfile。
- deploy 前必须先写入 `swap_fact_path`；写不了即失败。
- `swap_fact_path` 记录部署前整机 swap 视图，以及部署前 active 设备集合。
- rollback 目标是恢复部署前原本 active 的 swap 设备到可用状态，不做字节级重建。
- 角色自己管理 `/etc/fstab` 中对应 `swapfile_path` 的条目。
- rollback 成功后删除 `swap_fact_path`；deploy 中途失败则保留。
- verify 同时验证 deploy 结果和 rollback 前提。

## 实机结论

- `swap` 依赖 `python_environment` 提供的解释器环境；没有 `/opt/aurora_venv/bin/python3` 时，Ansible 会直接失去执行前提。
- 本轮真机验收确认：`swap` 可以在已有 `zram` 和其他 active swap 存在时补建 `/swapfile`，并在 rollback 后恢复部署前状态。
- `verify` / `rollback` 都要通过 SSH 再确认 `/proc/swaps`、`/swapfile`、`/etc/fstab`、`swap.fact`。

## 排查

- 查看 active swap：`cat /proc/swaps`
- 查看受管 swapfile：`ls -lh /swapfile`
- 查看受管基线：`sudo cat /etc/ansible/facts.d/swap.fact`
