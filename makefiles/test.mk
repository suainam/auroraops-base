# Test harness automation for AuroraOps
# Include this in the main Makefile

# Common Ansible extra arguments for test/acceptance environment
TEST_ARGS := --private-key $(HOME)/projects/AuroraOps/secrets/ssh/auroraops_test_debian13 -e "ansible_become_password={{ vault_ansible_become_password }}"

# Verification helper
# Usage: make verify-role ROLE=system.sysctl
verify-role:
	@env ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
	make verify-$(ROLE) ANSIBLE_EXTRA_ARGS='$(TEST_ARGS)' | grep -C 2 -iE "failed|error" || echo "Verify passed: $(ROLE)"

# Deployment helper
deploy-role:
	@env ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
	make deploy-$(ROLE) ANSIBLE_EXTRA_ARGS='$(TEST_ARGS)' | grep -C 2 -iE "failed|error" || echo "Deploy passed: $(ROLE)"
