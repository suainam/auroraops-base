# Role: vps.system.init

## 1. 概述
本角色用于服务器的初始化，包括系统包更新、安装必备的基础工具以及为后续的自动化部署准备目录结构。
它的职责是把主机拉到“APT 可用、基础包可装、后续角色能继续跑”的最低可用状态。

边界约束：
- `init` 可以修复 **bootstrap 级** 网络前提，例如 APT 所需的最小 resolver 配置。
- `init` 不负责长期 DNS 策略；正式 `/etc/resolv.conf` / nameserver 基线仍属于 `base`。
- `init` 不应依赖 `base` 先部署，否则会形成顺序循环。
- `init` 只准备自动化工作区和基础工具，不安装 `ansible` 本体。

## 2. 变量说明 (Defaults)
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `init_packages` | `[curl, git, vim, ...]` | 基础软件包列表，可在 `defaults/main.yml` 中自定义。 |

## 3. 内部逻辑
- **Preflight**: 检测操作系统/版本、当前 `sources.list`、当前 `resolv.conf`、APT 源连通性，并记录部署前 baseline。
- **Bootstrap DNS**: 仅在 `resolv.conf` 没有任何 `nameserver` 时，写入最小可用 resolver，确保 APT 能启动。
- **系统更新**: 执行 `apt update` 和 `apt upgrade -y` 确保系统处于可继续部署状态。
- **基础工具安装**: 安装 `init_packages` 列表中定义的常用运维工具 (如 `htop`, `rsync`, `python3-pip` 等)。
- **自动化环境准备**:
  - 不再在远端创建 `~/ansible` 工作区。
  - 本地开发侧的 Ansible 工具链和工作区由 `make bootstrap` 管理。
- **验证**: 同时验证 deploy 结果和 rollback 前提，例如 baseline、resolver 可用性、APT 基础能力。

## 4. 实机结论

- `init` 是后续 `python_environment`、`swap`、`zram` 的上游前提，必须优先保证部署态。
- 本轮真机验收确认：bootstrap 后 `sources.list` 需要继续按清华优先、官方回退的防御式顺序落地，不能因为 RTT 观测退回慢源。
- `verify` 和 `rollback` 都必须补 SSH 实机证据，不能只看 `make` 或 Ansible 回显。

## 5. 依赖关系
- 适用于 Debian/Ubuntu 系统。
- 优先级建议：`init -> python_environment -> swap -> zram`，再继续其他 base 角色。

## 6. 维护与排查
- 如果软件包安装失败，请先分层检查：
  - `/etc/resolv.conf` 是否有 `nameserver`
  - 默认路由和网关是否可达
  - 默认 Debian 源或 fallback 镜像源是否可解析
  - 只有这些前提正常后，才继续看 role 本身

## 6. 已知问题与解决方案 (2026-02-14)

### 问题: Linux Mint 系统上 apt update 失败
**现象**: 报错 `The repository 'https://mirrors.tuna.tsinghua.edu.cn/debian xia Release' does not have a Release file.`

**原因**: 
- Ansible 使用 `ansible_distribution_release` 获取系统代号 (如 Debian 为 `bookworm`)
- Linux Mint 22 的代号为 `xia`，但清华源不存在此路径
- 错误配置导致 `apt update` 失败

**解决方案**:
- 在配置 APT 镜像源任务中增加判断条件 `ansible_distribution == 'Debian'`
- 仅当系统为 Debian 时才应用 Debian 镜像源配置
- 对于 Linux Mint/Ubuntu 等系统，跳过镜像源配置，使用系统默认源
