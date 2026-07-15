import AppIntents
import Combine
import Foundation

struct PendingIntentAction: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case askPet
        case prepareTomorrow
        case continuePendingTask
    }

    let id: UUID
    let kind: Kind
    let question: String?

    init(id: UUID = UUID(), kind: Kind, question: String? = nil) {
        self.id = id
        self.kind = kind
        self.question = question
    }
}

@MainActor
final class IntentHandoffStore: ObservableObject {
    static let shared = IntentHandoffStore()

    @Published private(set) var pendingAction: PendingIntentAction?

    private init() {}

    func submit(_ action: PendingIntentAction) {
        pendingAction = action
    }

    func consume(id: UUID) {
        guard pendingAction?.id == id else { return }
        pendingAction = nil
    }
}

struct AskPetIntent: AppIntent {
    static let title: LocalizedStringResource = "問電子雞"
    static let description = IntentDescription("開啟 Toma 裡的電子雞並送出一個問題；Intent 本身不執行遠端工具。")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(
        title: "問題",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var question: String

    init() {}

    init(question: String) {
        self.question = question
    }

    func perform() async throws -> some IntentResult {
        let value = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 1_000 else {
            throw $question.needsValueError("請輸入 1 到 1000 個字的問題。")
        }

        await MainActor.run {
            IntentHandoffStore.shared.submit(
                PendingIntentAction(kind: .askPet, question: value)
            )
        }
        return .result()
    }
}

struct PrepareTomorrowIntent: AppIntent {
    static let title: LocalizedStringResource = "準備我的明天"
    static let description = IntentDescription("開啟 Toma 建立明日草稿；批准前不會設定提醒。")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            IntentHandoffStore.shared.submit(
                PendingIntentAction(kind: .prepareTomorrow)
            )
        }
        return .result()
    }
}

struct ContinuePendingTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "繼續待確認任務"
    static let description = IntentDescription("開啟 Toma 目前唯一的待確認草稿；不接受外部任務識別碼。")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            IntentHandoffStore.shared.submit(
                PendingIntentAction(kind: .continuePendingTask)
            )
        }
        return .result()
    }
}

struct TomaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskPetIntent(),
            phrases: ["問 \(.applicationName)"],
            shortTitle: "問電子雞",
            systemImageName: "bubble.left.fill"
        )

        AppShortcut(
            intent: PrepareTomorrowIntent(),
            phrases: ["用 \(.applicationName) 準備我的明天"],
            shortTitle: "準備我的明天",
            systemImageName: "sun.horizon.fill"
        )

        AppShortcut(
            intent: ContinuePendingTaskIntent(),
            phrases: ["用 \(.applicationName) 繼續待確認任務"],
            shortTitle: "繼續待確認任務",
            systemImageName: "hand.raised.fill"
        )
    }
}
