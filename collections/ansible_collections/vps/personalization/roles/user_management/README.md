# User Management Role

## 1. 概述
本角色用于管理服务器上的管理级用户。它负责创建管理员用户、配置权限、设置密码、同步 root 用户的个性化配置，以及管理 root 用户密码。

## 2. 变量说明 (Defaults)
| 变量名 | 来源 | 描述 |
| :--- | :--- | :--- |
| `admin_user` | Vault | 管理员用户名。 |
| `admin_password` | Vault | 管理员密码。 |
| `vault_root_password` | Vault | root 用户密码。 |
| `user_management_groups` | defaults | 管理员用户所属的用户组（默认: `["sudo"]`）。 |
| `user_management_shell` | defaults | 管理员用户的默认 Shell（默认: `/bin/zsh`）。 |

## 3. 生命周期
- `preflight`: 采集现状，读取/校验 baseline；若目标用户或 role-owned 路径已存在但尚无 fact，则采纳现状作为 rollback baseline。
- `apply`: 仅在非 check mode 落盘 baseline，创建/更新 admin 用户，设置 root/admin 密码，管理 `{{ user_management_admin_home }}`、`.ssh` 与 `authorized_keys`。
- `verify`: 只做只读验收，验证 baseline、账号 shell/group/home、以及 role-owned 路径的存在性和权限。
- `rollback`: 按 baseline 恢复 root/admin 密码、admin 账号属性与 role-owned 路径内容；若 admin 用户是本次部署新建，则删除并清理 fact。

### 功能清单

#### 部署阶段 (deploy)
- [x] 创建/确保 admin 用户存在
- [x] 设置 admin 用户密码（每次执行都会更新）
- [x] 配置 admin 用户的 shell 和用户组
- [x] 创建并配置 admin 用户的 `.ssh` 目录（0700）
- [x] 复制 root 的 `authorized_keys` 到 admin 用户（0600）
- [x] 为 root/admin 密码、admin 账号属性、`/home/{{ admin_user }}`、`.ssh`、`authorized_keys` 落 rollback baseline
- [x] 设置 root 用户密码（每次执行都会更新）

#### 验证阶段 (verify)
- [x] 验证 admin 用户存在
- [x] 验证 admin 用户 home 路径正确
- [x] 验证 admin 用户的 shell 正确
- [x] 验证 admin 用户在预期组中（sudo）
- [x] 验证 root 用户存在
- [x] 验证 baseline 满足 rollback 前提
- [x] 验证 `/home/{{ admin_user }}` 权限（0755）
- [x] 验证 `.ssh` 目录权限（0700）
- [x] 验证 `authorized_keys` 文件权限（0600）

#### 回滚阶段 (rollback)
- [x] 恢复 root/admin 密码哈希
- [x] 恢复 admin 用户原始 shell/home/groups
- [x] 恢复或删除 role-owned 路径到部署前状态
- [x] 若 admin 用户在部署前不存在，则删除该用户

## 4. 依赖关系
- 依赖于 `zsh` 角色提前提供 `/bin/zsh`。
- 不负责 `.vimrc`、`.zshrc`、`zinit` 等跨角色配置同步；这些由对应个性化角色自行验证。

## 5. 维护与排查
- 如果用户无法登录，请检查 `/etc/passwd` 和 `/etc/shadow`。
- 检查 `/home/{{ admin_user }}/` 目录的权限是否归属正确。
- 密码验证失败常见原因：密码哈希值为 `*`（锁定）或 `!`（未设置）。
