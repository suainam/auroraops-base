# 📦 Sub-collection: vps.personalization

> [!NOTE]
> **vps.personalization** 子集合是 AuroraOps 中用于管理服务器多用户权限、隔离 Root 环境并定制管理员特权环境的个性化配置套件。

---

## 🗺️ 角色全景：用户管理与环境加固

在 `auroraops-base` 中，本集合包含核心的用户管控组件：

- **[user_management](./roles/user_management/README.md)**: 企业级多用户权限管控。它负责创建专用的管理员用户、配置 sudo 权限、设置强密码、同步 Root 密钥、管理系统外壳 Shell 并对 root 用户密码实施安全轮转。

---

## ⚡ 极速操作入口汇总

在控制端完成 `make bootstrap` 后，您可以通过 Makefile 以极高的效率对 `personalization` 域或单个角色进行管理：

### 1. 大域操作（对全部个性化角色执行完整生命周期）
```bash
make check-personalization      # 1. 完整大域 Dry-Run 校验 (linear 稳定版)
make deploy-personalization     # 2. 完整大域物理部署 (Mitogen 极速版)
make verify-personalization     # 3. 完整大域实机物理状态核对
make rollback-personalization   # 4. 完整大域零污染回撤复原
```

### 2. 角色级精确操作（秒级响应）
```bash
make check-personalization.user_management
make deploy-personalization.user_management
make verify-personalization.user_management
make rollback-personalization.user_management
```

---

## 🔒 状态化与安全保障

`user_management` 严格遵守 AuroraOps 的 **Pre-deploy 基线快照契约**：
1. **密码与配置快照**：在执行 `deploy` 前，将自动拉取远端 target 主机上 `/etc/shadow` 中 root 及已有管理员用户的密码哈希快照，物理存储于 `/etc/ansible/facts.d/user_management.fact`。
2. **零污染回滚**：当执行 `rollback` 时，Ansible 将读取并还原前置密码哈希；如果是本次部署全新创建的管理员用户，在回滚时将对其进行**物理删除与账号清理**，实现对服务器无污染的无痕测试。
