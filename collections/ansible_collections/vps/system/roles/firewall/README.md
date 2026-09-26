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

## 6. 已知契约：本角色的 `idempotence` 阶段无法达到 `changed=0`

这是一条**已知契约，不是缺陷**，但它必须写明，否则每个读 `docs/lifecycle.md` 的人都会把
`idempotence` 阶段的红灯当成有东西在漂移。

`setup.yml` 每次 deploy 都执行 `nft flush ruleset`。在本机的 iptables-nft 后端下，
**ufw 的规则与它的默认策略都存放在这张 nft ruleset 里**，所以 flush 会一并抹掉
`Default: deny (incoming)`。随后「Configure UFW default policies」必须把它重新应用回去，
而 `community.general.ufw` 会如实把这次重新应用报成 `changed`。

也就是说：**`changed=0` 对本角色在结构上不可达**，与「是否有东西在漂移」无关。修掉 flush 的
`changed_when` 只能让 flush 本身诚实上报，消不掉紧随其后的那一次真实变更。

已排除的两个可能解释：

- **不是 `Configure UFW default policies` 的 `when` 用错了快照。** 那个真 bug 已修：它曾读取
  preflight 在 flush **之前** 的快照，于是 flush 刚抹掉的入站 deny 被判定为「已经是 deny 了」
  而跳过——fail-open。现在改为 flush **之后** 重读，并且读取失败时倾向「重新应用」而非「假定正确」。
- **不是「诚实上报就能达成幂等」。** flush 抹掉的东西必须被重放，重放就是变更。

要让 `changed=0` 可达，只能让 flush 变成条件执行（例如仅在 `nftables` 服务曾启用时）。
本机当前的证据是这次 flush **没有存在理由**：`nft list tables` 里的六张表
（`ip filter`/`ip6 filter`/`ip nat`/`ip6 nat`/`ip mangle`/`ip raw`）全部是 iptables-nft 模拟
iptables 用的表，其中没有一行独立 nftables 配置；`nftables` 服务为 `disabled` + `inactive`；
`/etc/nftables.conf` 是未改动的原版。但弱化公网主机上的防火墙步骤需要单独决策，尚未做。

### 另一条相关事实：`check` 阶段看不到本角色的 `apply` 步骤

`tasks/main.yml` 用 `when: not ansible_check_mode` 包住 `apply.yml`，而 flush、post-flush 重读、
默认策略重放全部位于 `setup.yml`（`apply.yml` 内）。因此 **`check` 阶段在结构上无法显示这些任务**，
dry-run 通过不构成「策略会被重放」的证据。要验证这一点只能真跑一次 apply。

## 7. 端口类型无关紧要（归一化在两处）

主机侧的端口清单天然混着两种写法：`firewall_udp_ports_host` 里既有带引号的 Jinja 引用
（到达时是 `AnsibleUnsafeText`），也有裸整数，而 TCP 清单全是整数。因此：

- `common/tasks/merge_list_vars.yml` 在合并前把每个清单 `map('string')` 归一化，
  `difference` 的两侧都归一化——否则字符串清单与整数清单相减**什么都不减且不报错**，
  `_exclude` 里的 `40052` 不会移除计划中的 `'40052'`，防火墙就会静默地关不掉一个被显式排除的端口；
- 本角色在 `tasks/main.yml` 与 `tasks/verify.yml` 里对输出再次 `map('string')`。

两处都归一化是必要的：`verify.yml` 自建清单，若归一化方式与它所校验的 `deploy` 不同，
就会对同一台主机给出不同结论。
