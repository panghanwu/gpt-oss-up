# Summon Local GPT-OSS-120B

在本機用 vLLM 跑 gpt-oss-120b，前面接 LiteLLM proxy。兩個服務都只綁 `127.0.0.1`，只有本機連得到。

```
client ──> LiteLLM :LITELLM_PORT ──> vLLM :VLLM_PORT (Docker, gpt-oss-120b)
```

## 檔案

| 檔案 | 用途 |
|---|---|
| `start.sh` | 一鍵啟動 vLLM + LiteLLM，Ctrl-C 一起停 |
| `vllm_start.sh` | 單獨啟動 vLLM（Docker），就緒後印出 greeting |
| `litellm_start.sh` | 單獨啟動 LiteLLM |
| `config.yaml` | LiteLLM 設定，只有 `gpt-oss-120b` |
| `.env.example` | 設定範本，複製成 `.env` 後填寫 |

## 最低需求

| 項目 | 需求 |
|---|---|
| GPU | NVIDIA GPU，顯存要放得下 60.8 GiB 權重加 KV cache：單張 80 GB（`GPU_MEMORY_UTILIZATION=0.9`），或兩張以上 |
| 磁碟 | `HF_HOME` 約 61 GiB（權重） |
| 系統 | Linux，Bash ≥ 5.1（`start.sh` 用到 `wait -n <pid>`） |
| Docker | Docker + NVIDIA Container Toolkit；NVIDIA driver 需支援 `vllm/vllm-openai:v0.28.0` 的 CUDA 版本 |
| Python | `litellm[proxy]`，`litellm` 指令要在 PATH 裡（先啟用對應 venv）；host 的 `python3` 用於 greeting，只用標準函式庫 |
| 其他 | `curl`；產生 key 需要 `openssl` |

`HF_HOME` 底下要有：
  - `hub/models--openai--gpt-oss-120b`（權重）
  - `tiktoken_encodings/`（`*.tiktoken`，離線時 harmony 需要）

## 設定

```bash
cp .env.example .env
```

| 變數 | 說明 |
|---|---|
| `HF_HOME` | HF cache 根目錄（權重與 tiktoken） |
| `VLLM_PORT` | vLLM 的 port（預設 28000） |
| `LITELLM_PORT` | LiteLLM 的 port，client 連這個（預設 24000） |
| `GPUS` | GPU 編號，例如 `0` 或 `2,3`；tensor parallel 大小 = 卡數 |
| `GPU_MEMORY_UTILIZATION` | vLLM 每張卡可用的顯存比例 |
| `LITELLM_MASTER_KEY` | 呼叫 LiteLLM 用的 key |

`LITELLM_MASTER_KEY` 可以用指令產生：

```bash
echo "sk-$(openssl rand -hex 32)"
```

## 啟動

```bash
bash start.sh
```

- LiteLLM 幾秒內就緒；vLLM 要載入權重，印出 `===== gpt-oss-120b is ready =====` 之後才能用
- 任一服務掛掉，另一個也會被停掉
- `vllm-gpt-oss-120b` container 已存在時，`start.sh` 會拒絕啟動

單獨啟動：

```bash
bash vllm_start.sh
bash litellm_start.sh
```

## 呼叫

OpenAI 相容 API，model 名稱 `gpt-oss-120b`：

```bash
set -a; source .env; set +a
curl -s "http://127.0.0.1:$LITELLM_PORT/v1/chat/completions" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"model": "gpt-oss-120b", "messages": [{"role": "user", "content": "Hello"}]}'
```

## 停止

- 前景執行：Ctrl-C
- 其他終端機：`docker stop vllm-gpt-oss-120b`

## 注意

- 共用 server 上，`127.0.0.1` 是所有使用者共用的：port 被占用時服務會起不來，同機的其他使用者也連得到你的 port（vLLM 那端沒有驗證）

- `GPUS` 的卡數用 1、2、4、8（tensor parallel 大小要能整除 attention head 數）
- `GPU_MEMORY_UTILIZATION`：單張 H100 80 GB 要 0.9 才放得下 60.8 GiB 權重；GB10（顯存與系統共用）原本用 0.75