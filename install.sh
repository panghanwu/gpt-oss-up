#!/usr/bin/env bash
# Create .venv-vllm and .venv-litellm inside this repo from the locked requirements/*.txt
# Safe to re-run: existing venvs are synced to the lock files
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

PYTHON_VERSION=3.12  # must match lock.sh

command -v uv >/dev/null || { echo 'uv not found; install it first, e.g. pip install uv' >&2; exit 1; }

# The locked torch is built against CUDA 13, which needs NVIDIA driver >= 580
if driver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)" && [[ -n "$driver" ]]; then
  (( ${driver%%.*} >= 580 )) || echo "warning: NVIDIA driver $driver is older than 580 (CUDA 13); vLLM may fail to start" >&2
else
  echo 'warning: nvidia-smi not available; cannot check the NVIDIA driver version' >&2
fi

for name in vllm litellm; do
  venv="$HERE/.venv-$name"
  [[ -x "$venv/bin/python" ]] || uv venv --python "$PYTHON_VERSION" "$venv"
  uv pip sync --python "$venv/bin/python" "$HERE/requirements/$name.txt"
done

echo 'done: .venv-vllm and .venv-litellm are ready'
