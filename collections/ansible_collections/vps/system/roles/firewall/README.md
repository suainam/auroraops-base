# Role: vps.system.firewall

## 1. 概述
该角色负责管理 VPS 的防火墙策略，采用 **UFW (Uncomplicated Firewall)** 作为前端。角色已对齐 stateful lifecycle：`preflight/apply/verify/rollback` 负责基线采集、写入、校验、恢复；`setup.yml` 与 `rules.yml` 退化为 apply 阶段复用的 helper。

## 2. 变量说明
### 2.1 基础架构 (Architecture)
*   **`tasks/preflight.yml`**: 只读采集当前 UFW/nftables/sysctl/受管文件状态，并准备 `facts.d` baseline。
*   **`tasks/apply.yml`**: 写入 baseline 后调用 `tasks/setup.yml` 与 `tasks/rules.yml` helper，统一执行安装、配置、规则放行。
*   **`tasks/verify.yml`**: 校验 baseline 存在、UFW 激活、SSH/TCP/UDP 规则和 Hysteria NAT 规则。
*   **`tasks/rollback.yml`**: 按 baseline 恢复受管文件、sysctl、包安装现状，并在恢复期间优先保住 SSH 端口。

### 2.2 变量详情 (Defaults)
所有端口变量建议在 `inventories/group_vars/all.yml` 中统一定义，本角色通过引用这些变量来实现单点管理。

| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `ssh_port` | `6868` | SSH 连接端口，可在 host_vars 中覆盖为 `22` 或其他端口。 |
| `firewall_allow_tcp_ports` | `[80, 443, ...]` | 允许进入的 TCP 端口列表；SSH 端口通过 `ssh_port` 注入，不要额外硬编码 `22`。 |
| `firewall_allow_udp_ports` | `[23049]` | 允许进入的 UDP 端口列表。 |
| `firewall_hysteria_hopping.enabled` | `false` | 是否开启 Hysteria 端口跳跃支持。公开 base 默认关闭。 |
| `firewall_hysteria_hopping.port_range` | `"30100:30200"` | 端口跳跃范围。 |
| `firewall_fact_path` | `/etc/ansible/facts.d/firewall.fact` | firewall baseline 持久化位置。 |

## 3. 内部逻辑
- **不冲突原则**: 主动检测 Docker 状态，在全量 Setup 时协调重启，在 Rules 变更时不惊动 Docker。
- **NAT 支持**: 自动在 `/etc/ufw/after.init` 中注入 IP Masquerade 和 Port Hopping 规则。

## 4. 依赖关系
*   `system/init`: 基础环境初始化。

## 5. 维护与排查
*   **全量部署**: `make deploy-system.firewall`
*   **仅更新规则**: 可通过 tags 或手动指定 task 文件（高级用法），但在现有 Makefile 体系下，直接运行 deploy 即可，Ansible 的幂等性会跳过 setup 中未变更的步骤。
