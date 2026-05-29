# Role: vps.system.benchmark

## 1. 概述
本角色用于服务器的综合性能测试与硬件/网络指标收集。它支持轻量级的本地基准测试（`fast` 模式）以及基于网络多节点测试的集成基准测试（`fusion` 模式，基于 ecs.sh 融合怪），并将提取到的性能事实持久化到目标机器上，同时可配置自动同步回控制端本地的 `host_vars` 中。

## 2. 变量说明 (Defaults)
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `benchmark_mode` | `fast` | 运行模式。`fast` 仅收集本地指标且不下载外部二进制；`fusion` 则拉取并调用 `ecs.sh` (网络与多路由测试)。 |
| `benchmark_fact_path` | `/etc/ansible/facts.d/performance.fact` | 性能结果持久化 Fact 文件的物理路径。 |
| `benchmark_script_path` | `/usr/local/bin/auroraops_benchmark.sh` | 写入实机的指标收集脚本路径。 |
| `benchmark_report_path` | `/var/log/auroraops/benchmark_report.txt` | 实机上生成的原始纯文本测试报告路径。 |
| `benchmark_sync_to_local` | `true` | 是否将收集到的性能指标自动同步到控制端本地的 `host_vars` 中。 |
| `benchmark_async_timeout` | `1800` | Ansible 异步执行超时时间（秒）。在 fusion 模式下建议设大。 |
| `benchmark_async_poll` | `15` | 异步轮询频率（秒）。 |

## 3. 内部逻辑
- **Preflight (前置检查)**: 自动检测实机上已有的 benchmark 基线和事实，若已部署过则安全保留 pre_deploy 状态。
- **采集脚本下发**: 向实机部署 `collect_metrics.sh` 脚本，此脚本具备两个模式的独立运行逻辑。
- **性能采集运行 (Async)**: 
  - 通过 `async: 1800` 异步调用指标收集脚本，规避长耗时测试导致的连接超时。
  - 在 `fast` 模式下，直接通过 `dd` 测试磁盘连续写速、`ping` 核心 DNS 节点评估延迟，并抓取 `/proc/cpuinfo`。
  - 在 `fusion` 模式下，拉取国内/国际最优质的 `ecs.sh` 并裁剪硬件、磁盘与三网路由测试。
- **本地 Fact 暴露**: 采集结果解析后以 JSON 格式持久化写入到 `/etc/ansible/facts.d/performance.fact` 中，Ansible 运行中可通过 `ansible_local.performance` 变量无缝提取。
- **自动分级评分 (Score)**:
  - 根据磁盘 IO 写速自动划分系统硬件底盘等级：`diamond` (💎 >=500MB/s), `gold` (🥇 >=200MB/s), `silver` (🥈 >=100MB/s), `stone` (🪨 <100MB/s)。
- **控制端同步 (Local Sync)**:
  - 若开启 `benchmark_sync_to_local`，角色会通过 Local Blockfile 动态将测得的性能参数（如 CPU、内存、磁盘 IO、平均延迟、分级）以标准 YAML 的 `performance:` 段，回写到控制端的 `inventories/host_vars/<hostname>.yml` 中。
- **优雅回滚 (Rollback)**: 
  - 完美恢复部署前的 `performance.fact`、`/usr/local/bin/` 脚本及本地 `host_vars` 段，达成 100% 零痕迹残留。

## 4. 依赖关系
- 本角色需要 `ansible.builtin` 核心模块的 `async` 与 `setup` 支持。

## 5. 维护与排查
- **手动重新执行**:
  ```bash
  # 使用 Linear 稳定模式，对指定主机强行运行 Benchmark
  make deploy-base.benchmark -e ANSIBLE_STRATEGY=linear
  ```
- **查看物理报告**:
  ```bash
  cat /var/log/auroraops/benchmark_report.txt
  ```
- **检查生成的 Facts**:
  ```bash
  cat /etc/ansible/facts.d/performance.fact
  ```
- **查看控制端变量**:
  检查本地的 `inventories/host_vars/<my-vps>.yml` 是否已被写入如下格式的块：
  ```yaml
  # BEGIN ANSIBLE MANAGED BLOCK: BENCHMARK PERFORMANCE
  performance:
    geo:
      country: "CN"
      city: "Beijing"
    network:
      latency_ms: 18.5
      ipv6_support: true
    hardware:
      cpu_model: "Intel(R) Xeon(R) Gold 6133 CPU @ 2.50GHz"
      cpu_cores: 2
      aes_ni: true
      virt_type: "kvm"
      ram_mb: 2048
      disk_gb: 40
      io_speed_mbps: 421
      score: "gold"
  # END ANSIBLE MANAGED BLOCK: BENCHMARK PERFORMANCE
  ```
