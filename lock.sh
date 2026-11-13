#!/usr/bin/env bash
# Re-resolve requirements/*.in into fully pinned requirements/*.txt (Python 3.12)
# vLLM is locked per CPU architecture (vllm.<arch>.txt, <arch> as printed by uname -m);
# LiteLLM and Open WebUI get one cross-platform lock each
# Run after changing a version in requirements/*.in, then re-run install.sh
set -euo pipefail
cd "$(dirname "$0")/requirements"

PYTHON_VERSION=3.12  # must match install.sh

compile() {  # <name>.in -> <name>.txt, extra args go to uv
  local name="$1"; shift
  # --emit-index-url keeps extra indexes from *.in (e.g. FlashInfer's) in the lock for uv pip sync
  uv pip compile "$name.in" -q -o "$name.txt" --emit-index-url \
    --python-version "$PYTHON_VERSION" --custom-compile-command 'bash lock.sh' "$@"
}

for arch in x86_64 aarch64; do
  compile "vllm.$arch" --python-platform "$arch-manylinux_2_28"
done
for name in litellm openwebui; do
  compile "$name" --universal
done
