import CryptoKit
import Foundation

enum ModelProvider: String, Codable, CaseIterable, Identifiable {
    case gpt
    case claude
    case gemma

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt: "GPT"
        case .claude: "Claude"
        case .gemma: "Gemma"
        }
    }
}

enum ChatRole: String, Codable {
    case user
    case pet
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: ChatRole
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), role: ChatRole, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

struct MemoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isEnabledForAgent: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        isEnabledForAgent: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.isEnabledForAgent = isEnabledForAgent
        self.createdAt = createdAt
    }
}

struct TomorrowPlanItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isEnabled: Bool

    init(id: UUID = UUID(), text: String, isEnabled: Bool = true) {
        self.id = id
        self.text = text
        self.isEnabled = isEnabled
    }
}

enum TomorrowPlanStatus: String, Codable {
    case draft
    case approved
}

struct TomorrowPlan: Identifiable, Codable, Equatable {
    let id: UUID
    var version: Int
    var title: String
    var items: [TomorrowPlanItem]
    var reminderEnabled: Bool
    var status: TomorrowPlanStatus
    var approvedContentDigest: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        version: Int = 1,
        title: String,
        items: [TomorrowPlanItem],
        reminderEnabled: Bool = true,
        status: TomorrowPlanStatus = .draft,
        approvedContentDigest: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.version = version
        self.title = title
        self.items = items
        self.reminderEnabled = reminderEnabled
        self.status = status
        self.approvedContentDigest = approvedContentDigest
        self.createdAt = createdAt
    }
}

private struct PlanApprovalPayload: Codable {
    let id: UUID
    let version: Int
    let title: String
    let items: [TomorrowPlanItem]
    let reminderEnabled: Bool
}

extension TomorrowPlan {
    var approvalDigest: String {
        if let approvedContentDigest {
            return approvedContentDigest
        }
        let payload = PlanApprovalPayload(
            id: id,
            version: version,
            title: title,
            items: items,
            reminderEnabled: reminderEnabled
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(payload)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum ReceiptStatus: String, Codable {
    case verified
    case partial
    case failed
    case reverted
}

struct TaskReceipt: Identifiable, Codable, Equatable {
    let id: UUID
    let petID: UUID
    let planID: UUID
    let planVersion: Int
    let planDigest: String
    var status: ReceiptStatus
    var summary: String
    let createdAt: Date
    let notificationIdentifier: String?
    let xpAwarded: Int
    var observedEffects: [String]
    var canUndo: Bool

    init(
        id: UUID = UUID(),
        petID: UUID,
        planID: UUID,
        planVersion: Int,
        planDigest: String,
        status: ReceiptStatus,
        summary: String,
        createdAt: Date = Date(),
        notificationIdentifier: String? = nil,
        xpAwarded: Int = 0,
        observedEffects: [String] = [],
        canUndo: Bool
    ) {
        self.id = id
        self.petID = petID
        self.planID = planID
        self.planVersion = planVersion
        self.planDigest = planDigest
        self.status = status
        self.summary = summary
        self.createdAt = createdAt
        self.notificationIdentifier = notificationIdentifier
        self.xpAwarded = xpAwarded
        self.observedEffects = observedEffects
        self.canUndo = canUndo
    }
}

struct InFlightExecution: Codable, Equatable {
    let operationID: UUID
    let petID: UUID
    let planID: UUID
    let planVersion: Int
    let planDigest: String
    let notificationIdentifier: String?
    let preparedAt: Date
}

struct AppSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var selectedProvider: ModelProvider
    var messages: [ChatMessage]
    var memories: [MemoryEntry]
    var pendingPlan: TomorrowPlan?
    var approvedPlan: TomorrowPlan?
    var receipts: [TaskReceipt]
    var petProfile: PetProfile
    var inFlightExecution: InFlightExecution?
    var pendingNotificationCleanupIDs: Set<String>

    var petXP: Int { petProfile.growth.xp }

    var growthLedgerIsConsistent: Bool {
        guard Set(receipts.map(\.id)).count == receipts.count,
              Set(petProfile.growth.awards.map(\.id)).count == petProfile.growth.awards.count else {
            return false
        }

        let activeAwards = petProfile.growth.awards.filter { $0.revokedAt == nil }
        let eligibleReceipts = receipts.filter {
            $0.petID == petProfile.id && $0.status == .verified && $0.xpAwarded == 20
        }
        guard Set(activeAwards.map(\.id)) == Set(eligibleReceipts.map(\.id)) else { return false }

        return petProfile.growth.awards.allSatisfy { award in
            award.petID == petProfile.id
                && award.points == 20
                && receipts.contains { receipt in
                    receipt.id == award.id
                        && receipt.petID == award.petID
                        && receipt.xpAwarded == award.points
                }
        }
    }

    static var initial: AppSnapshot {
        AppSnapshot(
            schemaVersion: 2,
            selectedProvider: .gemma,
            messages: [
                ChatMessage(role: .pet, text: "嗨，我剛孵化。先聊聊，或讓我幫你準備明天。")
            ],
            memories: [],
            pendingPlan: nil,
            approvedPlan: nil,
            receipts: [],
            petProfile: .initial,
            inFlightExecution: nil,
            pendingNotificationCleanupIDs: []
        )
    }
}

enum PetActivity: Equatable {
    case idle
    case listening
    case working
    case waitingForApproval
    case celebrating
    case failed

    var label: String {
        switch self {
        case .idle: "陪著你"
        case .listening: "正在聽"
        case .working: "正在整理"
        case .waitingForApproval: "等你確認"
        case .celebrating: "任務完成"
        case .failed: "需要你看看"
        }
    }
}

enum PetStage: Int, Codable, CaseIterable {
    case hatchling
    case companion
    case guardian

    init(xp: Int) {
        if xp >= 60 {
            self = .guardian
        } else if xp >= 20 {
            self = .companion
        } else {
            self = .hatchling
        }
    }

    var title: String {
        switch self {
        case .hatchling: "初生夥伴"
        case .companion: "默契夥伴"
        case .guardian: "日常守護者"
        }
    }

    var scale: Double {
        switch self {
        case .hatchling: 0.9
        case .companion: 1.0
        case .guardian: 1.08
        }
    }

    var progress: Double {
        switch self {
        case .hatchling: 0
        case .companion: 0.5
        case .guardian: 1
        }
    }
}

enum PetArchetype: String, Codable, CaseIterable, Identifiable {
    case warm
    case focused
    case adventurous

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .warm: "溫暖陪伴"
        case .focused: "專注行動"
        case .adventurous: "好奇探索"
        }
    }

    var summary: String {
        switch self {
        case .warm: "先理解你的感受，再一起往前。"
        case .focused: "把複雜事情拆成下一個可執行步驟。"
        case .adventurous: "主動提出新角度，但仍由你批准行動。"
        }
    }
}

struct GrowthAward: Identifiable, Codable, Equatable {
    let id: UUID
    let petID: UUID
    let points: Int
    let verifiedAt: Date
    var revokedAt: Date?
}

struct PetGrowth: Codable, Equatable {
    var awards: [GrowthAward] = []

    var xp: Int {
        awards
            .filter { $0.revokedAt == nil }
            .reduce(0) { $0 + $1.points }
    }

    var stage: PetStage { PetStage(xp: xp) }
}

enum HatchJobPhase: String, Codable, Equatable {
    case queued
    case generating
    case validating
    case ready
    case failed
}

struct HatchPackageReference: Identifiable, Codable, Equatable {
    let id: UUID
    let version: Int
    let targetStage: PetStage
    let spriteVersionNumber: Int
    let atlasSHA256: String
    let validationReceiptID: UUID

    var hasValidV2Metadata: Bool {
        version > 0
            && spriteVersionNumber == 2
            && atlasSHA256.count == 64
            && atlasSHA256.allSatisfy { $0.isHexDigit }
    }
}

struct HatchJob: Identifiable, Codable, Equatable {
    let id: UUID
    let petID: UUID
    let targetStage: PetStage
    var phase: HatchJobPhase
    var package: HatchPackageReference?
    var failureCode: String?
}

struct PetProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var archetype: PetArchetype
    var growth: PetGrowth
    var activePackage: HatchPackageReference
    var pendingHatchJob: HatchJob?

    static var initial: PetProfile {
        PetProfile(
            id: UUID(),
            name: "苗苗",
            archetype: .warm,
            growth: PetGrowth(),
            activePackage: HatchPackageReference(
                id: UUID(uuidString: "98BFA190-5B17-40A9-8C47-3DA80D44CA7F")!,
                version: 1,
                targetStage: .hatchling,
                spriteVersionNumber: 2,
                atlasSHA256: "06477704465847004132c3a1fed4c0892b8d118d1f46018423fbfaf6aa216cd0",
                validationReceiptID: UUID(uuidString: "897F8863-842C-46E8-9F30-2B6BF8AEE6B2")!
            ),
            pendingHatchJob: nil
        )
    }

    @discardableResult
    mutating func applyVerifiedReceipt(_ receipt: TaskReceipt) -> Bool {
        guard receipt.petID == id,
              receipt.status == .verified,
              receipt.xpAwarded == 20,
              !growth.awards.contains(where: { $0.id == receipt.id }) else {
            return false
        }

        growth.awards.append(
            GrowthAward(
                id: receipt.id,
                petID: id,
                points: receipt.xpAwarded,
                verifiedAt: receipt.createdAt,
                revokedAt: nil
            )
        )
        return true
    }

    @discardableResult
    mutating func revokeGrowth(for receiptID: UUID, at date: Date) -> Bool {
        guard let index = growth.awards.firstIndex(where: {
            $0.id == receiptID && $0.petID == id && $0.revokedAt == nil
        }) else {
            return false
        }
        growth.awards[index].revokedAt = date
        return true
    }

    @discardableResult
    mutating func activateReadyHatch(downloadedAtlasSHA256: String) -> Bool {
        guard let job = pendingHatchJob,
              job.petID == id,
              job.phase == .ready,
              job.targetStage == growth.stage,
              let package = job.package,
              package.targetStage == job.targetStage,
              package.version > activePackage.version,
              package.hasValidV2Metadata,
              package.atlasSHA256.lowercased() == downloadedAtlasSHA256.lowercased() else {
            return false
        }

        activePackage = package
        pendingHatchJob = nil
        return true
    }
}
