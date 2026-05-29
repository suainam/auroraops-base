# ==============================================================================
# Environment Management
# ==============================================================================

ENV_FILE := .env_active

# ---------------------------------------------------------------------------
# 本地部署：make switch_local
# 场景：已登录到目标服务器，对当前机器自身部署
# 自动检测当前主机名，映射到 localhost
# ---------------------------------------------------------------------------
switch_local: ## 切换到本地部署模式 (Switch to local deployment mode)
	@HOSTNAME=$$(hostname)
	@echo "INVENTORY=inventories/prod.ini" > $(ENV_FILE)
	@echo "ANSIBLE_LIMIT=localhost" >> $(ENV_FILE)
	@echo "ANSIBLE_MODE=local" >> $(ENV_FILE)
	@echo ""
	@echo "==========================================="
	@echo "MODE: LOCAL (self-deployment)"
	@echo "CURRENT HOST: $$HOSTNAME"
	@echo "==========================================="

# ---------------------------------------------------------------------------
# 远程部署：make switch_remote
# 场景：从本地机器 SSH 到目标服务器部署（所有主机）
# ---------------------------------------------------------------------------
switch_remote: ## 切换到远程部署模式 (Switch to remote deployment mode)
	@echo "INVENTORY=inventories/prod.ini" > $(ENV_FILE)
	@echo "ANSIBLE_LIMIT=all" >> $(ENV_FILE)
	@echo "ANSIBLE_MODE=remote" >> $(ENV_FILE)
	@echo ""
	@echo "==========================================="
	@echo "MODE: REMOTE (SSH deployment)"
	@echo "TARGET: all hosts"
	@echo "==========================================="

# ---------------------------------------------------------------------------
# 远程部署特定主机：make switch_remote.hdy
# ---------------------------------------------------------------------------
switch_remote.%:
	@echo "INVENTORY=inventories/prod.ini" > $(ENV_FILE)
	@echo "ANSIBLE_LIMIT=$*" >> $(ENV_FILE)
	@echo "ANSIBLE_MODE=remote" >> $(ENV_FILE)
	@BECOME_KEY="ansible_become_$${BECOME_KEY_SUFFIX:-password}"; \
	HOST_VARS_FILE="inventories/host_vars/$*.yml"; \
	if [ ! -f "$$HOST_VARS_FILE" ]; then HOST_VARS_FILE="host_vars/$*.yml"; fi; \
	KEY_FILE=$$(sed -n 's/^ansible_ssh_private_key_file: "\(.*\)"/\1/p' "$$HOST_VARS_FILE" 2>/dev/null | head -n 1); \
	BECOME_PASSWORD=$$(sed -n "s/^$${BECOME_KEY}: \"\\(.*\\)\"/\\1/p" "$$HOST_VARS_FILE" 2>/dev/null | head -n 1); \
	EXTRA_ARGS=""; \
	if [ -n "$$KEY_FILE" ]; then \
		EXTRA_ARGS="--private-key $$KEY_FILE"; \
	fi; \
	if [ -n "$$BECOME_PASSWORD" ]; then \
		EXTRA_ARGS="$$EXTRA_ARGS -e ansible_become_pass=$$BECOME_PASSWORD"; \
	fi; \
	if [ -n "$$EXTRA_ARGS" ]; then \
		echo "ANSIBLE_EXTRA_ARGS=$$EXTRA_ARGS" >> $(ENV_FILE); \
	fi
	@echo ""
	@echo "==========================================="
	@echo "MODE: REMOTE (SSH deployment)"
	@echo "TARGET: $*"
	@echo "==========================================="

# ---------------------------------------------------------------------------
# 显示当前环境
# ---------------------------------------------------------------------------
env_show: ## 显示当前环境配置 (Show current environment configuration)
	@echo "==========================================="; \
	MODE=$$(grep "ANSIBLE_MODE" $(ENV_FILE) 2>/dev/null | cut -d= -f2 || echo "remote"); \
	TARGET=$$(grep "ANSIBLE_LIMIT" $(ENV_FILE) 2>/dev/null | cut -d= -f2 || echo "all"); \
	echo "MODE: $${MODE:-remote} | TARGET: $${TARGET}"; \
	echo "==========================================="; \
	cat $(ENV_FILE)
