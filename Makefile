# ==============================================================================
# AuroraOps Makefile - Automation interface
# ==============================================================================

.DEFAULT_GOAL := help
comma := ,

# --- 1. Environment & Configuration ---

# Get current directory dynamically (support non-root users)
CURRENT_DIR := $(shell pwd)
export ANSIBLE_COLLECTIONS_PATH ?= $(CURRENT_DIR)/collections
export ANSIBLE_VAULT_PASSWORD_FILE ?= $(CURRENT_DIR)/.vault_pass.txt
export ANSIBLE_DEPRECATION_WARNINGS := False

# Try to load environment from .ansible_env
ifneq ($(wildcard .ansible_env),)
    include .ansible_env
    PYTHON_BIN ?= $(ANSIBLE_VENV_BIN)/python
else
    # Fallback if bootstrapping hasn't run
    ANSIBLE_VENV_BIN ?= $(HOME)/.local/bin
    LINT_VENV_BIN ?= $(HOME)/.local/bin
    # Detect python3 vs python
    PYTHON_BIN ?= $(if $(wildcard $(ANSIBLE_VENV_BIN)/python),$(ANSIBLE_VENV_BIN)/python,$(ANSIBLE_VENV_BIN)/python3)
endif

INVENTORY ?= inventories/prod.ini

# 读取环境切换配置
ifneq ($(wildcard .env_active),)
    include .env_active
endif

# Command Definitions
PYTHON           = $(PYTHON_BIN)
# Get active Mitogen plugin path on the fly
MITOGEN_STRATEGY_PATH := $(shell $(PYTHON_BIN) -c "import ansible_mitogen, os; print(os.path.join(os.path.dirname(ansible_mitogen.__file__), 'plugins/strategy'))" 2>/dev/null)
export ANSIBLE_STRATEGY_PLUGINS := $(MITOGEN_STRATEGY_PATH)

# Ensure ANSIBLE_CONFIG is prioritized to current directory
export ANSIBLE_CONFIG := $(CURRENT_DIR)/ansible.cfg

# 动态性能分析支持: 使用 make <target> BENCH=1 开启
ANSIBLE_PLAYBOOK = $(if $(BENCH),ANSIBLE_CALLBACKS_ENABLED="ansible.posix.timer$(comma)ansible.posix.profile_tasks",) \
	$(ANSIBLE_VENV_BIN)/ansible-playbook -i $(INVENTORY) \
	$(if $(filter all,$(ANSIBLE_LIMIT)),,--limit "$(ANSIBLE_LIMIT)") \
	$(ANSIBLE_EXTRA_ARGS)
ANSIBLE_GALAXY   = $(ANSIBLE_VENV_BIN)/ansible-galaxy
ANSIBLE_LINT     = $(LINT_VENV_BIN)/ansible-lint

# --- 2. Include Modules ---

include makefiles/ops.mk
include makefiles/utils.mk
include makefiles/bootstrap.mk
include makefiles/env.mk

# --- 3. Help ---

.PHONY: help
help:
	@echo "AuroraOps Management Interface"
	@echo "Usage: make <target> [FORCE=true] [BENCH=1]"
	@echo ""
	@echo "Core Lifecycle:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "^  .*(deploy|verify|rollback|check) " | grep -v "check-" | head -4 || true
	@echo ""
	@echo "Validation & Compliance:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(validate|check-|fix-)" || true
	@echo ""
	@echo "Development Utilities:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(install-dependencies|generate-playbooks|verify-phase0)" || true
	@echo ""
	@echo "Bootstrap (Environment Setup):"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "bootstrap" || true
	@echo ""
	@echo "Environment Management:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "env_|switch_" || true
	@echo "  \033[36mswitch_remote.<host>    \033[0m 切换到指定主机远程部署 (Switch to specific host)"
	@echo ""
	@echo "Backup & Restore (Rustic):"
	@echo "  \033[36mrustic-backup-now       \033[0m 立即执行备份 (当前目标主机)"
	@echo "  \033[36mrustic-snapshots-local  \033[0m 查询本地快照 (/opt/backups/complete)"
	@echo "  \033[36mrustic-snapshots-cloud  \033[0m 查询云端快照 (SOURCE=onedrive/gdrive)"
	@echo "  \033[36mrustic-unlock           \033[0m 解锁所有仓库 (本地+云端)"
	@echo "  \033[36mrustic-prune            \033[0m 清理旧快照 (按保留策略)"
	@echo "  \033[36mrustic-check-health     \033[0m 触发仓库完整性检查"
	@echo "  \033[36mrustic-baseline         \033[0m 创建基线快照 (完整备份)"
	@echo ""
	@echo "Backup & Restore (Legacy):"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(docker-backup|system-backup)" || true
	@echo ""
	@echo "Restore Operations:"
	@echo "  \033[36mrestore-help            \033[0m 显示完整恢复命令帮助"
	@echo "  \033[36mrestore-system          \033[0m 恢复系统配置到当前主机"
	@echo "  \033[36mrestore-*               \033[0m 更多恢复选项: make restore-help"
	@echo ""
	@echo "Testing (Fast Framework):"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "test-" || true
	@echo ""
	@echo "Docker Management:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "docker-" || true
	@echo ""
	@echo "Additional Options:"
	@echo "  FORCE=true              强制覆盖现有安装"
	@echo "  BENCH=1                 启用性能分析"
	@echo "  WORKERS=N               并行测试工作进程数 (默认: 5)"
	@echo "  JOBS=N                  并行任务数 (默认: 2)"
	@echo "  SOURCE=<remote>         云端存储源 (onedrive/gdrive)"
	@echo "  SNAPSHOT=<id>           快照 ID (默认: latest)"
	@echo ""
	@echo "Dynamic Targets (Pattern Matching):"
	@echo "  make <action>-<scope>"
	@echo "    Actions: deploy, verify, rollback, check"
	@echo "    Scopes:  phaseX, domain (e.g. system), domain.role (e.g. system.ssh)"

# Public split aliases
.PHONY: check-base deploy-base verify-base rollback-base smoke-base-docker
check-base: ## Dry-run AuroraOps base bootstrap, hardening, and foundation layers
	@$(MAKE) check-phase0
	@$(MAKE) check-phase1
	@$(MAKE) check-phase2

deploy-base: ## Deploy AuroraOps base bootstrap, hardening, and foundation layers
	@$(MAKE) deploy-phase0
	@$(MAKE) deploy-phase1
	@$(MAKE) deploy-phase2

verify-base: ## Verify AuroraOps base bootstrap, hardening, and foundation layers
	@$(MAKE) verify-phase0
	@$(MAKE) verify-phase1
	@$(MAKE) verify-phase2

rollback-base: ## Roll back AuroraOps base bootstrap, hardening, and foundation layers
	@$(MAKE) rollback-phase2
	@$(MAKE) rollback-phase1
	@$(MAKE) rollback-phase0

smoke-base-docker: ## Run fast Docker smoke test for public AuroraOps base
	@bash scripts/run_public_base_docker_smoke.sh

check-base.benchmark: ## Check single base role: benchmark
	@$(MAKE) check-system.benchmark

check-base.base: ## Check single base role: base
	@$(MAKE) check-system.base

check-base.fail2ban: ## Check single base role: fail2ban
	@$(MAKE) check-system.fail2ban

check-base.firewall: ## Check single base role: firewall
	@$(MAKE) check-system.firewall

check-base.init: ## Check single base role: init
	@$(MAKE) check-system.init

check-base.journald: ## Check single base role: journald
	@$(MAKE) check-system.journald

check-base.limits: ## Check single base role: limits
	@$(MAKE) check-system.limits

check-base.logrotate: ## Check single base role: logrotate
	@$(MAKE) check-system.logrotate

check-base.python_environment: ## Check single base role: python_environment
	@$(MAKE) check-system.python_environment

check-base.reinstall: ## Check single base role: reinstall
	@$(MAKE) check-system.reinstall

check-base.ssh: ## Check single base role: ssh
	@$(MAKE) check-system.ssh

check-base.swap: ## Check single base role: swap
	@$(MAKE) check-system.swap

check-base.sysctl: ## Check single base role: sysctl
	@$(MAKE) check-system.sysctl

check-base.systemd_priority: ## Check single base role: systemd_priority
	@$(MAKE) check-system.systemd_priority

check-base.unattended_upgrades: ## Check single base role: unattended_upgrades
	@$(MAKE) check-system.unattended_upgrades

check-base.user_management: ## Check single base role: user_management
	@$(MAKE) check-personalization.user_management

check-base.zerotier: ## Check single base role: zerotier
	@$(MAKE) check-system.zerotier

check-base.zram: ## Check single base role: zram
	@$(MAKE) check-system.zram

deploy-base.benchmark: ## Deploy single base role: benchmark
	@$(MAKE) deploy-system.benchmark

deploy-base.base: ## Deploy single base role: base
	@$(MAKE) deploy-system.base

deploy-base.fail2ban: ## Deploy single base role: fail2ban
	@$(MAKE) deploy-system.fail2ban

deploy-base.firewall: ## Deploy single base role: firewall
	@$(MAKE) deploy-system.firewall

deploy-base.init: ## Deploy single base role: init
	@$(MAKE) deploy-system.init

deploy-base.journald: ## Deploy single base role: journald
	@$(MAKE) deploy-system.journald

deploy-base.limits: ## Deploy single base role: limits
	@$(MAKE) deploy-system.limits

deploy-base.logrotate: ## Deploy single base role: logrotate
	@$(MAKE) deploy-system.logrotate

deploy-base.python_environment: ## Deploy single base role: python_environment
	@$(MAKE) deploy-system.python_environment

deploy-base.reinstall: ## Deploy single base role: reinstall
	@$(MAKE) deploy-system.reinstall

deploy-base.ssh: ## Deploy single base role: ssh
	@$(MAKE) deploy-system.ssh

deploy-base.swap: ## Deploy single base role: swap
	@$(MAKE) deploy-system.swap

deploy-base.sysctl: ## Deploy single base role: sysctl
	@$(MAKE) deploy-system.sysctl

deploy-base.systemd_priority: ## Deploy single base role: systemd_priority
	@$(MAKE) deploy-system.systemd_priority

deploy-base.unattended_upgrades: ## Deploy single base role: unattended_upgrades
	@$(MAKE) deploy-system.unattended_upgrades

deploy-base.user_management: ## Deploy single base role: user_management
	@$(MAKE) deploy-personalization.user_management

deploy-base.zerotier: ## Deploy single base role: zerotier
	@$(MAKE) deploy-system.zerotier

deploy-base.zram: ## Deploy single base role: zram
	@$(MAKE) deploy-system.zram

verify-base.benchmark: ## Verify single base role: benchmark
	@$(MAKE) verify-system.benchmark

verify-base.base: ## Verify single base role: base
	@$(MAKE) verify-system.base

verify-base.fail2ban: ## Verify single base role: fail2ban
	@$(MAKE) verify-system.fail2ban

verify-base.firewall: ## Verify single base role: firewall
	@$(MAKE) verify-system.firewall

verify-base.init: ## Verify single base role: init
	@$(MAKE) verify-system.init

verify-base.journald: ## Verify single base role: journald
	@$(MAKE) verify-system.journald

verify-base.limits: ## Verify single base role: limits
	@$(MAKE) verify-system.limits

verify-base.logrotate: ## Verify single base role: logrotate
	@$(MAKE) verify-system.logrotate

verify-base.python_environment: ## Verify single base role: python_environment
	@$(MAKE) verify-system.python_environment

verify-base.reinstall: ## Verify single base role: reinstall
	@$(MAKE) verify-system.reinstall

verify-base.ssh: ## Verify single base role: ssh
	@$(MAKE) verify-system.ssh

verify-base.swap: ## Verify single base role: swap
	@$(MAKE) verify-system.swap

verify-base.sysctl: ## Verify single base role: sysctl
	@$(MAKE) verify-system.sysctl

verify-base.systemd_priority: ## Verify single base role: systemd_priority
	@$(MAKE) verify-system.systemd_priority

verify-base.unattended_upgrades: ## Verify single base role: unattended_upgrades
	@$(MAKE) verify-system.unattended_upgrades

verify-base.user_management: ## Verify single base role: user_management
	@$(MAKE) verify-personalization.user_management

verify-base.zerotier: ## Verify single base role: zerotier
	@$(MAKE) verify-system.zerotier

verify-base.zram: ## Verify single base role: zram
	@$(MAKE) verify-system.zram

rollback-base.benchmark: ## Rollback single base role: benchmark
	@$(MAKE) rollback-system.benchmark

rollback-base.base: ## Rollback single base role: base
	@$(MAKE) rollback-system.base

rollback-base.fail2ban: ## Rollback single base role: fail2ban
	@$(MAKE) rollback-system.fail2ban

rollback-base.firewall: ## Rollback single base role: firewall
	@$(MAKE) rollback-system.firewall

rollback-base.init: ## Rollback single base role: init
	@$(MAKE) rollback-system.init

rollback-base.journald: ## Rollback single base role: journald
	@$(MAKE) rollback-system.journald

rollback-base.limits: ## Rollback single base role: limits
	@$(MAKE) rollback-system.limits

rollback-base.logrotate: ## Rollback single base role: logrotate
	@$(MAKE) rollback-system.logrotate

rollback-base.python_environment: ## Rollback single base role: python_environment
	@$(MAKE) rollback-system.python_environment

rollback-base.reinstall: ## Rollback single base role: reinstall
	@$(MAKE) rollback-system.reinstall

rollback-base.ssh: ## Rollback single base role: ssh
	@$(MAKE) rollback-system.ssh

rollback-base.swap: ## Rollback single base role: swap
	@$(MAKE) rollback-system.swap

rollback-base.sysctl: ## Rollback single base role: sysctl
	@$(MAKE) rollback-system.sysctl

rollback-base.systemd_priority: ## Rollback single base role: systemd_priority
	@$(MAKE) rollback-system.systemd_priority

rollback-base.unattended_upgrades: ## Rollback single base role: unattended_upgrades
	@$(MAKE) rollback-system.unattended_upgrades

rollback-base.user_management: ## Rollback single base role: user_management
	@$(MAKE) rollback-personalization.user_management

rollback-base.zerotier: ## Rollback single base role: zerotier
	@$(MAKE) rollback-system.zerotier

rollback-base.zram: ## Rollback single base role: zram
	@$(MAKE) rollback-system.zram

