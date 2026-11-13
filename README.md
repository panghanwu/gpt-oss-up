# Summon Local GPT-OSS

在本機用 vLLM 跑 gpt-oss（120b 或 20b），前面接 LiteLLM proxy，可以再加裝 Open WebUI 當聊天介面。所有服務都只綁 `127.0.0.1`，只有本機連得到。不需要 Docker：每個服務各自裝在 repo 內的 venv。

```
browser ──> Open WebUI :OPENWEBUI_PORT ──┐  (bash install.sh full)
client  ─────────────────────────────────┴──> LiteLLM :LITELLM_PORT ──> vLLM :VLLM_PORT (gpt-oss)
```

## 平台

| 平台 | vLLM 鎖定版本 | NVIDIA driver | 狀態 |
|---|---|---|---|
| DGX Spark（GB10，aarch64） | `vllm==0.33.0`（CUDA 13.0） | ≥ 580 | ✅ 已驗證：`backend`、`full`，120b、20b |
| DGX server（H200／H100／A100，x86_64） | `vllm==0.19.1`（CUDA 12.8） | ≥ 570 | ⚠️ 未驗證（`backend` 之前在 H200 跑過，這次的改動沒有在 x86_64 上測） |
| 一般 x86_64 NVIDIA 機器 | 同上 | ≥ 570 | ⚠️ 未驗證 |
| Mac（Apple Silicon） | 無 | — | ❌ 尚未支援：沒有 `requirements/vllm.arm64.txt`，`install.sh` 會直接報錯 |

- `install.sh` 用 `uname -m` 選 `requirements/vllm.<arch>.txt`；LiteLLM 和 Open WebUI 的鎖定是跨平台的同一份
- aarch64 的鎖定另外裝 `flashinfer-cubin`（下載約 1.7 GB，裝好約 7 GB，來自 FlashInfer 自己的 index）：預先編好的 FlashInfer kernel，少了它 vLLM 每次啟動都會連 NVIDIA 的 artifactory 檢查、需要時再下載 kernel
- x86_64 的 driver ≥ 580 時，可以把 `requirements/vllm.x86_64.in` 升到 CUDA 13 的版本（vLLM 0.20 以後）
- 安裝前先用 `nvidia-smi` 確認 `Driver Version`

## 檔案

| 檔案 | 用途 |
|---|---|
| `install.sh` | 用 uv 建立 venv 並安裝鎖定版本：`backend`（預設）或 `full` |
| `start.sh` | 一鍵啟動所有已安裝的服務，Ctrl-C 一起停 |
| `vllm_start.sh` | 單獨啟動 vLLM，就緒後印出 greeting |
| `litellm_start.sh` | 單獨啟動 LiteLLM |
| `openwebui_start.sh` | 單獨啟動 Open WebUI（等 vLLM 就緒才啟動）；Open WebUI 的設定都寫在這裡 |
| `env.sh` | 各 `*_start.sh` 共用：讀 `.env`，依 `MODEL` 決定模型名稱與 `GPU_MEMORY_UTILIZATION` 預設 |
| `config.yaml` | LiteLLM 設定，只有一個 model（名稱由 `MODEL` 決定） |
| `.env.example` | 設定範本，複製成 `.env` 後填寫 |
| `requirements/*.in` | 直接依賴的版本；vLLM 依 CPU 架構分開（`vllm.x86_64.in`、`vllm.aarch64.in`） |
| `requirements/*.txt` | 完整鎖定的依賴，由 `lock.sh` 產生 |
| `lock.sh` | 改了 `*.in` 之後重新鎖定 |

## 最低需求

| 項目 | 需求 |
|---|---|
| GPU | NVIDIA GPU。120b 要放得下 60.8 GiB 權重加 KV cache：DGX Spark、單張 80 GB（`GPU_MEMORY_UTILIZATION=0.9`），或兩張以上；20b 權重約 13 GiB |
| NVIDIA driver | 見上方「平台」；`install.sh` 會檢查並警告 |
| 磁碟 | `HF_HOME`：120b 約 61 GiB、20b 約 13 GiB；venv（DGX Spark 實測）：`backend` 約 17 GB（其中 `flashinfer-cubin` 約 7 GB），`full` 再加約 1.5 GB（Open WebUI 和 vLLM 共用 torch 與 CUDA 套件） |
| 系統 | Linux x86_64 或 aarch64，Bash ≥ 5.1（`start.sh` 用到 `wait -n <pid>`） |
| Python | [uv](https://docs.astral.sh/uv/)；venv 用 uv 管理的 Python 3.12（第一次會自動下載） |
| 其他 | `curl`；產生 key 需要 `openssl` |

uv 用官方 installer 安裝（Ubuntu 24.04 的系統 Python 不允許直接 `pip install`）：

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

`HF_HOME` 底下要有：
  - `hub/models--openai--gpt-oss-120b` 或 `hub/models--openai--gpt-oss-20b`（權重，看 `MODEL`）
  - `tiktoken_encodings/`（`*.tiktoken`，離線時 harmony 需要）

缺權重時，裝好之後可以用 venv 裡的 `hf` 下載（需要連網；`original/`、`metal/` 是其他格式的權重，vLLM 用不到）：

```bash
HF_HOME=/path/to/huggingface .venv-vllm/bin/hf download openai/gpt-oss-20b --exclude 'original/*' --exclude 'metal/*'
```

## 安裝

```bash
bash install.sh        # backend：vLLM + LiteLLM（等同 bash install.sh backend）
bash install.sh full   # backend 再加 Open WebUI
```

- 可以重複執行；已存在的 venv 會被同步成鎖定的版本
- `start.sh` 依 `.venv-openwebui` 存不存在決定要不要啟動 Open WebUI；裝過 `full` 之後想回到只有 backend，刪掉 `.venv-openwebui` 即可

要升級版本時，改 `requirements/*.in`，再執行：

```bash
bash lock.sh
bash install.sh   # 或 bash install.sh full
```

## 設定

```bash
cp .env.example .env
```

| 變數 | 說明 |
|---|---|
| `HF_HOME` | HF cache 根目錄（權重與 tiktoken） |
| `MODEL` | `120b` 或 `20b`（沒設時為 `120b`）；決定 vLLM 載入的模型與 model 名稱 `gpt-oss-120b`／`gpt-oss-20b` |
| `VLLM_PORT` | vLLM 的 port（預設 28000） |
| `LITELLM_PORT` | LiteLLM 的 port，API client 連這個（預設 24000） |
| `OPENWEBUI_PORT` | Open WebUI 的 port，瀏覽器連這個（預設 28080） |
| `GPUS` | GPU 編號，例如 `0` 或 `2,3`；tensor parallel 大小 = 卡數 |
| `GPU_MEMORY_UTILIZATION` | 選填，vLLM 每張卡可用的顯存比例；沒設時依 `MODEL` 用 `env.sh` 的預設，在 DGX Spark 實測：120b 用 0.75、20b 用 0.35，KV cache 都約 25 GiB（120b 約 70 萬 tokens、20b 約 100 萬 tokens），足夠同時跑 5 個以上 131k context 的請求 |
| `LITELLM_MASTER_KEY` | 呼叫 LiteLLM 用的 key；Open WebUI 也用它連 LiteLLM |
| `OPENWEBUI_FILE_UPLOAD` | Open WebUI 聊天中上傳檔案：`false`（預設）或 `true`，見下方「上傳檔案」 |

`LITELLM_MASTER_KEY` 可以用指令產生：

```bash
echo "sk-$(openssl rand -hex 32)"
```

## 啟動

```bash
bash start.sh
```

- 不用先啟用任何 venv，腳本直接呼叫 repo 內 venv 的執行檔
- LiteLLM 幾秒內就緒；vLLM 要載入權重，印出 `===== gpt-oss-120b is ready =====`（20b 則是 `gpt-oss-20b`）之後才能用；DGX Spark 實測 120b 約 8 分鐘（大部分是讀權重），20b 約 3.5 分鐘
- 裝了 Open WebUI 時，它等 vLLM 就緒才啟動；印出 `===== Open WebUI is ready: http://127.0.0.1:28080 =====` 後用瀏覽器打開
- 任一服務掛掉，其他也會被停掉
- port 已被占用時會直接報錯，不會啟動

單獨啟動：

```bash
bash vllm_start.sh
bash litellm_start.sh
bash openwebui_start.sh   # 會先等 vLLM 就緒
```

## Open WebUI

- 本機單人使用：不用註冊或登入，打開就是聊天畫面；唯一的使用者是 admin
- 只連 LiteLLM，不直接連 vLLM，不連 Ollama
- 只留聊天：網頁搜尋、知識庫、圖片生成、code interpreter／程式執行、tools／functions、memory、notes、channels 等功能都關閉；背景的 follow-up 建議、tags、autocomplete 也關閉，只保留自動產生聊天標題
- 唯一的使用者是 admin，而 Open WebUI 對 admin 不套用權限設定，所以有些入口關不掉：左下選單的 Workspace、Playground、Admin Panel，以及輸入框「+」→「Add Context」；上面列的功能已全域關閉，其中只有「Attach Webpage」仍可以點（貼上網址時，伺服器會去抓那個網頁）
- 執行期不主動連外（`OFFLINE_MODE=True`）：不下載任何模型、不檢查更新
- gpt-oss 的思考過程顯示成可展開的區塊，答案正常顯示

### 設定以腳本為準

Open WebUI 預設會在第一次啟動時把設定寫進自己的資料庫，之後環境變數就不再生效。`openwebui_start.sh` 設了 `ENABLE_PERSISTENT_CONFIG=False`，每次啟動都以腳本裡的設定為準：

- 在管理員設定裡改的東西，重新啟動後會還原；要長期改，改 `openwebui_start.sh`
- 聊天記錄存在 `.openwebui-data/`（已在 `.gitignore`）
- 要完全重設（包括聊天記錄）：停掉服務後刪除 `.openwebui-data/`

### 上傳檔案

預設關閉。打開後，Open WebUI 要用 embedding 模型（`sentence-transformers/all-MiniLM-L6-v2`）處理上傳的檔案；執行期是離線的，所以要先把模型下載到 `HF_HOME`（約 0.9 GiB；離線載入會檢查 snapshot 是否完整，不能只下載部分檔案）：

```bash
HF_HOME=/path/to/huggingface .venv-openwebui/bin/hf download sentence-transformers/all-MiniLM-L6-v2
```

然後在 `.env` 設 `OPENWEBUI_FILE_UPLOAD=true`，重新啟動。少了模型時 Open WebUI 仍會啟動，但上傳的檔案無法處理，log 會出現 `IncompleteSnapshotError` 或 `Error loading SentenceTransformer`。

## 呼叫

OpenAI 相容 API，model 名稱是 `gpt-oss-120b` 或 `gpt-oss-20b`（看 `MODEL`）：

```bash
set -a; source .env; set +a
curl -s "http://127.0.0.1:$LITELLM_PORT/v1/chat/completions" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"model": "gpt-oss-120b", "messages": [{"role": "user", "content": "Hello"}]}'
```

## 停止

- 前景執行：Ctrl-C（按一次就好，停止過程中再按會被忽略）
- 其他終端機：`kill <start.sh 或 *_start.sh 的 PID>`（送 TERM，腳本會關掉自己的服務再結束）
- vLLM 就緒後幾秒內就會停；還在載入權重時它不理會 TERM，`vllm_start.sh` 等 15 秒後強制結束（DGX Spark 實測：就緒後約 3 秒，載入中約 15 秒）
- 不要用 `kill -9` 停腳本：vLLM 跑在自己的 process group，腳本被強制結束時它會留下來繼續占記憶體。萬一留下了（`nvidia-smi` 看得到 `VLLM::EngineCore`），用 `pkill -KILL -f 'vllm serve|VLLM::EngineCore'` 清掉（會結束這個帳號下所有的 vLLM）

## 注意

- 共用 server 上，`127.0.0.1` 是所有使用者共用的：port 被占用時服務會起不來，同機的其他使用者也連得到你的 port（vLLM 那端沒有驗證；Open WebUI 關掉了登入）
- `GPUS` 的卡數用 1、2、4、8（tensor parallel 大小要能整除 attention head 數）
- `GPU_MEMORY_UTILIZATION`：單張 H100 80 GB 跑 120b 要 0.9 才放得下 60.8 GiB 權重；DGX Spark 的 GPU 和系統共用記憶體，比例設太高會壓縮系統與 Open WebUI 可用的記憶體
- DGX Spark 第一次啟動 vLLM 時，FlashInfer 會現場編譯 GB10 用的幾個 kernel（用 venv 裡的 `ninja`），結果快取在 `~/.cache/flashinfer`，之後的啟動就不用再編
- 執行期不主動連外：vLLM 只讀 `HF_HOME` 且不回報使用統計（`VLLM_NO_USAGE_STATS=1`），LiteLLM 用內建的模型價格表（`LITELLM_LOCAL_MODEL_COST_MAP=True`），Open WebUI 見上方；下載都在安裝期（`install.sh`、權重與 embedding 模型）
