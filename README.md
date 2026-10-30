# Summon Local GPT-OSS-120B

在本機用 vLLM 跑 gpt-oss-120b，前面接 LiteLLM proxy。兩個服務都只綁 `127.0.0.1`，只有本機連得到。不需要 Docker：vLLM 和 LiteLLM 各自裝在 repo 內的 venv。

> ⚠️ **NVIDIA driver 版本決定能用的 vLLM 版本**
>
> - 這個 repo 鎖定 `vllm==0.19.1`（torch 2.10，CUDA 12.8），需要 driver ≥ 570
> - vLLM 0.20 以後改用 CUDA 13，需要 driver ≥ 580；driver 夠新時再改 `requirements/vllm.in` 升級
> - 安裝前先用 `nvidia-smi` 確認 `Driver Version`

```
client ──> LiteLLM :LITELLM_PORT ──> vLLM :VLLM_PORT (gpt-oss-120b)
```

## 檔案

| 檔案 | 用途 |
|---|---|
| `install.sh` | 用 uv 建立 `.venv-vllm`、`.venv-litellm` 並安裝鎖定版本 |
| `start.sh` | 一鍵啟動 vLLM + LiteLLM，Ctrl-C 一起停 |
| `vllm_start.sh` | 單獨啟動 vLLM，就緒後印出 greeting |
| `litellm_start.sh` | 單獨啟動 LiteLLM |
| `config.yaml` | LiteLLM 設定，只有 `gpt-oss-120b` |
| `.env.example` | 設定範本，複製成 `.env` 後填寫 |
| `requirements/*.in` | 直接依賴的版本（`vllm==0.19.1`、`litellm[proxy]==1.106.6`） |
| `requirements/*.txt` | 完整鎖定的依賴，由 `lock.sh` 產生 |
| `lock.sh` | 改了 `*.in` 之後重新鎖定 |

## 最低需求

| 項目 | 需求 |
|---|---|
| GPU | NVIDIA GPU，顯存要放得下 60.8 GiB 權重加 KV cache：單張 80 GB（`GPU_MEMORY_UTILIZATION=0.9`），或兩張以上 |
| NVIDIA driver | ≥ 570（鎖定的 torch 2.10 用 CUDA 12.8；`install.sh` 會檢查並警告） |
| 磁碟 | `HF_HOME` 約 61 GiB（權重），另加兩個 venv（vLLM 那個含 torch，數 GB 起跳） |
| 系統 | Linux x86_64，Bash ≥ 5.1（`start.sh` 用到 `wait -n <pid>`） |
| Python | [uv](https://docs.astral.sh/uv/)；Python 3.12（uv 找不到時會自己下載） |
| 其他 | `curl`；產生 key 需要 `openssl` |

`HF_HOME` 底下要有：
  - `hub/models--openai--gpt-oss-120b`（權重）
  - `tiktoken_encodings/`（`*.tiktoken`，離線時 harmony 需要）

## 安裝

```bash
bash install.sh
```

可以重複執行；已存在的 venv 會被同步成鎖定的版本。

要升級版本時，改 `requirements/*.in`，再執行：

```bash
bash lock.sh
bash install.sh
```

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

- 不用先啟用任何 venv，腳本直接呼叫 repo 內 venv 的執行檔
- LiteLLM 幾秒內就緒；vLLM 要載入權重，印出 `===== gpt-oss-120b is ready =====` 之後才能用
- 任一服務掛掉，另一個也會被停掉
- port 已被占用時會直接報錯，不會啟動

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
- 其他終端機：`kill <start.sh 或 vllm_start.sh 的 PID>`（送 TERM，腳本會關掉 vLLM 再結束）

## 注意

- 共用 server 上，`127.0.0.1` 是所有使用者共用的：port 被占用時服務會起不來，同機的其他使用者也連得到你的 port（vLLM 那端沒有驗證）
- `GPUS` 的卡數用 1、2、4、8（tensor parallel 大小要能整除 attention head 數）
- `GPU_MEMORY_UTILIZATION`：單張 H100 80 GB 要 0.9 才放得下 60.8 GiB 權重；GB10（顯存與系統共用）原本用 0.75
