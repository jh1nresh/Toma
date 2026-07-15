# Pet 生命週期與進化規則

## 每個人都能建立自己的 Toma 嗎？

可以，但分兩階段完成：

- 現在的 Foundation：每台裝置有一個本機 Pet Profile，可設定名字與原型，成長紀錄可稽核。
- Gateway 上線後：每個已登入使用者擁有一個或多個 tenant-scoped `PetProfile`，可跨裝置同步；pet、記憶、收據與 connector 授權都綁定 owner。

個人化外觀不是即時任意圖片。hatch request 走固定流程：

```text
request -> queued -> generating -> validating -> ready
                                      |             |
                                      +-> failed    +-> SHA-256 check -> 使用者明確啟用
```

新 package 必須符合 hatch-pet 的 8×11 v2 atlas 合約、通過結構與視覺 QA，下載後比對 SHA-256。只有 `ready` 且 hash 正確的 package 能啟用；任何產生、驗證或下載失敗都繼續使用上一版 atlas。本機可能存在由使用者提供的私人 starter atlas；它已被 Git 忽略，只能進入本機 Debug build，不得上傳、重製、進入 Release build 或送給外部 provider。

## 進化

| XP | 階段 | 可見變化 |
|---:|---|---|
| 0–19 | 初生夥伴 | 基礎外觀、稱號與表情 |
| 20–59 | 默契夥伴 | 新的視覺階段與互動回饋 |
| 60+ | 日常守護者 | 成熟外觀、稱號與表情 |

每一筆 XP 都來自可追溯的 `GrowthAward`：

- 已明確批准的 run，且 durable receipt 為 `verified`：`+20 XP`。
- chat、draft、pending、partial、failed：`0 XP`。
- 同一 receipt 只能計分一次；pet ID 不相符時拒絕計分。
- undo／reverted receipt 撤銷原 receipt 對應的 award，階段隨可用 XP 回退。
- 無提醒的 verified 任務可由使用者明確封存：收據與 award 保留、計畫內容清除、放棄 undo，之後即可開始下一次。Foundation 的提醒預設關閉；開啟提醒的任務不提供這個封存捷徑。

進化永遠只改視覺、稱號、表情與個性呈現。它不會開啟工具、MCP、connector、Home Assistant、排程或更高風險權限。能力由使用者明確授權與伺服器政策決定；「陪伴很久」不能變成權限提升機制。

## Pet 與 Agent 的關係

Pet 是使用者看得見、會成長的身份；Agent runtime 是受管制的執行能力。兩者透過已驗證收據相連：Agent 真正完成有用工作，Pet 才成長。這保留情感回饋，也避免用聊天次數或黏著度灌 XP。
