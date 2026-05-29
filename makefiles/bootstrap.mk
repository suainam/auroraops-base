# ==============================================================================
# AuroraOps Bootstrap (Final Verified & Audited)
# ==============================================================================

SHELL := /bin/bash
PROJECT_ROOT := $(shell pwd)
SUDO := $(shell which sudo 2>/dev/null)

# 确保新版路径在最前，彻底解决 2.9 版本干扰
SAFE_PATH := $(HOME)/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 智能源探测
IS_CN := $(shell curl -I -s --connect-timeout 2 https://pypi.tuna.tsinghua.edu.cn > /dev/null && echo "yes" || echo "no")
ifeq ($(IS_CN), yes)
    export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
    MIRROR_MSG := China (Tsinghua Mirror)
else
    MIRROR_MSG := International (Default PyPI)
endif

.PHONY: bootstrap bootstrap-status _ensure_pipx _install_tools _config_mitogen _verify

bootstrap: _ensure_pipx _install_tools _config_mitogen _ensure_inventory_vars _verify  ## 初始化开发环境 (Initialize development environment)
	@echo "Step 7: Generating Playbooks..."
	@$(MAKE) generate-playbooks
	@echo "----------------------------------------------------------------"
	@echo 'Bootstrap complete! [$(MIRROR_MSG)]'
	@echo "----------------------------------------------------------------"

_ensure_pipx:
	@echo "Step 1: Checking infrastructure & Python version..."
	@PATH=$(SAFE_PATH) ; \
	python_ver=$$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0"); \
	v_python=$$(command -v python3.12 || command -v python3); \
	echo "  -> Found Python $$python_ver"; \
	if [[ $$(echo -e "$$python_ver\n3.11" | sort -V | head -n1) == "3.11" ]]; then \
		echo "  -> System Python $$python_ver is modern (>=3.11), skipping installation."; \
	elif command -v python3.12 > /dev/null; then \
		echo "  -> Found Python 3.12 command, skipping installation."; \
	else \
		echo "  -> Python version too low ($$python_ver) and 3.12 missing. Installing from source..."; \
		[ -f /etc/debian_version ] && $(SUDO) apt-get update && \
		$(SUDO) apt-get install -y build-essential libssl-dev zlib1g-dev libncurses5-dev libncursesw5-dev libreadline-dev libsqlite3-dev libgdbm-dev libdb5.3-dev libbz2-dev libexpat1-dev liblzma-dev libffi-dev uuid-dev wget curl ; \
		cd /tmp && wget -N https://www.python.org/ftp/python/3.12.9/Python-3.12.9.tar.xz && \
		tar -xf Python-3.12.9.tar.xz && cd Python-3.12.9 && \
		make distclean || true; \
		./configure --with-system-ffi --with-computed-gotos --enable-loadable-sqlite-extensions --prefix=/usr/local && \
		make -j$$(nproc) && $(SUDO) make altinstall ; \
	fi; \
	if ! command -v pipx > /dev/null; then \
		if [[ "$$v_python" == "/usr/local/bin/python3.12" ]]; then \
			env -u ALL_PROXY -u HTTPS_PROXY -u HTTP_PROXY -u all_proxy -u https_proxy -u http_proxy -u no_proxy -u NO_PROXY \
				$$v_python -m pip install --user --upgrade pip pipx PySocks || \
			([ -f /etc/debian_version ] && $(SUDO) apt-get update && $(SUDO) apt-get install -y pipx) || \
			$$v_python -m pip install --user pipx PySocks ; \
		else \
			[ -f /etc/debian_version ] && $(SUDO) apt-get update || true; \
			$(SUDO) apt-get install -y python3-pip pipx || $$v_python -m pip install --user pipx ; \
		fi; \
		if [ -x "$$HOME/.local/bin/pipx" ]; then PATH="$$HOME/.local/bin:$$PATH"; fi; \
		command -v pipx > /dev/null || { echo "Error: pipx install failed."; exit 1; }; \
		pipx ensurepath --force; \
	fi

_install_tools:
	@echo "Step 2: Installing/Updating core tools & dependencies..."
	@PATH=$(SAFE_PATH) ; \
	V_PYTHON=$$(command -v python3.12 || command -v python3); \
	CUR_VENV_PY=$$(/root/.local/pipx/venvs/ansible-core/bin/python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0"); \
	if [[ $$CUR_VENV_PY != "3.12" && "$$V_PYTHON" == "/usr/local/bin/python3.12" ]]; then \
		echo "  -> Migrating venvs to Python 3.12..."; \
		pipx reinstall ansible-core --python $$V_PYTHON 2>/dev/null || pipx install ansible-core --python $$V_PYTHON ; \
		pipx reinstall ansible-lint --python $$V_PYTHON 2>/dev/null || pipx install ansible-lint --python $$V_PYTHON ; \
	else \
		pipx install ansible-core --python $$V_PYTHON 2>/dev/null || pipx upgrade ansible-core ; \
		pipx install ansible-lint --python $$V_PYTHON 2>/dev/null || pipx upgrade ansible-lint ; \
	fi; \
	pipx runpip ansible-core install jmespath cryptography passlib redis requests docker 'mitogen==0.3.41' > /dev/null 2>&1 || true ; \
	echo 'export PATH="$$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' > $(PROJECT_ROOT)/.ansible_env ; \
	VENV_BASE=$$(pipx environment --value PIPX_HOME 2>/dev/null || echo "$$HOME/.local/pipx"); \
	echo "ANSIBLE_VENV_BIN=$$VENV_BASE/venvs/ansible-core/bin" >> $(PROJECT_ROOT)/.ansible_env ; \
	echo "LINT_VENV_BIN=$$VENV_BASE/venvs/ansible-lint/bin" >> $(PROJECT_ROOT)/.ansible_env

_config_mitogen:
	@echo "Step 3: Validating Mitogen installation..."
	@PATH=$(SAFE_PATH) ; \
	VENV_BASE=$$(pipx environment --value PIPX_HOME 2>/dev/null || echo "$$HOME/.local/pipx"); \
	ANS_PYTHON="$$VENV_BASE/venvs/ansible-core/bin/python"; \
	MITOGEN_PATH=$$($$ANS_PYTHON -c "import ansible_mitogen, os; print(os.path.join(os.path.dirname(ansible_mitogen.__file__), 'plugins/strategy'))" 2>/dev/null); \
	if [ -n "$$MITOGEN_PATH" ]; then \
		echo "  -> Mitogen Strategry resolved at: $$MITOGEN_PATH"; \
	else \
		echo "Error: Mitogen not found."; exit 1; \
	fi

_ensure_inventory_vars:
	@echo "Step 4: Ensuring inventory variables..."
	@mkdir -p inventories/group_vars/all
	@if [ ! -L inventories/group_vars/all/vault.yml ] && [ ! -f inventories/group_vars/all/vault.yml ]; then \
		ln -s ../../../secrets/vault.yml inventories/group_vars/all/vault.yml; \
		echo "  -> Created symlink: inventories/group_vars/all/vault.yml -> secrets/vault.yml"; \
	elif [ -L inventories/group_vars/all/vault.yml ]; then \
		echo "  -> Symlink already exists: inventories/group_vars/all/vault.yml"; \
	else \
		echo "  -> WARNING: vault.yml already exists as file, skipping"; \
	fi

_verify:
	@echo "Step 5: Verification & Assets..."
	@PATH=$(SAFE_PATH) ; \
	$(MAKE) install-dependencies ; \
	printf "  - Using Ansible at: %s\n" "$$(which ansible)" ; \
	printf "  - Ansible Version:  %s\n" "$$(ansible --version | head -n 1)" ; \
	# 改进的路径提取逻辑，兼容新版列表格式输出 \
	MIT_PATH_RAW=$$(ansible-config dump | grep -i "STRATEGY_PLUGIN_PATH" | sed "s/.*= //"); \
	printf "  - Mitogen Path:     %s\n" "$$MIT_PATH_RAW" ; \
	printf "  - Active Strategy:  %s\n" "$$(ansible-config dump | grep -i "DEFAULT_STRATEGY(" | awk '{print $$NF}')"

bootstrap-status:  ## 检查 Bootstrap 状态 (Check bootstrap status)
	@echo "Bootstrap Status Check"
	@echo "----------------------------------------------------------------"
	@PATH=$(SAFE_PATH) ; \
	if command -v ansible > /dev/null 2>&1; then \
		printf "✓ Ansible:    %s\n" "$$(ansible --version | head -n 1)"; \
	else \
		echo "✗ Ansible:    Not installed"; \
	fi; \
	if command -v ansible-lint > /dev/null 2>&1; then \
		printf "✓ Lint:       %s\n" "$$(ansible-lint --version | head -n 1)"; \
	else \
		echo "✗ Lint:       Not installed"; \
	fi; \
	if [ -f .ansible_env ]; then \
		echo "✓ Environment: .ansible_env exists"; \
	else \
		echo "✗ Environment: .ansible_env missing"; \
	fi; \
	if [ -f .ansible_env ]; then . ./.ansible_env; fi; \
	ANS_PYTHON="$$ANSIBLE_VENV_BIN/python"; \
	MITOGEN_PATH=$$($$ANS_PYTHON -c "import ansible_mitogen, os; print(os.path.join(os.path.dirname(ansible_mitogen.__file__), 'plugins/strategy'))" 2>/dev/null); \
	if [ -n "$$MITOGEN_PATH" ] && grep -q "strategy = mitogen_" ansible.cfg; then \
		echo "✓ Mitogen:     Configured"; \
	else \
		echo "✗ Mitogen:     Not configured"; \
	fi
	@echo "----------------------------------------------------------------"
