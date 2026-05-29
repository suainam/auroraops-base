#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${AURORAOPS_BASE_SMOKE_IMAGE:-auroraops-base-smoke}"
TEMP_ROOT="$(mktemp -d)"
WORKTREE="${TEMP_ROOT}/repo"
DOCKER_ENV_PREFIX=(
  env
  -u ALL_PROXY
  -u HTTPS_PROXY
  -u HTTP_PROXY
  -u NO_PROXY
  -u all_proxy
  -u https_proxy
  -u http_proxy
  -u no_proxy
)

cleanup() {
  rm -rf "${TEMP_ROOT}"
}
trap cleanup EXIT

cp -a "${REPO_ROOT}/." "${WORKTREE}"

if [[ -f "${WORKTREE}/inventories/prod.ini.example" ]]; then
  cp "${WORKTREE}/inventories/prod.ini.example" "${WORKTREE}/inventories/prod.ini"
fi

if [[ -f "${WORKTREE}/inventories/host_vars/example-host.yml" ]]; then
  mkdir -p "${WORKTREE}/inventories/host_vars"
  cp "${WORKTREE}/inventories/host_vars/example-host.yml" "${WORKTREE}/inventories/host_vars/smoke.yml"
fi

if [[ -f "${WORKTREE}/inventories/group_vars/all/base.example.yml" ]]; then
  cp "${WORKTREE}/inventories/group_vars/all/base.example.yml" "${WORKTREE}/inventories/group_vars/all/base.yml"
fi

if [[ -f "${WORKTREE}/secrets/vault.yml.example" ]]; then
  cp "${WORKTREE}/secrets/vault.yml.example" "${WORKTREE}/secrets/vault.yml"
fi

printf 'smoke-test\n' > "${WORKTREE}/.vault_pass.txt"

cat > "${WORKTREE}/.ansible_env" <<'EOF'
PYTHON_BIN=/usr/local/bin/python3
ANSIBLE_VENV_BIN=/usr/local/bin
LINT_VENV_BIN=/usr/local/bin
EOF

echo ">> [Base-Smoke] Building Docker image: ${IMAGE_NAME}"
"${DOCKER_ENV_PREFIX[@]}" docker build \
  --build-arg ALL_PROXY= \
  --build-arg HTTPS_PROXY= \
  --build-arg HTTP_PROXY= \
  --build-arg NO_PROXY= \
  --build-arg all_proxy= \
  --build-arg https_proxy= \
  --build-arg http_proxy= \
  --build-arg no_proxy= \
  -t "${IMAGE_NAME}" \
  -f "${REPO_ROOT}/scripts/Dockerfile.public_base_smoke" \
  "${REPO_ROOT}"

echo ">> [Base-Smoke] Running smoke checks inside container"
"${DOCKER_ENV_PREFIX[@]}" docker run --rm \
  -e AURORAOPS_SKIP_VAULT=1 \
  -e HOME=/tmp/auroraops-smoke \
  -e ANSIBLE_LOCAL_TEMP=/tmp/ansible-local \
  -e ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
  --user "$(id -u):$(id -g)" \
  -v "${WORKTREE}:/workspace" \
  -w /workspace \
  "${IMAGE_NAME}" \
  bash -lc '
    set -euo pipefail
    make install-dependencies
    make generate-playbooks
    make check-syntax
    make -n deploy-base >/dev/null
    make -n verify-base >/dev/null
  '

echo ">> [Base-Smoke] Docker smoke test passed"
