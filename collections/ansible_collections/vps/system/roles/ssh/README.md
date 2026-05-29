# Role: vps.system.ssh

## 1. 概述
该角色负责配置 OpenSSH Server。它采用现代化的 `sshd_config.d` 目录管理方式，确保 Ansible 管理的配置与系统默认配置隔离，便于维护和升级。

**新功能（2026-02-12）：**
- ✅ 自动检测端口变更并提示用户更新本地 SSH config
- ✅ 显式配置 `PubkeyAuthentication yes` 确保密钥认证始终启用
- ✅ 支持端口 22（标准）或自定义端口（如 6868）

## 2. 变量说明
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `ssh_port` | `6868` | SSH 监听端口（可在 host_vars 中覆盖为 22）。 |
| `ssh_permit_root_login` | `"yes"` | 是否允许 Root 登录（`yes`/`prohibit-password`/`no`）。 |
| `ssh_password_authentication` | `"no"` | 是否允许密码验证（建议仅使用密钥）。 |
| `ssh_pubkey_authentication` | `"yes"` | 是否允许公钥验证（**必须启用**）。 |
| `ssh_max_auth_tries` | `3` | 最大认证尝试次数（防暴力破解）。 |
| `ssh_login_grace_time` | `45` | 登录宽限时间（秒），超时未认证则断开。 |
| `ssh_client_alive_interval` | `60` | 客户端存活检测间隔。 |
| `ssh_client_alive_count_max` | `3` | 存活检测最大失败次数。 |

## 3. 内部逻辑
1.  **清理遗留**: 自动检测并删除直接写入 `/etc/ssh/sshd_config` 的旧配置行。
2.  **模块化配置**: 将所有自定义配置渲染至 `/etc/ssh/sshd_config.d/99-ansible.conf`。
3.  **配置生效**: 确保主配置文件包含 (`Include`) `.d` 目录下的配置。
4.  **验证**: 使用 `sshd -T` 验证配置语法的正确性以及关键参数的最终生效值。

## 4. 依赖关系
无。

## 5. 维护与排查

### 登录被拒绝 (Permission denied)

1. **检查认证方式**：
   ```bash
   sshd -T | grep -E '(pubkey|password)authentication'
   ```

2. **检查公钥文件权限**：
   ```bash
   # 正确权限：
   ~/.ssh/         700
   ~/.ssh/*_key    600
   authorized_keys 600
   ```

3. **检查公钥内容匹配**：
   ```bash
   # 本地公钥：
   cat ~/.ssh/<key>.pub

   # 服务器公钥：
   cat ~/.ssh/authorized_keys
   ```

### 服务无法启动

```bash
# 检查配置语法
sshd -t

# 查看详细错误
journalctl -u ssh -n 20
```

### SSH 服务相关命令

| 操作 | 命令 |
|------|------|
| 检查状态 | `systemctl status ssh` |
| 重启服务 | `systemctl restart ssh` |
| 查看监听端口 | `ss -tlnp | grep sshd` |
| 测试配置 | `sshd -T | grep <option>` |

## 6. 安全配置建议

### 避免被锁在服务器外的流程

1. **先配置公钥**：
   - 确保目标用户的 `~/.ssh/authorized_keys` 已包含你的公钥
   - 测试公钥登录：`ssh -i ~/.ssh/<key> -p <port> <user>@<host>`

2. **再禁用密码登录**：
   ```yaml
   # group_vars/all/ssh.yml
   ssh_password_authentication: "no"
   ```

3. **验证流程**：
   ```bash
   # 1. 语法检查（干跑）
   make check-system.ssh

   # 2. 确认配置无误后部署
   make deploy-system.ssh

   # 3. 测试新会话登录（保留旧会话作为备份）
   ssh -i ~/.ssh/<key> -p <port> <user>@<host>
   ```

### 推荐的配置组合

| 场景 | `ssh_password_authentication` | `ssh_pubkey_authentication` | `ssh_permit_root_login` |
|------|------------------------------|----------------------------|------------------------|
| 最安全 | no | yes | prohibit-password |
| 允许密码备份 | yes | yes | yes |
| 禁用 root | no | yes | no |

### 配置文件位置

- **主配置文件**：`/etc/ssh/sshd_config`（保持默认，不直接修改）
- **Ansible 覆盖**：`/etc/ssh/sshd_config.d/99-ansible.conf`（由本角色管理）
- **全局变量**：`inventories/group_vars/all/ssh.yml`
- **主机变量**：`inventories/host_vars/<host>.yml`

## 7. 常见问题排查与避障 (Troubleshooting)

### SSH 端口/IP 变更后的连通性问题

> [!NOTE]
> **自动化提示**：本角色已集成自动化迁移逻辑。当 `ssh_port` 变更时，角色会通过 `delegate_to: localhost` 自动尝试更新本地 `~/.ssh/config`、清理旧指纹并重新建立信任。

若自动迁移因权限或其他原因失败，请参考以下手动排障步骤：

#### 1. 清理本地主机密钥 (Known Hosts)
Ansible 在非交互模式下对密钥匹配非常严格。请清理旧的指纹信息（包括主机名和 **IP 地址**）：
```bash
# 按主机名清理
ssh-keygen -R <hostname>
ssh-keygen -R [<hostname>]:<port>

# 按 IP 清理（非常重要，常被忽视）
ssh-keygen -R <ip_address>
ssh-keygen -R [<ip_address>]:<port>
```

#### 2. 清理 SSH 连接复用缓存 (ControlMaster)
这是最隐蔽的问题。`ansible.cfg` 或 `~/.ssh/config` 启用了 `ControlMaster`，会在本地生成持久化 Socket。
即使你重启了 Terminal，由于 Socket 文件驻留在磁盘上，旧的连接状态依然会被复用。

**常见 Socket 位置**：
- `/tmp/ansible-ssh-*` (Ansible 默认)
- `~/.ssh/cm-*` (系统 SSH 常用)

**解决方法**：
- **手动清理**：`rm /tmp/ansible-ssh-* ~/.ssh/cm-*`
- **强制重连**：执行命令时临时禁用复用：
  ```bash
  ANSIBLE_SSH_ARGS="-o ControlMaster=no" make <target>
  ```

### 登录被拒绝 (Permission denied)

1. **检查认证方式**：
   ```bash
   sshd -T | grep -E '(pubkey|password)authentication'
   ```

2. **检查公钥文件权限**：
   - `~/.ssh/` : `700`
   - `~/.ssh/authorized_keys` : `600`
   - 私钥文件 : `600`

### 服务相关诊断

| 操作 | 命令 |
|------|------|
| 检查配置语法 | `sshd -t` |
| 查看详细日志 | `journalctl -u ssh -n 50` |
| 查看监听端口 | `ss -tlnp | grep sshd` |
| 查看最终生效配置 | `sshd -T` |
