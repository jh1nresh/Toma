# Toma iOS Foundation — PM Gate

Repo: `/Users/jhinresh/Documents/Codex/2026-07-15/new-chat/Toma`（獨立本機 repo；尚無 remote）

## 產品決策

先交付一隻會成長、可對話，且能安全完成一個實用任務的電子雞。這個切片證明完整信任迴圈，不把 provider key、Hermes 或任意工具 runtime 放進 iOS。

每位已登入使用者未來可建立一個或多個 Pet Profile；Foundation 先提供一個裝置本機 profile（名字、原型、可稽核成長）。正式帳號、多 pet 與跨裝置同步屬於 Gateway 階段。

## Foundation 驗收

- iOS 17+ 可建置與測試，專案／scheme 為 `Toma.xcodeproj`／`Toma`。
- 可文字對話，並在裝置與語系支援時使用裝置端語音轉文字。
- GPT、Claude、Gemma 可選，但目前只路由至確定性的本機 demo；不聲稱已連到真實模型。
- 「幫我準備明天」提供可讀草稿、明確批准、本機執行、read-back、收據與復原。
- 記憶對使用者可見、可加入與刪除。
- 恰好三個 App Intents：問電子雞、準備我的明天、繼續待確認任務。
- 成長只接受已批准且 receipt 為 `verified` 的執行，每筆 `+20 XP`；chat、draft、pending、partial、failed 都是 0，undo 撤銷連結 award。
- 明日提醒預設關閉；無提醒的 verified 任務可明確封存並保留 award，讓下一次任務與 60 XP 階段在真實 app flow 可達。
- 階段為 0–19「初生夥伴」、20–59「默契夥伴」、60+「日常守護者」。進化只改外觀、稱號與表情，不提高任何工具或家庭控制權限。
- 內附 8×11 v2 atlas 可通過 hatch-pet QA，並保持私有、不得上傳或重新產生。
- `./scripts/check.sh` 通過；Release simulator build 另行驗證。

## Hatch 合約

第一版產品範圍固定為三個預設 Pet（芽芽／溫暖陪伴、火花／主動行動、雲朵／冷靜整理）與三個進化階段（初生／默契／守護），共九個狀態。選擇 Pet 不加 XP，也不提高工具權限。

Foundation 只把自訂外觀願望標成 `saved locally`。完整流程依序是 `saved locally → Gateway accepted → queued → generating → validating → ready → signed receipt + local SHA-256 → explicit activation`。只有符合 hatch-pet 8×11 v2、QA／簽章／hash 與 request 綁定都通過的 package 能啟用；失敗時保留上一版 atlas。Foundation 不偽裝成已送出、已排隊或已具備雲端圖像生成服務。

## Hermes 方向

Hermes parity 是後端 roadmap，不是目前完成狀態。目標架構：

```text
Toma iOS
  -> authenticated Toma Gateway
      -> policy engine + tool registry
      -> isolated tenant worker + Hermes adapter
      -> provider routing + server-side secrets
      -> MCP / Home Assistant / memory / cron / goals / subagents
      -> durable receipts + compensating undo
```

Hermes profile 不視為多租戶安全邊界。公開服務需 tenant-scoped database、隔離 worker 與每租戶 credential scope。第一個 live connector 必須低風險、效果可讀回、可冪等，且能提供補償式復原。

## 路線與不做的事

1. **Foundation（現在）**：本機 Pet、對話、準備明天、批准／收據／復原、記憶與成長。
2. **Gateway（下一步）**：登入、租戶隔離、真實 provider、Hermes adapter、串流與 server receipt。
3. **Tools（之後）**：單一低風險 connector 通過信任 gate 後，才擴展 MCP、Home Assistant、cron、goals、subagents。

本切片不包含 production backend、live GPT／Claude／Gemma、Hermes runtime、家庭控制、硬體、帳號、雲端同步、付款、analytics、TestFlight 或 App Store 發佈。

## 執行與驗證邊界

- 預覽是唯讀；只有使用者批准後才能產生副作用。
- provider、connector 與 Hermes secrets 全留在未來的安全後端。
- 通知與語音權限由系統與使用者決定；Siri 句型及實際語音辨識需實機 QA。
- 真實 backend、credentials、remote tools、push、PR、TestFlight 與 App Store submission 需要另外明確授權。
- 驗證入口：`./scripts/check.sh`，再以 `xcodebuild -project Toma.xcodeproj -scheme Toma ...` 做 Release simulator build。

Owner: JhiNResH

Suggested labels: `ios`, `mvp`, `agent`, `pet`, `app-intents`, `trust-boundary`
