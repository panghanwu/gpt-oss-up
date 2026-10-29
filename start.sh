#!/usr/bin/env bash
# One-command entry: start vLLM (gpt-oss-120b) and the LiteLLM proxy together; Ctrl-C stops both
# LiteLLM is up within seconds; gpt-oss-120b requests fail until vLLM prints its ready banner
# If either service exits on its own, the other is stopped too
# Run a single service with: bash vllm_start.sh / bash litellm_start.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

VLLM_PID=''
LITELLM_PID=''
cleanup() {
  trap - EXIT INT TERM HUP
  echo 'stopping LiteLLM and vLLM ...' >&2
  # TERM only; vllm_start.sh stops its own server and waits for it
  for pid in "$LITELLM_PID" "$VLLM_PID"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP  # exit triggers the EXIT trap

# Background jobs in scripts ignore Ctrl-C, so cleanup() stops them explicitly
bash "$HERE/vllm_start.sh" &
VLLM_PID=$!
bash "$HERE/litellm_start.sh" &
LITELLM_PID=$!

rc=0
wait -n "$VLLM_PID" "$LITELLM_PID" || rc=$?  # returns as soon as either service exits
exit "$rc"
