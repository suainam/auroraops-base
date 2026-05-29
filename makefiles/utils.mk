# ==============================================================================
# Maintenance & Dev Utilities
# ==============================================================================

.PHONY: install-dependencies check-syntax generate-playbooks verify-phase0
.PHONY: validate check-subtags fix-subtags fix-tags check-deps

install-dependencies: ## 安装 Galaxy 依赖 (Install dependencies)
	@echo "   Collections..."
	@$(ANSIBLE_GALAXY) collection install -r requirements.yml --collections-path ./collections 2>&1 | grep -E "(was installed|already installed)" | sort -u | sed 's/^/      /' || true
	@echo "      Mitogen: OK"

check-syntax: ## 运行代码语法与 Lint 检查 (Run lint & syntax checks)
	@echo ">> Running syntax checks..."
	$(ANSIBLE_LINT) . --offline
	$(ANSIBLE_PLAYBOOK) playbooks/deploy.yml --syntax-check
	$(ANSIBLE_PLAYBOOK) playbooks/verify.yml --syntax-check
	$(ANSIBLE_PLAYBOOK) playbooks/rollback.yml --syntax-check
	@$(MAKE) -n -f Makefile > /dev/null

generate-playbooks: ## 自动生成并优化 Playbooks (Regenerate & Optimize)
	@echo ">> Generating top-level playbooks..."
	@$(PYTHON) scripts/generate_ansible_playbooks.py
	@echo ">> Mass optimizing task structure (include_tasks -> import_tasks)..."
	@$(PYTHON) scripts/mass_optimize_tasks.py
	@echo "✅ Playbooks regenerated and static optimizations applied."

verify-phase0: ## 运行 Phase 0 基线验证 (Verify specific phase infrastructure)
	@echo ">> Running Phase 0 verification..."
	@$(PYTHON) scripts/verify_phase0.py

validate: ## 全量验证（标签+子标签格式+文档）
	@echo ">> Running full validation..."
	@echo "   1. Checking base tags..."
	@$(PYTHON) scripts/check_ansible_tags.py || true
	@echo "   2. Checking subtag format..."
	@$(PYTHON) scripts/check_subtags.py || true
	@echo "   3. Checking documentation..."
	@$(PYTHON) scripts/check_doc_compliance.py || true
	@echo "✅ Validation complete (review any issues above)"

check-subtags: ## 检查子标签格式规范
	@echo ">> Checking subtag format compliance..."
	@$(PYTHON) scripts/check_subtags.py

fix-subtags: ## 修复子标签格式（预览后确认）
	@echo ">> Analyzing subtag issues..."
	@$(PYTHON) scripts/fix_subtags.py --dry-run
	@echo ""
	@read -p "Apply fixes? [y/N] " confirm && if [ "$$confirm" = "y" ]; then \
		echo ">> Applying fixes..."; \
		$(PYTHON) scripts/fix_subtags.py; \
		echo ">> Regenerating playbooks..."; \
		$(MAKE) generate-playbooks; \
	else \
		echo "Aborted."; \
	fi

fix-subtags-auto: ## 自动修复子标签（无确认，用于CI）
	@echo ">> Auto-fixing subtags..."
	@$(PYTHON) scripts/fix_subtags.py
	$(MAKE) generate-playbooks

fix-tags: ## 修复所有标签问题（基础标签+子标签）
	@echo ">> Fixing all tag issues..."
	@echo "   1. Fixing base tags..."
	@$(PYTHON) scripts/fix_ansible_tags.py
	@echo "   2. Fixing subtags (dry-run)..."
	@$(PYTHON) scripts/fix_subtags.py --dry-run
	@echo ""
	@read -p "Apply subtag fixes? [y/N] " confirm && if [ "$$confirm" = "y" ]; then \
		$(PYTHON) scripts/fix_subtags.py; \
		$(MAKE) generate-playbooks; \
	else \
		echo "Subtag fixes skipped."; \
	fi

check-deps: ## 检查角色依赖关系
	@echo ">> Checking role dependencies..."
	@$(PYTHON) scripts/check_role_dependencies.py --check-phases
