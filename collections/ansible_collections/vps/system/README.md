# 📦 Sub-collection: vps.system

> [!NOTE]
> **vps.system** 子集合是 AuroraOps 自动化管理框架中最为核心的基础设施底盘。
> 它由 18 个独立的系统级 Ansible 角色组成，从物理包管理器、内核底层参数，到主机高级防火墙与入侵防御策略，完成了对 Debian 服务器的全面加固与优化。

---

## 🗺️ 角色全景与执行阶段 (Execution Phases)

这 18 个角色按照严密的生命周期依赖顺序，划分为四个主要的执行阶段（Phases）。

```mermaid
graph LR
    P0[Phase 0: 核心基线与底层调优] --> P1[Phase 1: 网络与主机安全加固]
    P1 --> P2[Phase 2: 局域网组网与个性化运行]
    P2 --> P3[Phase 3: 验收测试与综合性能度量]

    style P0 fill:#2196F3,stroke:#1976D2,color:#fff
    style P1 fill:#4CAF50,stroke:#388E3C,color:#fff
    style P2 fill:#9C27B0,stroke:#7B1FA2,color:#fff
    style P3 fill:#E91E63,stroke:#C2185B,color:#fff
```

### 1. 阶段 0：核心系统底层调优 (Phase 0)
本阶段的角色直接与 Linux 内核与基础磁盘/内存交互，用于搭建极速、稳健的 OS 底盘：
-   **[init](./roles/init/README.md)**: 物理包管理器配置、全局主机名注入、系统核心包补全。
-   **[base](./roles/base/README.md)**: 系统时区、 locale 字符编码、高速度国内 APT 软件源、timesyncd 时钟客户端及公共 DNS 调优。
-   **[sysctl](./roles/sysctl/README.md)**: 网络高并发、TCP 拥堵控制 (BBR/BBR2)、内存 Page-cluster 交换优化及脏数据写盘比率内核调优。
-   **[limits](./roles/limits/README.md)**: 突破 Linux 默认 nofile 限制，将用户句柄上限调优至 `1048576`。
-   **[swap](./roles/swap/README.md)**: 智能识别 RAM 大小，动态创建、挂载并开启合理配额的 Swap 分区。
-   **[zram](./roles/zram/README.md)**: 基于 ZRAM 的动态内存压缩缓冲，低配 VPS 主机的“内存救星”。
-   **[journald](./roles/journald/README.md)**: 接管 Systemd 日志系统，实现日志的持久化并严格限额以杜绝磁盘写满。
-   **[systemd_priority](./roles/systemd_priority/README.md)**: 动态为系统核心服务进程（如 SSH, PGsql）配置 CPU nice 与 OOMScoreAdjust 调度优先级。

---

### 2. 阶段 1：网络与主机安全加固 (Phase 1)
本阶段的角色负责切断一切外部不安全接入，防范扫描爆破，实现系统的“零信任”加固：
-   **[ssh](./roles/ssh/README.md)**: 关闭密码登录、关闭 Root 远程密码登录，强制密钥验证，重构 sshd 配置并开启连接流复用。
-   **[firewall](./roles/firewall/README.md)**: 基于 UFW 的安全防火墙，入站全拦截，动态放行服务提权端口。
-   **[fail2ban](./roles/fail2ban/README.md)**: 智能日志审计防线，对扫描、爆破 SSH 的外部恶意源进行实时识别并拉黑封禁。
-   **[logrotate](./roles/logrotate/README.md)**: 全局日志轮转策略，定时压缩、清理冗余日志文件。
-   **[unattended_upgrades](./roles/unattended_upgrades/README.md)**: 守护进程，自动静默拉取并物理更新 Linux 的紧急安全补丁。

---

### 3. 阶段 2：虚拟组网与环境支持 (Phase 2 & 2.5)
本阶段负责提供高级的本地互联与系统虚拟化支持：
-   **[zerotier](./roles/zerotier/README.md)**: 一键部署并加入 ZeroTier 私有局域网网卡。
-   **[python_environment](./roles/python_environment/README.md)**: 统一全局 Python 及其开发依赖的虚拟化环境。
-   **[reinstall](./roles/reinstall/README.md)**: 为新机器快速拉取并一键安装重装系统引导。

---

### 4. 阶段 3：验收测试与性能度量 (Phase 3)
本阶段的角色负责为整个基础设施基线提供可量化、可验证的数据支持：
-   **[ansibletest](./roles/ansibletest/README.md)**: 仓库专用的集成自动化校验脚手架。
-   **[benchmark](./roles/benchmark/README.md)**: 服务器 CPU、I/O 写速、网络带宽及全局性能评估基盘。

---

## ⚡ 极速操作入口汇总

在控制端完成 `make bootstrap` 后，您可以通过 Makefile 以极高的效率对整个 `system` 域或精确到单个角色进行管理：

### 1. 系统级大域操作（对全部 18 个角色执行完整生命周期）
```bash
make check-system      # 1. 完整大域 Dry-Run 校验 (linear 稳定版)
make deploy-system     # 2. 完整大域物理部署 (Mitogen 极速版)
make verify-system     # 3. 完整大域实机物理状态核对
make rollback-system   # 4. 完整大域零污染回撤复原
```

### 2. 角色级精确操作（秒级响应）
支持只执行单个角色的生命周期，响应速度提升 90% 以上：
```bash
make check-system.sysctl
make deploy-system.ssh
make verify-system.swap
make rollback-system.zram
```

---

## 🔒 状态化生命周期契约

本集合内的所有状态角色（Stateful Roles）均严格遵守 AuroraOps **基线快照契约**：
1.  **事实归档 (Pre-deploy)**：在角色发生任何 `deploy` 前，会自动提取该项配置的原系统文件/状态，物理存储于 `/etc/ansible/facts.d/<role_name>.fact`，作为此主机的黄金第一基线。
2.  **验证断言 (Verify)**：执行 `verify` 时，将直接提取主机的运行时数据与事实信息（如 `timedatectl` 时区、`sysctl -a` 内核变量）进行强类型 `assert`，只有实机状态 100% 达标才算通过。
3.  **无损降拨 (Rollback)**：当需要执行 `rollback` 时，Ansible 会主动 slurp 远端的 `.fact` 基线文件，将其完全还原为**部署前的历史模样**，并物理清除所有下发规则，确保测试机 100% 零痕迹残留。
