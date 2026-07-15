# Toma

Toma 是一隻會成長、也能替使用者做事的 iPhone 電子雞。這個 repo 先完成一條可信任、可復原的 Agent 體驗：提出草稿、等待批准、執行、讀回結果、留下收據，必要時復原。

## 目前可用

- 一個裝置本機的 Pet Profile，可設定名字與原型；正式帳號與多隻寵物留給 Gateway 階段
- 文字對話與裝置端語音轉文字
- GPT、Claude、Gemma 選擇器；目前都接確定性的本機 demo，尚未呼叫真實模型
- 「幫我準備明天」：預覽、批准、本機執行、收據與復原
- 明日提醒預設關閉；無提醒的已驗證任務可由使用者封存，保留成長並開始下一次
- 使用者可查看、加入與刪除的記憶簿
- 恰好三個 App Intents：問電子雞、準備我的明天、繼續待確認任務
- 經驗與進化只由可稽核的已驗證收據驅動

成長規則與自訂外觀流程見 [docs/pet-lifecycle.md](docs/pet-lifecycle.md)。Hermes 能力是後端路線，不是目前 app 的能力聲明；邊界見 [docs/hermes-capability-map.md](docs/hermes-capability-map.md) 與 [docs/backend-contract.md](docs/backend-contract.md)。

## 執行

```sh
ruby scripts/generate_project.rb
open Toma.xcodeproj
```

選擇 iOS 17 以上模擬器並執行 `Toma` scheme。

`Toma/Resources/pet-sprites.png` 是不納入 Git 的私人測試素材。檔案存在時，只會複製到本機 Debug build；缺少時 App 使用內建 `bird.fill` 外觀，Release build 永遠不包含這份私人素材。

## 驗證

```sh
./scripts/check.sh
```

可用 `DESTINATION` 指定模擬器。語音辨識與 Siri 句型仍需在實機、實際語系下驗證後才能發佈。

## 路線

1. **Foundation（現在）**：本機 Pet Profile、可信任任務迴圈、記憶、成長與三個 App Intents。
2. **Gateway（下一步）**：登入、租戶隔離、真實 GPT／Claude／Gemma 路由、Hermes adapter、伺服器端秘密與稽核。
3. **Tools（之後）**：經政策限制的工具、MCP、Home Assistant、排程、目標與子代理；所有外部效果仍要預覽、批准、驗證與收據。
