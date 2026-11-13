#!/usr/bin/env bash
# Serve Open WebUI on 127.0.0.1:$OPENWEBUI_PORT: chat-only, single local user, talks to LiteLLM only
# Starts once vLLM is ready, so the model answers as soon as the page opens; installed by: bash install.sh full
# Stop: Ctrl-C or close the terminal; from elsewhere: kill this script's PID
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/env.sh"  # loads .env; sets MODEL_NAME

VENV="$HERE/.venv-openwebui"
PORT="${OPENWEBUI_PORT:?OPENWEBUI_PORT not set in .env}"
: "${VLLM_PORT:?VLLM_PORT not set in .env}" "${LITELLM_PORT:?LITELLM_PORT not set in .env}" "${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY not set in .env}"

[[ -x "$VENV/bin/open-webui" ]] || { echo "Open WebUI venv not found: run bash install.sh full first" >&2; exit 1; }
if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
  echo "port $PORT is already in use; change OPENWEBUI_PORT in .env" >&2
  exit 1
fi

# Open WebUI settings; with ENABLE_PERSISTENT_CONFIG=False they apply on every start
# (changes made in the admin panel last only until the next restart)
export DATA_DIR="$HERE/.openwebui-data"  # chats and Open WebUI's database; delete it to start over
export ENABLE_PERSISTENT_CONFIG=False
export WEBUI_AUTH=False  # no sign-in; the only user is an admin
export OFFLINE_MODE=True  # no model downloads or update checks at runtime (also sets HF_HUB_OFFLINE)

# Connect to LiteLLM only
export OPENAI_API_BASE_URLS="http://127.0.0.1:$LITELLM_PORT/v1"
export OPENAI_API_KEYS="$LITELLM_MASTER_KEY"
export ENABLE_OLLAMA_API=False
export DEFAULT_MODELS="$MODEL_NAME"

# Chat only: turn everything else off
export ENABLE_WEB_SEARCH=False
export ENABLE_IMAGE_GENERATION=False ENABLE_IMAGE_EDIT=False
export ENABLE_CODE_INTERPRETER=False ENABLE_CODE_EXECUTION=False
export ENABLE_PLUGINS=False  # tools, functions and tool servers
export ENABLE_MEMORIES=False ENABLE_NOTES=False ENABLE_CHANNELS=False
export ENABLE_AUTOMATIONS=False ENABLE_CALENDAR=False
export ENABLE_COMMUNITY_SHARING=False ENABLE_MESSAGE_RATING=False ENABLE_EVALUATION_ARENA_MODELS=False
export ENABLE_NOTIFICATIONS=False ENABLE_USER_STATUS=False  # inbox and presence are for multiple users
# Extra model calls Open WebUI makes in the background: keep chat titles only
export ENABLE_TITLE_GENERATION=True
export ENABLE_FOLLOW_UP_GENERATION=False ENABLE_TAGS_GENERATION=False ENABLE_AUTOCOMPLETE_GENERATION=False
export ENABLE_SEARCH_QUERY_GENERATION=False ENABLE_RETRIEVAL_QUERY_GENERATION=False ENABLE_IMAGE_PROMPT_GENERATION=False

# File upload in chat (OPENWEBUI_FILE_UPLOAD in .env); true needs the embedding model in HF_HOME (see README)
if [[ "${OPENWEBUI_FILE_UPLOAD:-false}" == true ]]; then
  upload=true
  export RAG_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
else
  upload=false
  export RAG_EMBEDDING_MODEL=''  # do not load any embedding model
fi
export USER_PERMISSIONS_CHAT_FILE_UPLOAD="$upload"
# Model capabilities decide which buttons the chat input shows, even for the admin;
# file_context puts uploaded file text into the prompt (the alternative, builtin tools, is turned off)
export DEFAULT_MODEL_METADATA="{\"capabilities\": {\"file_upload\": $upload, \"file_context\": $upload, \"vision\": false,
  \"web_search\": false, \"image_generation\": false, \"code_interpreter\": false, \"terminal\": false, \"memory\": false,
  \"builtin_tools\": false}}"

echo "Open WebUI waits for vLLM on port $VLLM_PORT ..." >&2
until curl -sf "127.0.0.1:$VLLM_PORT/health" >/dev/null; do
  sleep 5 & wait $!
done

mkdir -p "$DATA_DIR"
cd "$DATA_DIR"  # open-webui keeps its generated .webui_secret_key in the working directory
"$VENV/bin/open-webui" serve --host 127.0.0.1 --port "$PORT" &
WEBUI_PID=$!

# Stop the server on Ctrl-C / TERM (start.sh sends TERM); the waits below use builtin wait so this fires at once
trap 'kill "$WEBUI_PID" 2>/dev/null || true; wait "$WEBUI_PID" 2>/dev/null || true; exit 130' INT TERM HUP

until curl -sf "127.0.0.1:$PORT/health" >/dev/null; do
  kill -0 "$WEBUI_PID" 2>/dev/null || exit 1  # server exited during startup
  sleep 2 & wait $!
done
echo -e "\n===== Open WebUI is ready: http://127.0.0.1:$PORT =====\n"
wait "$WEBUI_PID"
