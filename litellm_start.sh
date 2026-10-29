#!/usr/bin/env bash
# Serve the LiteLLM proxy on 127.0.0.1:$LITELLM_PORT; routes gpt-oss-120b to vLLM on $VLLM_PORT (see config.yaml)
# Stop: Ctrl-C
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

set -a  # export every variable defined in .env
source "$HERE/.env"
set +a
: "${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY not set in .env}"
: "${LITELLM_PORT:?LITELLM_PORT not set in .env}"
export VLLM_API_BASE="http://127.0.0.1:${VLLM_PORT:?VLLM_PORT not set in .env}/v1"  # read by config.yaml

LITELLM="$HERE/.venv-litellm/bin/litellm"
[[ -x "$LITELLM" ]] || { echo "LiteLLM venv not found: run bash install.sh first" >&2; exit 1; }
if (exec 3<>"/dev/tcp/127.0.0.1/$LITELLM_PORT") 2>/dev/null; then
  echo "port $LITELLM_PORT is already in use; change LITELLM_PORT in .env" >&2
  exit 1
fi

exec "$LITELLM" --config "$HERE/config.yaml" --port "$LITELLM_PORT" --host 127.0.0.1
