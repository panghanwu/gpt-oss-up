#!/usr/bin/env bash
# Re-resolve requirements/*.in into fully pinned requirements/*.txt (Linux x86_64, Python 3.12)
# Run after changing a version in requirements/*.in, then re-run install.sh
set -euo pipefail
cd "$(dirname "$0")/requirements"

PYTHON_VERSION=3.12  # must match install.sh

for name in vllm litellm; do
  uv pip compile "$name.in" -q -o "$name.txt" \
    --python-version "$PYTHON_VERSION" --python-platform x86_64-manylinux_2_28 \
    --custom-compile-command 'bash lock.sh'
done
