# Zsh Role

## 1. 概述
本角色用于安装 Zsh、配置高性能的 Zsh 环境，并使用 Zinit 插件管理器安装常用的 Zsh 插件（如语法高亮、自动补全）。

平台兼容：Debian 通过 APT 安装，Alpine 通过 APK 安装；回滚也按相同平台选择包管理器。

## 2. 功能特性

### 2.1 自动切换到 Zsh
部署后，SSH 登录将自动切换到 Zsh，无需手动执行 `zsh` 命令。

**实现方式**: 通过 `.bash_profile` 自动检测并使用 `exec zsh` 切换。

```
用户 SSH 登录 → .bash_profile 检测 → 自动 exec zsh → Zsh 加载
```

**首次登录说明**: 首次进入 Zsh 时，Zinit 会自动下载插件（约 10-30 秒）。后续登录将秒进 Zsh。

### 2.2 Zinit 插件管理
使用 Zinit 插件管理器，包含以下插件：
- `zsh-autosuggestions`: 命令自动补全
- `zsh-completions`: 额外的补全规则
- `zsh-history-substring-search`:  history 快速搜索
- `fast-syntax-highlighting`: 语法高亮

### 2.3 Bun 全局包支持
自动配置 Bun 全局包的 PATH，确保 `bun install -g` 安装的命令（如 `qmd`）可直接使用。

```zsh
export PATH="/root/.bun/bin:$PATH"
```

### 2.4 OpenClaw 集成（可选）
如果目标主机安装了 openclaw，自动加载其 Zsh 补全配置。

**安全机制**:
- 仅在交互式 shell 中加载（避免非交互模式报错）
- 仅当 `compdef` 函数存在时加载（避免补全系统未初始化错误）
- 自动过滤 openclaw 的日志输出（避免 glob pattern 错误）

## 2. 变量说明 (Defaults)
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `zsh_path` | `/bin/zsh` | Zsh 的二进制路径。 |
| `admin_user` | (可选) | 需要配置 Zsh 的管理员用户名。 |

## 3. 内部逻辑
- **安装**: 安装 `zsh` 和 `lua5.4` (某些插件需要)。
- **Zinit 安装**: 自动运行官方安装脚本，为 `root` 和可选的 `admin_user` 安装 Zinit 插件管理器。
- **配置部署**: 使用模板生成个性化的 Zsh 配置文件。
- **Shell 切换**: 使用 Ansible Handler 机制，在 zsh 安装完成后自动将 `zsh` 设置为 `root` 和 `admin_user` 的默认 Shell，确保部署顺序正确。
- **自动切换**: 部署 `.bash_profile`，实现 SSH 登录自动切换到 Zsh。

**部署顺序优化** (2026-02-05):
- 采用 `notify` + `handler` 模式确保 shell 切换在 zsh 安装完成后执行
- 避免首次部署时因顺序问题导致 shell 未切换
- 实现真正的幂等性：重复部署不会重复修改 shell

## 4. 依赖关系
- 依赖网络连接以从 GitHub 下载 Zinit。
- 可选：openclaw（用于 AI 工具集成）
- 可选：bun（用于 JavaScript 包管理）

## 5. 维护与排查

### 常见问题

**问题: `.zshrc` 不能在 bash 中 source**
> `.zshrc` 包含 zsh 专用语法，不能在 bash 中执行。这是设计行为，不是 bug。部署已通过 `.bash_profile` 实现自动切换。

**问题: 首次登录 Zsh 很慢**
> 首次登录时 Zinit 需要下载插件，属于正常行为。后续登录将秒进。

**问题: 插件未生效**
> 在 Zsh 中运行 `zinit self-update` 或 `zinit update`。

**问题: `source ~/.zshrc` 时出现 "bad pattern" 错误**
> 已修复。模板中已添加 `setopt NO_NOMATCH`，防止 zsh 将方括号内容误解为 glob pattern。

**问题: 登录时出现 "compdef: command not found"**
> 已修复。openclaw 补全仅在交互式 shell 且补全系统初始化后才加载。

**问题: bun 全局安装的命令找不到（如 `qmd`）**
> 已修复。模板自动添加 `/root/.bun/bin` 到 PATH。

### 手动操作
- 手动切换到 Zsh: `exec zsh`
- 更新所有插件: `zinit update`
- 更新 Zinit 本身: `zinit self-update`

### 日志
Zsh 本身无独立日志，相关报错会直接显示在终端。

## 6. 已知问题与解决方案 (2026-02-14)

### 问题: 部署 zsh 角色时出现 "Permission denied" 错误
**现象**: 
```
PermissionError: [Errno 13] Permission denied: '/home/suai/AuroraOps/playbooks/personalization'
```

**原因**:
- 使用 Mitogen 策略 (`strategy = mitogen_linear`) 时存在已知 Bug
- 当任务使用 `become_user` 切换到其他用户时，Mitogen 会尝试访问当前工作目录 (CWD)
- 如果目标用户无法访问 Ansible 的 CWD，任务会失败

**解决方案**:
1. **角色级修复**: 在使用 `become_user` 的任务中添加 `chdir: /tmp`，强制任务在 /tmp 目录执行
2. **Makefile 级修复**: `make` 命令自动检测 `zsh` 角色 + 非 root 用户场景，切换到 `linear` 策略

**参考文档**:
- [Mitogen Issue #636](https://github.com/mitogen-hq/mitogen/issues/636)
- [Ansible Issue #19729](https://github.com/ansible/ansible/issues/19729)
