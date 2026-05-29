# AuroraOps Base

AuroraOps Base 是公开的首装仓。
目标是让你在本地 clone 后，只修改模板配置文件，就能完成一台全新 Debian 12/13 VPS 的基础设施首装。

## Responsibilities

- 新 VPS 首装闭环
- 基础系统与安全加固
- 统一 Python 运行环境
- 基线网络与远程接入
- 最小 inventory / host_vars / group_vars / secrets 模板

## Not Included

- 真实生产 inventory / host_vars / group_vars
- 真实 secrets
- services / ops 角色
- 个性化工具角色（除 `user_management`）
- 监控、备份、CI/CD

## Quick Start

```bash
make bootstrap
make bootstrap-status
cp inventories/prod.ini.example inventories/prod.ini
mkdir -p inventories/host_vars
cp inventories/host_vars/example-host.yml inventories/host_vars/my-vps.yml
cp inventories/group_vars/all/base.example.yml inventories/group_vars/all/base.yml
cp secrets/vault.yml.example secrets/vault.yml
make validate
make generate-playbooks
make switch_remote.my-vps
make env_show
make check-base
make deploy-base
make verify-base
make rollback-base
```

按角色精确执行：

```bash
make check-base.swap
make deploy-base.firewall
make verify-base.user_management
make rollback-base.zram
```

容器化真机验收入口：

```bash
bash scripts/run_public_base_remote_acceptance.sh --source-host-vars /path/to/host_vars.yml
```

Bootstrap 只负责本地 Ansible 环境，不会改远端主机。
`switch_remote.<host>` 会把目标锁到 `inventories/prod.ini` 里的指定主机。

维护者快速烟雾测试：

```bash
make smoke-base-docker
```

这会在容器里执行依赖安装、playbook 生成、语法检查，以及 `check-base` / `deploy-base` / `verify-base` 入口探测。

## Suggested Workflow

1. 修改 `inventories/prod.ini`，写入目标主机地址。
2. 修改 `inventories/host_vars/my-vps.yml`，写入主机名、SSH 端口、登录用户和私钥路径。
3. 修改 `inventories/group_vars/all/base.yml`，调整基础设施开关。
4. 修改 `secrets/vault.yml`，填入私有环境需要的值。
5. 先执行 `make validate`，再执行 `make generate-playbooks`。
6. 使用 `make switch_remote.my-vps` 和 `make env_show` 确认目标主机。
7. 执行 `make check-base` -> `make deploy-base` -> `make verify-base`；需要回退时执行 `make rollback-base`。

## Maintainer Validation

仓库保留了 `tests/pytest.ini` 和 `scripts/run_pytest.py`，用于后续补充公开仓自验证。
