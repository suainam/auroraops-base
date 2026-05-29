# auroraops-base Public Setup

这个公开仓只提供公开可分发的源码和最小脚手架。
它的目标是让公开边界清楚，同时保留最小可执行入口。

它不包含：
- 真实 inventories
- 真实 host_vars / group_vars
- 真实 secrets

最小启动：
```bash
make bootstrap
make bootstrap-status
make validate
make generate-playbooks
```

公开模板入口：
- `inventories/prod.ini.example`
- `inventories/host_vars/example-host.yml`
- `inventories/group_vars/all/base.example.yml`
- `secrets/vault.yml.example`

推荐执行顺序：
```bash
make switch_remote.my-vps
make env_show
make check-base
make deploy-base
make verify-base
make rollback-base
```

角色级精确入口：`make check-base.<role>` / `make deploy-base.<role>` / `make verify-base.<role>` / `make rollback-base.<role>`
