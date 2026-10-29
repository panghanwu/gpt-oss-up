#!/usr/bin/env bash
# Serve gpt-oss-120b with vLLM on 127.0.0.1:$VLLM_PORT and send a greeting once ready
# Stop: Ctrl-C or close the terminal; from elsewhere: docker stop vllm-gpt-oss-120b
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

set -a  # export every variable defined in .env
source "$HERE/.env"
set +a

NAME=gpt-oss-120b  # served model name; must match model in config.yaml
IMAGE=vllm/vllm-openai:v0.28.0
PORT="${VLLM_PORT:?VLLM_PORT not set in .env}"
: "${GPUS:?GPUS not set in .env}" "${GPU_MEMORY_UTILIZATION:?GPU_MEMORY_UTILIZATION not set in .env}"
GREETING='請你用 100 字左右介紹你自己，並附上表情符號表達你現在的心情。'

greet() {
  PYTHONIOENCODING=utf-8 python3 - "$PORT" "$NAME" "$GREETING" <<'EOF'
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

# Fixed container name prevents a second copy from starting
# --gpus needs the inner quotes, otherwise docker splits "device=2,3" at the comma
docker run --rm --name "vllm-$NAME" --gpus "\"device=$GPUS\"" --ipc=host \
  -p "127.0.0.1:$PORT:8000" \
  -v "${HF_HOME:?HF_HOME not set in .env}:/root/.cache/huggingface" \
  -e HF_HUB_OFFLINE=1 \
  -e TIKTOKEN_ENCODINGS_BASE=/root/.cache/huggingface/tiktoken_encodings \
  "$IMAGE" openai/gpt-oss-120b \
  --served-model-name "$NAME" \
  --tensor-parallel-size "${#GPU_LIST[@]}" \
  --reasoning-parser openai_gptoss \
  --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" &
DOCKER_PID=$!

# Background jobs ignore Ctrl-C in scripts, so stop the container explicitly
trap 'docker stop "vllm-$NAME" >/dev/null 2>&1 || true; exit 130' INT TERM HUP

until curl -sf "127.0.0.1:$PORT/health" >/dev/null; do
  kill -0 "$DOCKER_PID" 2>/dev/null || exit 1  # container exited during startup
  sleep 5
done

greet || echo 'greeting failed'  # never take the server down over the greeting
wait "$DOCKER_PID"