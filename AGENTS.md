# auroraops-base Agent Operating Directives

## 1. 仓库定位与职责 (Child Capability Repository)
- **定位**：公开子仓库，提供纯净的 Linux 系统通用底层基座能力。
- **边界**：
  - 仅包含通用操作系统初始化、网络基础防火墙、系统级资源限制与内核参数。
  - **严禁**包含特定应用、Docker、外部穿透协议（ZeroTier/Cloudflare）、破坏性重装或业务端口。
  - **严禁**包含生产环境密钥、主机 IP、私有 inventory。
- **父仓关系**：被父仓 `auroraops-control` 通过 Release Tag + Commit Hash 精确锁定使用。

---

## 2. 包含角色列表 (共 13 个)
- `system/base`: 裸机通用基础配置（去旧 monolith 路径）
- `system/init`: 系统引导前置检查
- `system/fail2ban`: 通用防暴破服务
- `system/firewall`: 通用 UFW 底层规则与 NAT（已剥离业务端口与 Docker）
- `system/journald`: systemd 日志配置
- `system/limits`: Linux limits 资源限制
- `system/logrotate`: 通用系统日志轮替
- `system/python_environment`: 基础 Python 运行环境
- `system/ssh`: SSH 安全加固与端口管理
- `system/swap`: Swap 虚拟内存管理
- `system/sysctl`: 内核参数优化
- `system/unattended_upgrades`: 无人值守安全更新
- `system/zram`: 内存压缩块设备

---

## 3. 开发与测试指南
1. **修改 Role**：
   - 保持 stateful lifecycle 契约：`preflight`, `apply`, `verify`, `rollback`。
   - 所有更改必须具备幂等性（再次执行 `check` 必须 `changed=0`）。
2. **重新生成 Playbook**：
   ```bash
   python3 scripts/generate_ansible_playbooks.py
   ```
3. **语法与 Lint 检查**：
   ```bash
   make syntax-check
   ```
4. **提交与发版**：
   - 更新 `CHANGELOG.md` 与 `galaxy.yml` 版本号。
   - 提交推送并打 release tag，通知父仓更新版本锁定。
