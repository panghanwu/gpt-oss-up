#!/usr/bin/env bash
# One-command entry: start vLLM (gpt-oss-120b) and the LiteLLM proxy together; Ctrl-C stops both
# LiteLLM is up within seconds; gpt-oss-120b requests fail until vLLM prints its ready banner
# If either service exits on its own, the other is stopped too
# Run a single service with: bash vllm_start.sh / bash litellm_start.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

VLLM_CONTAINER=vllm-gpt-oss-120b  # must match "vllm-$NAME" in vllm_start.sh

# Refuse to start a second copy, so cleanup() never stops a container this run didn't start
if docker container inspect "$VLLM_CONTAINER" >/dev/null 2>&1; then
  echo "$VLLM_CONTAINER already exists; stop it first: docker stop $VLLM_CONTAINER" >&2
  exit 1
fi

VLLM_PID=''
LITELLM_PID=''
cleanup() {
  trap - EXIT INT TERM HUP
  echo 'stopping LiteLLM and vLLM ...' >&2
  [[ -n "$LITELLM_PID" ]] && kill "$LITELLM_PID" 2>/dev/null || true
  # The container may still be starting, so keep stopping it until vllm_start.sh has exited
  while [[ -n "$VLLM_PID" ]] && kill -0 "$VLLM_PID" 2>/dev/null; do
    docker stop "$VLLM_CONTAINER" >/dev/null 2>&1 || true
    sleep 1
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