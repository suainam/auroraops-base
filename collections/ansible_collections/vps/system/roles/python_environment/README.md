# Role: vps.system.python_environment

## 1. 概述
该角色是 AuroraOps 的基础系统角色（Phase 1），核心目标是在目标主机上建立**统一的 Python 运行环境 (Canonical Venv)**。
它现在按 stateful role 模板拆成 `preflight / apply / verify / rollback`，先持久化部署前基线，再创建和回收 `Canonical Venv`，为后续角色提供一致的 Python 解释器。
本轮真机验收还把 `/etc/pip.conf` 归入本角色受管范围，确保后续 `pip` / `venv --upgrade-deps` 也走统一的防御式源策略。

## 2. 变量说明
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `system_python_venv_path` | `"/opt/aurora_venv"` | **核心变量**：统一虚拟环境的规范路径。 |
| `python_environment_fact_path` | `"/etc/ansible/facts.d/python_environment.fact"` | 部署前基线的持久化路径。 |
| `python_auto_link_existing_venv` | `true` | 历史兼容变量；当前 stateful 流程不再自动接管外部 venv。 |
| `bootstrap_venv_search_paths` | `[...]` | 只读探测路径，用于诊断已有 bootstrap/pipx 环境。 |
| `python_base_packages` | `["cryptography", "pyopenssl", ...]` | 确保安装在统一环境中的基础依赖包。 |
| `use_domestic_mirrors` | `false` | 是否使用国内 pip 镜像。 |
| `python_environment_pip_conf_path` | `"/etc/pip.conf"` | 系统级 pip 源配置，归角色受管。 |

## 3. 内部逻辑
- **Preflight**: 只读采集当前 `Canonical Venv` 状态、基线文件状态，以及系统 Python 是否具备 `ensurepip/venv` 前提。
- **Apply**: 先写入部署前基线，再按需补系统包、创建 `/opt/aurora_venv`、注入基础依赖、修正权限。
- **Verify**: 同时验证部署结果和 rollback 前提，至少检查基线存在、`python3`/`pip` 二进制存在、基础包可导入。
- **Rollback**: 仅按基线清理本角色创建的 `Canonical Venv` 和 baseline，不接管来源不明的既有环境。
- **pip 源治理**: 通过 `/etc/pip.conf` 受管清华优先、官方回退的防御式顺序，避免每次都靠临时环境变量。

## 4. 架构影响
- **ansible_python_interpreter**: 全局变量 `ansible_python_interpreter` 指向 `{{ system_python_venv_path }}/bin/python3`。
- **依赖一致性**: 角色只需向 `/opt/aurora_venv` 安装包，即可确保在整个部署生命周期中版本一致。

## 5. 维护与排查
- **状态验证**: `make verify-system.python_environment`。
- **手动检查**: `ls -ld /opt/aurora_venv /etc/ansible/facts.d/python_environment.fact /etc/pip.conf`。
- **环境测试**: `/opt/aurora_venv/bin/python3 -c "import cryptography,requests,jmespath,redis; print('Loaded')"`。
- **已知阻塞类型**: 若系统 Python 缺 `ensurepip`，角色会尝试安装 `python3-venv` 等系统包；此时若目标机 APT/DNS 有问题，失败层应归类为运行时前提，而不是 Role 逻辑。

## 6. 实机结论

- `python_environment` 是 `swap`、`zram` 的解释器前提；如果回滚它，后续角色会直接失去 `/opt/aurora_venv/bin/python3`。
- 本轮真机验收确认：`/etc/pip.conf` 由本角色受管，且应采用“清华优先，官方回退”的防御式顺序。
- `verify` 不应只验 venv，还要验证 `pip.conf`、基础包导入和回滚前提。
