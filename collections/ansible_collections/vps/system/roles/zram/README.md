# Role: vps.system.zram

## 1. 概述
该角色用于配置 zRAM (压缩内存交换)，通过在内存中划分压缩区域作为 swap，提高系统在低内存环境下的性能。

## 2. 变量说明
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `zram_algo` | `zstd` | 压缩算法（`lz4` 更快，`zstd` 压缩率更高）。 |
| `zram_percent` | `50` | 占用物理内存的最大百分比。 |
| `zram_priority` | `100` | zRAM 的优先级（通常高于磁盘 swap）。 |

## 3. 内部逻辑
- **安装**: 安装 `zram-tools` 软件包。
- **配置**: 修改 `/etc/default/zramswap`。
- **优先级管理**: 自动调整 `/etc/fstab`，确保物理磁盘 swap 的优先级低于 zRAM。

## 4. 依赖关系
- 系统包: `zram-tools`。

## 5. 维护与排查
- **查看 zRAM 状态**: `zramctl`。
- **查看 Swap 优先级**: `swapon --show`。
- **服务状态**: `systemctl status zramswap`。

## 6. 实机结论

- `zram` 的运行前提同样依赖 `python_environment`，因为角色执行要先有 `/opt/aurora_venv/bin/python3`。
- 本轮真机验收确认：`zram` 可在目标机已存在 active `/dev/zram0` 的情况下建立 baseline，并在 rollback 后恢复原有 active 状态。
- `verify` 需要同时看 `/etc/default/zramswap`、`swapon --show`、`zramctl`、`zram.fact`，不能只看服务启用状态。
