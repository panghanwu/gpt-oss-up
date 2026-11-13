#!/usr/bin/env bash
# Create the venvs inside this repo from the locked requirements/*.txt
#   bash install.sh [backend]  .venv-vllm and .venv-litellm
#   bash install.sh full       backend plus .venv-openwebui (chat UI)
# Safe to re-run: existing venvs are synced to the lock files
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

PYTHON_VERSION=3.12  # must match lock.sh
ARCH="$(uname -m)"

case "${1:-backend}" in
  backend) NAMES=(vllm litellm) ;;
  full) NAMES=(vllm litellm openwebui) ;;
  *) echo 'usage: bash install.sh [backend|full]' >&2; exit 1 ;;
esac

command -v uv >/dev/null || { echo 'uv not found; install it first: curl -LsSf https://astral.sh/uv/install.sh | sh' >&2; exit 1; }
[[ -f "$HERE/requirements/vllm.$ARCH.txt" ]] || { echo "no vLLM lock for $ARCH: requirements/vllm.$ARCH.txt" >&2; exit 1; }

# The locked torch is built against CUDA 12.8 on x86_64 (driver >= 570) and CUDA 13.0 on aarch64 (driver >= 580)
MIN_DRIVER=570
[[ "$ARCH" == aarch64 ]] && MIN_DRIVER=580
if driver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)" && [[ -n "$driver" ]]; then
  (( ${driver%%.*} >= MIN_DRIVER )) || echo "warning: NVIDIA driver $driver is older than $MIN_DRIVER; vLLM may fail to start" >&2
else
  echo 'warning: nvidia-smi not available; cannot check the NVIDIA driver version' >&2
fi

for name in "${NAMES[@]}"; do
  venv="$HERE/.venv-$name"
  lock="$HERE/requirements/$name.txt"
  [[ "$name" == vllm ]] && lock="$HERE/requirements/vllm.$ARCH.txt"
  # uv-managed Python ships its C headers, which Triton needs to JIT-compile kernels
  [[ -x "$venv/bin/python" ]] || uv venv --python "$PYTHON_VERSION" --managed-python "$venv"
  uv pip sync --python "$venv/bin/python" "$lock"
done

echo "done: ${NAMES[*]/#/.venv-} ready"
