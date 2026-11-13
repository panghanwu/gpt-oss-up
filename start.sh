#!/usr/bin/env bash
# One-command entry: start vLLM (gpt-oss) and the LiteLLM proxy together, plus Open WebUI after bash install.sh full
# Ctrl-C stops all of them; if any service exits on its own, the others are stopped too
# LiteLLM is up within seconds; model requests fail until vLLM prints its ready banner, and Open WebUI starts after that
# Run a single service with: bash vllm_start.sh / bash litellm_start.sh / bash openwebui_start.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

PIDS=()
cleanup() {
  trap - EXIT
  trap '' INT TERM HUP  # a second Ctrl-C must not leave services running without start.sh
  echo 'stopping all services (vLLM may take up to 15 s) ...' >&2
  # TERM only; each *_start.sh stops its own server and waits for it
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP  # exit triggers the EXIT trap

# Background jobs in scripts ignore Ctrl-C, so cleanup() stops them explicitly
bash "$HERE/vllm_start.sh" &
PIDS+=($!)
bash "$HERE/litellm_start.sh" &
PIDS+=($!)
if [[ -x "$HERE/.venv-openwebui/bin/open-webui" ]]; then  # created by bash install.sh full
  bash "$HERE/openwebui_start.sh" &
  PIDS+=($!)
fi

rc=0
wait -n "${PIDS[@]}" || rc=$?  # returns as soon as any service exits
exit "$rc"
