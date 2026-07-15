# Hermes 能力映射

Hermes parity 是 Toma 的後端目標，不是目前 iOS Foundation 的能力聲明。Toma 保留自己的批准、收據、復原、記憶控制與成長語意，再透過 Gateway 使用 Hermes runtime。

## 已由官方文件確認

| Hermes 能力 | Toma 的使用方式 |
|---|---|
| [`/hatch` pets](https://hermes-agent.nousresearch.com/docs/user-guide/features/pets) | 官方 pet 目前是 cosmetic；Toma 額外定義可稽核成長、版本化 atlas 與啟用流程。 |
| [Profiles](https://hermes-agent.nousresearch.com/docs/user-guide/profiles/) | 可隔開 Hermes 使用狀態，但不能當 SaaS 多租戶安全邊界；Toma 仍需隔離 worker、tenant storage 與 secret scope。 |
| [OpenAI-compatible API server](https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server/) | 作為 Toma Gateway 與 Hermes adapter 的整合面，支援 server-side runtime 與進度事件。 |
| [Tools](https://hermes-agent.nousresearch.com/docs/user-guide/features/tools/) | 經 Toma policy engine、allowlist、批准、read-back 與收據封裝後才能提供給使用者。 |
| [Security controls](https://hermes-agent.nousresearch.com/docs/user-guide/security/) | 當作執行層基礎；Toma 再加 tenant isolation、風險級別、plan digest 與補償式 undo。 |
| [Hermes Agent repository](https://github.com/NousResearch/hermes-agent) | 可研究或整合的 MIT 專案；若納入程式碼或散佈衍生內容，保留授權與 notice。 |

Hermes 原生覆蓋 provider routing、工具與 toolsets、MCP、memory／skills、cron、persistent goals、delegation／subagents、voice 與 Home Assistant 等方向。GPT、Claude 可作為第一級 provider；Gemma 走相容或自託管 endpoint。實際可用的 model、版本與 connector 必須由 Gateway 在部署時驗證，不能由 iOS 選擇器自行保證。

## Toma 必須補上的產品層

- 每次有副作用的工作都要：可讀預覽 → 綁定 digest 的批准 → 執行後 read-back → durable receipt → 可行時補償式復原。
- Pet Profile、GrowthAward 與 hatch package 都有 owner、版本、hash 與稽核鏈。
- 記憶由使用者看見、選取、確認與刪除；Hermes memory 不能繞過這個控制面。
- 所有工具和家庭設備授權與 Pet 進化完全分離。
- 公開服務使用真實租戶隔離；不把 Hermes profile、prompt 或單一共用主機帳號誤當 sandbox。

## 路線

1. **Foundation**：完成本機 Toma 體驗與信任狀態機。
2. **Gateway**：先接對話與一個 provider，再加入 Hermes adapter、server memory 與 receipt event。
3. **Tools**：從一個低風險、可驗證、可補償的任務開始，達標後才擴展 MCP、Home Assistant、cron、goals 與 subagents。
