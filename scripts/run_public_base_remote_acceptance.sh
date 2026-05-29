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

HOST_ALIAS="lan-debian13"
SOURCE_HOST_VARS=""
ANSIBLE_HOST=""
ANSIBLE_USER=""
ANSIBLE_PORT=""
SSH_PORT=""
PRIVATE_KEY_FILE=""
SUDO_PASSWORD=""
BOOTSTRAP_SSH_PASSWORD=""
BASE_ADMIN_USER=""
PROXY_ENABLED=""
PROXY_HTTP=""
PROXY_HTTPS=""
ANSIBLE_PYTHON_INTERPRETER=""

usage() {
  cat <<'EOF'
Usage:
  bash scripts/run_public_base_remote_acceptance.sh [options]

Options:
  --host-alias <name>
  --source-host-vars <path>
  --ansible-host <host>
  --ansible-user <user>
  --ansible-port <port>
  --ssh-port <port>
  --private-key-file <path>
  --sudo-password <password>
  --bootstrap-ssh-password <password>
  --base-admin-user <user>
  --proxy-enabled <true|false>
  --proxy-http <url>
  --proxy-https <url>
  --ansible-python-interpreter <path>

Either --source-host-vars or all required explicit connection args must be provided.
EOF
}

cleanup() {
  rm -rf "${TEMP_ROOT}"
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host-alias) HOST_ALIAS="$2"; shift 2 ;;
    --source-host-vars) SOURCE_HOST_VARS="$2"; shift 2 ;;
    --ansible-host) ANSIBLE_HOST="$2"; shift 2 ;;
    --ansible-user) ANSIBLE_USER="$2"; shift 2 ;;
    --ansible-port) ANSIBLE_PORT="$2"; shift 2 ;;
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    --private-key-file) PRIVATE_KEY_FILE="$2"; shift 2 ;;
    --sudo-password) SUDO_PASSWORD="$2"; shift 2 ;;
    --bootstrap-ssh-password) BOOTSTRAP_SSH_PASSWORD="$2"; shift 2 ;;
    --base-admin-user) BASE_ADMIN_USER="$2"; shift 2 ;;
    --proxy-enabled) PROXY_ENABLED="$2"; shift 2 ;;
    --proxy-http) PROXY_HTTP="$2"; shift 2 ;;
    --proxy-https) PROXY_HTTPS="$2"; shift 2 ;;
    --ansible-python-interpreter) ANSIBLE_PYTHON_INTERPRETER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "${SOURCE_HOST_VARS}" ]]; then
  for required in ANSIBLE_HOST ANSIBLE_USER PRIVATE_KEY_FILE SUDO_PASSWORD; do
    if [[ -z "${!required}" ]]; then
      echo "Missing required arg: ${required}" >&2
      usage >&2
      exit 2
    fi
  done
fi

cp -a "${REPO_ROOT}/." "${WORKTREE}"

if [[ -f "${WORKTREE}/inventories/prod.ini.example" ]]; then
  cp "${WORKTREE}/inventories/prod.ini.example" "${WORKTREE}/inventories/prod.ini"
fi

if [[ -f "${WORKTREE}/inventories/group_vars/all/base.example.yml" ]]; then
  cp "${WORKTREE}/inventories/group_vars/all/base.example.yml" "${WORKTREE}/inventories/group_vars/all/base.yml"
fi

if [[ -f "${WORKTREE}/secrets/vault.yml.example" ]]; then
  cp "${WORKTREE}/secrets/vault.yml.example" "${WORKTREE}/secrets/vault.yml"
fi

printf 'acceptance-test\n' > "${WORKTREE}/.vault_pass.txt"

RENDER_ARGS=(
  /usr/bin/python3
  "${REPO_ROOT}/tests/public_base_acceptance/render_fixture.py"
  --output "${WORKTREE}"
  --host-alias "${HOST_ALIAS}"
)

if [[ -n "${SOURCE_HOST_VARS}" ]]; then
  RENDER_ARGS+=(--source-host-vars "${SOURCE_HOST_VARS}")
fi
if [[ -n "${ANSIBLE_HOST}" ]]; then RENDER_ARGS+=(--ansible-host "${ANSIBLE_HOST}"); fi
if [[ -n "${ANSIBLE_USER}" ]]; then RENDER_ARGS+=(--ansible-user "${ANSIBLE_USER}"); fi
if [[ -n "${ANSIBLE_PORT}" ]]; then RENDER_ARGS+=(--ansible-port "${ANSIBLE_PORT}"); fi
if [[ -n "${SSH_PORT}" ]]; then RENDER_ARGS+=(--ssh-port "${SSH_PORT}"); fi
if [[ -n "${PRIVATE_KEY_FILE}" ]]; then RENDER_ARGS+=(--private-key-file "${PRIVATE_KEY_FILE}"); fi
if [[ -n "${SUDO_PASSWORD}" ]]; then RENDER_ARGS+=(--sudo-password "${SUDO_PASSWORD}"); fi
if [[ -n "${BOOTSTRAP_SSH_PASSWORD}" ]]; then RENDER_ARGS+=(--bootstrap-ssh-password "${BOOTSTRAP_SSH_PASSWORD}"); fi
if [[ -n "${BASE_ADMIN_USER}" ]]; then RENDER_ARGS+=(--base-admin-user "${BASE_ADMIN_USER}"); fi
if [[ -n "${PROXY_ENABLED}" ]]; then RENDER_ARGS+=(--proxy-enabled "${PROXY_ENABLED}"); fi
if [[ -n "${PROXY_HTTP}" ]]; then RENDER_ARGS+=(--proxy-http "${PROXY_HTTP}"); fi
if [[ -n "${PROXY_HTTPS}" ]]; then RENDER_ARGS+=(--proxy-https "${PROXY_HTTPS}"); fi
if [[ -n "${ANSIBLE_PYTHON_INTERPRETER}" ]]; then RENDER_ARGS+=(--ansible-python-interpreter "${ANSIBLE_PYTHON_INTERPRETER}"); fi

echo ">> [Base-Acceptance] Rendering private fixture into worktree"
"${RENDER_ARGS[@]}"

HOST_VARS_FILE="${WORKTREE}/inventories/host_vars/${HOST_ALIAS}.yml"
if [[ ! -f "${HOST_VARS_FILE}" ]]; then
  echo "Rendered host vars missing: ${HOST_VARS_FILE}" >&2
  exit 1
fi

KEY_PATH="$(sed -n 's/^ansible_ssh_private_key_file: "\(.*\)"/\1/p' "${HOST_VARS_FILE}" | head -n 1)"
if [[ -z "${KEY_PATH}" ]]; then
  echo "Unable to determine private key path from ${HOST_VARS_FILE}" >&2
  exit 1
fi
if [[ ! -f "${KEY_PATH}" ]]; then
  echo "Private key not found on host: ${KEY_PATH}" >&2
  exit 1
fi

KEY_DIR="$(dirname "${KEY_PATH}")"

cat > "${WORKTREE}/.ansible_env" <<'EOF'
PYTHON_BIN=/usr/local/bin/python3
ANSIBLE_VENV_BIN=/usr/local/bin
LINT_VENV_BIN=/usr/local/bin
EOF

echo ">> [Base-Acceptance] Building Docker image: ${IMAGE_NAME}"
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

echo ">> [Base-Acceptance] Running remote acceptance against ${HOST_ALIAS}"
"${DOCKER_ENV_PREFIX[@]}" docker run --rm \
  -e AURORAOPS_SKIP_VAULT=1 \
  -e HOME=/tmp/auroraops-acceptance \
  -e ALL_PROXY= \
  -e HTTPS_PROXY= \
  -e HTTP_PROXY= \
  -e NO_PROXY= \
  -e all_proxy= \
  -e https_proxy= \
  -e http_proxy= \
  -e no_proxy= \
  -e ANSIBLE_LOCAL_TEMP=/tmp/ansible-local \
  -e ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
  -e ANSIBLE_STRATEGY=linear \
  -v "${WORKTREE}:/workspace" \
  -v "${KEY_DIR}:${KEY_DIR}:ro" \
  -w /workspace \
  "${IMAGE_NAME}" \
  bash -lc "
    set -euo pipefail
    mkdir -p \"\$HOME/.ssh\"
    python3 tests/public_base_acceptance/ensure_key_login.py --host-vars inventories/host_vars/${HOST_ALIAS}.yml
    make bootstrap
    make bootstrap-status
    make validate
    make generate-playbooks
    make switch_remote.${HOST_ALIAS}
    make env_show
    make check-base
    make deploy-base
    make verify-base
    # make rollback-base
  "

echo ">> [Base-Acceptance] Remote acceptance passed"
