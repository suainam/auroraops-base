# ==============================================================================
# Core Macros & Pattern Rules
# ==============================================================================

# Dynamic Strategy Plugins Path for Mitogen - Inherited from Makefile

# Macro: Dynamic Ansible Execution logic
# Parses the make target to extract Action, Target, and Tags
# Example: deploy-services.nginx -> ACTION=deploy, TARGET=services.nginx, TAGS=nginx
# Support FORCE=true to force overwrite existing installations
define run_ansible
	$(eval ACTION := $(word 1,$(subst -, ,$1)))
	$(eval TARGET := $(patsubst $(ACTION)-%,%,$1))
	$(eval DOMAIN := $(firstword $(subst ., ,$(TARGET))))
	$(eval TAGS   := $(lastword $(subst ., ,$(TARGET))))
	$(eval APP_NAME := $(lastword $(subst ., ,$(TARGET))))
	@# Build force overwrite extra vars (use TAGS which is already the role name)
	$(eval FORCE_ARG := $(if $(filter true,$(FORCE)),-e $(TAGS)_force_overwrite=true,))
	@# Special handling for opencode: also pass opencode_force, opencode_install_force, opencode_config_force
	$(eval FORCE_ARG := $(FORCE_ARG) $(if $(filter true,$(FORCE)),$(if $(findstring opencode,$(TAGS)),-e opencode_force=true -e opencode_install_force=true -e opencode_config_force=true,),))
	@# Single-app verify/rollback for docker_apps needs the container name explicitly
	$(eval APP_ARG := $(if $(findstring services.docker_apps.,$(TARGET)),$(if $(filter verify,$(ACTION)),-e verify_docker_app_name=$(APP_NAME),$(if $(filter rollback,$(ACTION)),-e rollback_docker_app_name=$(APP_NAME),)),))
	@# Determine the best playbook to use: prefer domain-specific over top-level
	$(eval PB_PATH := playbooks/$(if $(filter phase%,$(DOMAIN)),deploy.yml,$(if $(wildcard playbooks/$(DOMAIN)/$(ACTION).yml),$(DOMAIN)/$(ACTION).yml,$(ACTION).yml)))
	@if [ "$(ACTION)" = "check" ]; then \
		echo ">> [Dry-Run] Executing via $(PB_PATH) for tags: $(TAGS) $(if $(filter true,$(FORCE)),[FORCE],)"; \
		ANSIBLE_STRATEGY=linear $(STRATEGY_OPTS) $(ANSIBLE_PLAYBOOK) playbooks/$(if $(filter phase%,$(DOMAIN)),deploy.yml,$(if $(wildcard playbooks/$(DOMAIN)/deploy.yml),$(DOMAIN)/deploy.yml,deploy.yml)) --check --diff --tags "$(TAGS)" $(FORCE_ARG) \
			$(if $(ANSIBLE_LIMIT),--limit "$(ANSIBLE_LIMIT)",); \
	else \
		echo ">> [$(ACTION)] Executing via $(PB_PATH) for tags: $(TAGS) $(if $(filter true,$(FORCE)),[FORCE],)"; \
		$(STRATEGY_OPTS) $(ANSIBLE_PLAYBOOK) $(PB_PATH) --tags "$(TAGS)" $(FORCE_ARG) $(APP_ARG) \
			$(if $(ANSIBLE_LIMIT),--limit "$(ANSIBLE_LIMIT)",); \
	fi
endef

# Dynamic Patterns: Matches deploy-*, verify-*, rollback-*, check-*
# Scopes: phaseX, domain, domain.role
deploy-% verify-% rollback-% check-%:
	@# Auto-detect if python_environment role needs system Python fallback
	$(if $(findstring python_environment,$*),$(eval export ANSIBLE_EXTRA_ARGS := $(ANSIBLE_EXTRA_ARGS) -e ansible_python_interpreter=/usr/bin/python3),)
	$(call run_ansible,$@)
	@# Hook: Run phase0 verification after health checks verification
	@if [ "$@" = "verify-observability.health_checks" ]; then $(MAKE) verify-phase0; fi

# --- 3. Main Lifecycle Targets ---

.PHONY: deploy verify rollback check

deploy: ## 部署所有功能 (Deploy all collection domains)
	@echo ">> Deploying all domains..."
	$(ANSIBLE_PLAYBOOK) playbooks/deploy.yml --tags deploy \
		$(if $(ANSIBLE_LIMIT),--limit "$(ANSIBLE_LIMIT)",)

verify: ## 验证所有功能 (Verify all collection domains)
	@echo ">> Verifying all domains..."
	$(ANSIBLE_PLAYBOOK) playbooks/verify.yml --tags verify \
		$(if $(ANSIBLE_LIMIT),--limit "$(ANSIBLE_LIMIT)",)

rollback: ## 回滚所有功能 (Rollback all collection domains)
	@echo ">> Rolling back all domains..."
	$(ANSIBLE_PLAYBOOK) playbooks/rollback.yml --tags rollback \
		$(if $(ANSIBLE_LIMIT),--limit "$(ANSIBLE_LIMIT)",)

check: check-syntax ## 执行全量 Dry-Run 检查 (Run dry-run check for all)
	@echo ">> Running dry-run for all domains..."
	$(ANSIBLE_PLAYBOOK) playbooks/deploy.yml --check --diff --tags deploy \
		$(if $(ANSIBLE_LIMIT),--limit "$(ANSIBLE_LIMIT)",)
	$(ANSIBLE_PLAYBOOK) playbooks/verify.yml --check --diff --tags verify \
		$(if $(ANSIBLE_LIMIT),--limit "$(ANSIBLE_LIMIT)",)
	$(ANSIBLE_PLAYBOOK) playbooks/rollback.yml --check --diff --tags rollback \
		$(if $(ANSIBLE_LIMIT),--limit "$(ANSIBLE_LIMIT)",)
