# Toma Gateway 安全合約

狀態：設計合約。現在的 iOS Foundation 不發出模型或工具網路請求；GPT、Claude、Gemma 選擇器只控制本機 demo 回應。

## 邊界

```text
iOS（Pet／預覽／批准／記憶控制／收據 UI）
  -> 經驗證的 Toma Gateway
      -> policy engine + tool registry
      -> 租戶隔離 worker -> Hermes adapter
      -> GPT | Claude | Gemma-compatible endpoint
      -> MCP | Home Assistant | 其他 allowlisted connector
      -> memory | cron | goals | subagents
```

iOS 不持有 provider、Hermes、MCP 或家庭設備憑證。Gateway 負責驗證身分、每租戶資料隔離、secret store、provider routing、限流、政策、冪等、稽核與補償式復原。Hermes profile 可分開使用體驗狀態，但不是程序、檔案系統或憑證的多租戶安全邊界；公開服務必須使用隔離 worker 與真正的 tenant-scoped storage。

## Provider-neutral run

`POST /v1/agent/runs`

```json
{
  "pet_id": "uuid",
  "intent": "prepare_tomorrow",
  "provider_preference": "gemma",
  "conversation": [{"role": "user", "text": "幫我準備明天"}],
  "memory_ids": ["user-approved-memory-id"],
  "client_request_id": "uuid"
}
```

Gateway 可回傳純對話，或一份可檢查的 draft。draft 必須含穩定 action ID、白話效果、需要的權限、風險級別、可否復原與有效期限，不含可直接執行的原始模型輸出。

## 批准與執行

`POST /v1/agent/runs/{run_id}/approve`

```json
{
  "draft_version": 1,
  "plan_digest": "sha256-of-canonical-preview",
  "approved_action_ids": ["action-id"],
  "idempotency_key": "uuid",
  "policy_version": "server-issued"
}
```

執行前重新驗證使用者、pet owner、canonical preview digest、版本、期限、connector scope 與目前政策；client 傳入的 `pet_id` 或 receipt 永遠不能單獨作為授權依據。任何效果改變都必須產生新預覽並重新批准。模型只能提案；憑證與工具呼叫由政策層掌管。家庭或商店控制要有 connector-specific policy、最小 scope 與執行後 read-back 才能進入產品。

## 事件與收據

狀態可以串流，但完成的唯一證明是 durable receipt：

```json
{
  "receipt_id": "uuid",
  "pet_id": "uuid",
  "run_id": "uuid",
  "plan_digest": "sha256-of-canonical-preview",
  "status": "verified",
  "effects": [{"action_id": "action-id", "observed": "read-back result"}],
  "executed_at": "RFC3339 timestamp",
  "undo": {"available": true, "expires_at": "RFC3339 timestamp"}
}
```

狀態限 `verified`、`partial`、`failed`、`reverted`。connector 回覆成功不等於驗證；需讀回結果才可標記 `verified`，也只有這種收據能增加 pet XP。server 必須在同一個 tenant-scoped transaction 寫入 receipt 與 `GrowthAward`。`POST /v1/receipts/{receipt_id}/undo` 必須冪等，產生含 `reverts_receipt_id` 的新復原收據並撤銷相連的 growth award。無法真正逆轉的動作要在預覽中明示，不能假裝支援 undo。

## 記憶、秘密與工具

- 一次 run 只使用使用者明確選取的記憶；新記憶先預覽再確認，刪除要同步主存儲、索引與 cache tombstone。
- 原始語音預設不保存；秘密與敏感 payload 不得進入模型上下文、analytics、crash report 或一般收據。
- 工具 schema、tenant scope、timeout、idempotency、risk class 與補償動作全部在伺服器註冊。
- App Intents 只能送出 Toma 的三個產品 intent，不得成為任意工具入口。
- Hermes adapter 受相同政策、sandbox、稽核與批准約束，不能成為特權繞道。

## 分階段交付

- **Foundation（現在）**：只驗證本機信任迴圈與 Pet 成長語意。
- **Gateway（下一步）**：帳號、租戶資料、隔離 worker、真實 provider、Hermes adapter、串流與 server receipt。
- **Tools（之後）**：從一個低風險、可讀回且可補償的 connector 開始，再逐步加入 MCP、Home Assistant、cron、goals 與 subagents。
