import Foundation

protocol AgentGateway {
    func reply(
        to message: String,
        provider: ModelProvider,
        memories: [MemoryEntry]
    ) async throws -> String

    func prepareTomorrow(
        provider: ModelProvider,
        memories: [MemoryEntry],
        now: Date
    ) async throws -> TomorrowPlan
}

struct DemoAgentGateway: AgentGateway {
    func reply(
        to message: String,
        provider: ModelProvider,
        memories: [MemoryEntry]
    ) async throws -> String {
        let memoryNote = memories.isEmpty
            ? ""
            : " 我會使用你目前允許的 \(memories.count) 則記憶，但不在回覆裡重複原文。"
        return "我收到「\(message)」。這個原型目前用 \(provider.displayName) 的示範路由，不會把內容送到網路。\(memoryNote)"
    }

    func prepareTomorrow(
        provider: ModelProvider,
        memories: [MemoryEntry],
        now: Date
    ) async throws -> TomorrowPlan {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateFormat = "M 月 d 日 EEEE"
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now

        var items = [
            TomorrowPlanItem(text: "選出明天最重要的一件事"),
            TomorrowPlanItem(text: "把第一個可執行步驟放到早上"),
            TomorrowPlanItem(text: "預留 10 分鐘做開始前檢查")
        ]

        if !memories.isEmpty {
            items.insert(TomorrowPlanItem(text: "根據你允許的記憶，預留 15 分鐘處理相關事項"), at: 1)
        }

        return TomorrowPlan(
            title: "\(formatter.string(from: tomorrow)) 的準備",
            items: items,
            reminderEnabled: false
        )
    }
}
