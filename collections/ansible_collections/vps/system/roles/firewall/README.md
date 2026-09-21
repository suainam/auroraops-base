# Role: vps.system.firewall

## 1. 概述
该角色负责管理 VPS 的通用防火墙策略，采用 **UFW (Uncomplicated Firewall)** 作为前端。角色已对齐 stateful lifecycle：`preflight/apply/verify/rollback` 负责基线采集、写入、校验、恢复；`setup.yml` 与 `rules.yml` 为 apply 阶段复用的 helper。

## 2. 变量说明
### 2.1 基础架构 (Architecture)
*   **`tasks/preflight.yml`**: 只读采集当前 UFW/nftables/sysctl/受管文件状态，并准备 `facts.d` baseline。
*   **`tasks/apply.yml`**: 写入 baseline 后调用 `tasks/setup.yml` 与 `tasks/rules.yml` helper，统一执行安装、配置、规则放行。
*   **`tasks/verify.yml`**: 校验 baseline 存在、UFW 激活、SSH/TCP/UDP 规则和基础转发。
*   **`tasks/rollback.yml`**: 按 baseline 恢复受管文件、sysctl、包安装现状，并在恢复期间优先保住 SSH 端口。

### 2.2 变量详情 (Defaults)
所有端口变量建议在 profile 或 host_vars 中统一定义：

| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `ssh_port` | `6868` | SSH 连接端口，可在 host_vars 中覆盖为 `22` 或其他端口。 |
| `firewall_tcp_ports_global` | `[]` | 全局允许进入的 TCP 端口列表。 |
| `firewall_tcp_ports_host` | `[]` | 主机特定 TCP 端口。 |
| `firewall_tcp_ports_exclude` | `[]` | 排除的 TCP 端口。 |
| `firewall_udp_ports_global` | `[]` | 全局允许进入的 UDP 端口列表。 |
| `firewall_udp_ports_host` | `[]` | 主机特定 UDP 端口。 |
| `firewall_fact_path` | `/etc/ansible/facts.d/firewall.fact` | firewall baseline 持久化位置。 |

## 3. 内部逻辑
- **通用 NAT 支持**: 自动在 `/etc/ufw/after.init` 中注入通用 IP Masquerade 与 TCPMSS Clamping 规则。
- **服务解耦**: 特定业务服务（如 Docker、特定代理端口跳跃）的转发规则交由对应服务角色管理。

## 4. 依赖关系
*   `system/init`: 基础环境初始化。

## 5. 维护与排查
*   **全量部署**: `make deploy-system.firewall`
*   **验证规则**: `make verify-system.firewall`
