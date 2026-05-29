# Role: vps.system.reinstall

## 1. 概述
> [!CAUTION]
> **本角色为高危物理操作角色！** 
> 它旨在通过网络一键下载并调用系统重装（DD 还原）交互式引导工具（默认使用科技lion），实现对远程主机操作系统的彻底推倒重来。此操作将抹除机器上的**所有数据**并重装为纯净全新的系统。

由于此操作具备毁灭性，**角色默认在全局变量中处于完全禁用状态**。必须通过显式配置并且在运行中经过双重确认才能触发。

## 2. 变量说明 (Defaults)
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `reinstall_script_url` | `https://kejilion.pro/kejilion.sh` | 调用的系统重装与多功能运维脚本链接。 |
| `reinstall_warning_msg` | *多行警告文本* | 角色被激活并在终端暂停时，向操作者输出的警告巨幅文本。 |

## 3. 内部逻辑
- **显式开关保护**:
  - 本角色依赖变量 `auroraops_roles.system.reinstall`。该值默认未定义或设为 `false`。
  - 若未被显式启用，角色运行时会自动 debug 输出 `Role reinstall is disabled, skipping` 并优雅跳过，绝无误触风险。
- **终端交互二次确认**:
  - 当显式启用该角色后，Ansible 在执行该任务前会触发 `ansible.builtin.pause` 模块在您的控制端终端输出巨幅红色高亮警告，并要求输入 `y` 确认继续。
  - 任何非 `y`（如回车、输入 `n` 或取消）都会触发 `ansible.builtin.meta: end_host` 立即安全终止对当前主机的所有后续剧本执行。
- **重装执行**:
  - 当且仅当操作者明确输入 `y` 确认后，角色将在目标主机上通过 `curl -sS -O` 下载脚本，赋予执行权限，并在终端暴露交互接口，引导您完成远程主机的重装（DD 还原）操作。

## 4. 依赖关系
- 本角色无其他 role 依赖，也不建立 facts 基线（因系统重装后原有事实将不复存在，故本角色为**无状态破坏性操作**，不支持 rollback）。

## 5. 维护与排查
- **如何安全地启用与执行**:
  如果因为机器出现故障或确有重新安装纯净系统的需要，可在 `inventories/host_vars/<my-host>.yml` 中增加显式覆写：
  ```yaml
  auroraops_roles:
    system:
      reinstall: true
  ```
  然后运行专有单角色指令：
  ```bash
  make deploy-base.reinstall
  ```
- **注意终端回显**:
  由于重装脚本涉及复杂的终端交互或交互式菜单，在运行 Ansible 时，请确保您的终端是交互式的，能够正常响应 `pause` 模块的确认提示。
