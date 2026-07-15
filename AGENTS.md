# Toma working agreement

- 保持目前切片本機、確定性且可測試；不要把 provider SDK、API key、Hermes runtime 或任意遠端工具放進 iOS target。
- 保留信任順序：草稿 → 明確批准 → 執行 → 讀回 → 收據 → 復原。
- 只有已批准且收據狀態為 `verified` 的執行可以增加 XP；chat、draft、pending、partial、failed 都是 0 XP，復原要撤銷對應 award。
- 進化只改外觀、稱號與表情，不得提高工具、connector、MCP 或家庭控制權限。
- 記憶必須對使用者可見、可選擇、可刪除。
- 只暴露三個 App Intents：問電子雞、準備我的明天、繼續待確認任務。
- `Toma/Resources/pet-sprites.png` 是私有、由使用者提供的素材；不得上傳、重新產生或送給外部 provider。
- 新 hatch package 必須符合 hatch-pet 8×11 v2、通過 QA 與 SHA-256 驗證，並由使用者明確啟用；失敗時保留現有 atlas。
- 本機保存的 hatch 願望只能標示為 `savedLocally`；只有經驗證的 Gateway 回應能標示 `queued`，不得用假進度或假預覽暗示圖片已生成。
- Hermes 只能位於通過驗證的 Toma Gateway 後方。Hermes profile 不是多租戶安全邊界。
- 宣稱完成前執行 `./scripts/check.sh`；修改 project 設定後也要確認 `Toma.xcodeproj`／`Toma` scheme 可建置。
