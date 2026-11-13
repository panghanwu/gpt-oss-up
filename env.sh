# Sourced by the *_start.sh scripts (not run directly): load .env and derive the model settings
# The caller sets HERE to the repo root before sourcing this file

[[ -f "$HERE/.env" ]] || { echo ".env not found: run cp .env.example .env and fill it in" >&2; exit 1; }
set -a  # export every variable defined in .env (HF_HOME is read by vLLM itself)
source "$HERE/.env"
set +a

# MODEL picks the gpt-oss checkpoint; GPU_MEMORY_UTILIZATION set in .env overrides the default
# Defaults measured on DGX Spark (121.6 GiB shared with the OS): both leave ~25 GiB for the KV cache
case "${MODEL:=120b}" in
  120b) MODEL_NAME=gpt-oss-120b; default_gpu_memory_utilization=0.75 ;;
  20b) MODEL_NAME=gpt-oss-20b; default_gpu_memory_utilization=0.35 ;;
  *) echo "MODEL in .env must be 120b or 20b, got: $MODEL" >&2; exit 1 ;;
esac
export MODEL_NAME  # served name in vLLM, LiteLLM (config.yaml) and Open WebUI
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-$default_gpu_memory_utilization}"
