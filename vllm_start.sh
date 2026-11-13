#!/usr/bin/env bash
# Serve gpt-oss (MODEL in .env) with vLLM on 127.0.0.1:$VLLM_PORT and send a greeting once ready
# Stop: Ctrl-C or close the terminal; from elsewhere: kill this script's PID
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/env.sh"  # loads .env; sets MODEL_NAME and GPU_MEMORY_UTILIZATION

NAME="$MODEL_NAME"  # served model name; config.yaml reads the same MODEL_NAME
VENV="$HERE/.venv-vllm"
PORT="${VLLM_PORT:?VLLM_PORT not set in .env}"
: "${HF_HOME:?HF_HOME not set in .env}" "${GPUS:?GPUS not set in .env}"
GREETING='請你用 100 字左右介紹你自己，並附上表情符號表達你現在的心情。'

[[ -x "$VENV/bin/vllm" ]] || { echo "vLLM venv not found: run bash install.sh first" >&2; exit 1; }
if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
  echo "port $PORT is already in use (another vLLM?); change VLLM_PORT in .env" >&2
  exit 1
fi

greet() {
  PYTHONIOENCODING=utf-8 "$VENV/bin/python" - "$PORT" "$NAME" "$GREETING" <<'EOF'
import json
import sys
import urllib.request

port, name, prompt = sys.argv[1:]
body = {'model': name, 'reasoning_effort': 'low', 'messages': [{'role': 'user', 'content': prompt}]}
req = urllib.request.Request(f'http://127.0.0.1:{port}/v1/chat/completions', json.dumps(body).encode(), {'Content-Type': 'application/json'})
reply = json.load(urllib.request.urlopen(req, timeout=300))['choices'][0]['message']['content']
print(f'\n===== {name} is ready =====\n{reply}\n{"=" * 30}\n', flush=True)
EOF
}

IFS=, read -ra GPU_LIST <<< "$GPUS"  # one tensor-parallel rank per GPU

# HF_HUB_OFFLINE: load weights from HF_HOME only; TIKTOKEN_ENCODINGS_BASE: harmony vocab without network
# VLLM_NO_USAGE_STATS: do not send usage stats to stats.vllm.ai
# PATH: FlashInfer JIT-compiles kernels it has no prebuilt binary for (e.g. on GB10) with the venv's ninja
# setsid: vLLM and its engine process get their own process group, so stop() below can signal both
PATH="$VENV/bin:$PATH" \
CUDA_VISIBLE_DEVICES="$GPUS" \
HF_HUB_OFFLINE=1 \
VLLM_NO_USAGE_STATS=1 \
TIKTOKEN_ENCODINGS_BASE="$HF_HOME/tiktoken_encodings" \
  setsid "$VENV/bin/vllm" serve "openai/$NAME" \
  --host 127.0.0.1 --port "$PORT" \
  --served-model-name "$NAME" \
  --tensor-parallel-size "${#GPU_LIST[@]}" \
  --reasoning-parser openai_gptoss \
  --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" &
VLLM_PID=$!  # also the process group ID, thanks to setsid

# Stop the server on Ctrl-C / TERM (start.sh sends TERM); the waits below use builtin wait so this fires at once
# While still loading, vLLM does not react to TERM, so the whole group is killed after 15 s
stop() {
  trap '' INT TERM HUP  # repeated Ctrl-C must not interrupt the shutdown
  kill -- -"$VLLM_PID" 2>/dev/null || true
  for _ in {1..15}; do
    kill -0 -- -"$VLLM_PID" 2>/dev/null || break
    sleep 1
  done
  kill -KILL -- -"$VLLM_PID" 2>/dev/null || true
  wait "$VLLM_PID" 2>/dev/null || true
  exit 130
}
trap stop INT TERM HUP

until curl -sf "127.0.0.1:$PORT/health" >/dev/null; do
  kill -0 "$VLLM_PID" 2>/dev/null || exit 1  # server exited during startup
  sleep 5 & wait $!
done

greet & wait $! || echo 'greeting failed'  # never take the server down over the greeting
wait "$VLLM_PID"
