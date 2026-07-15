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

    var wireName: String {
        switch self {
        case .hatchling: "hatchling"
        case .companion: "companion"
        case .guardian: "guardian"
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

enum PetPreset: String, Codable, CaseIterable, Identifiable {
    case sprout
    case spark
    case cloud

    var id: String { rawValue }

    var defaultName: String {
        switch self {
        case .sprout: "芽芽"
        case .spark: "火花"
        case .cloud: "雲朵"
        }
    }

    var role: String {
        switch self {
        case .sprout: "溫暖・陪伴型"
        case .spark: "主動・行動型"
        case .cloud: "冷靜・整理型"
        }
    }

    var summary: String {
        switch self {
        case .sprout: "先接住你的感受，再陪你走下一步。"
        case .spark: "主動把想法變成清楚、可批准的行動。"
        case .cloud: "把混亂慢慢整理成安定、有順序的選擇。"
        }
    }

    var archetype: PetArchetype {
        switch self {
        case .sprout: .warm
        case .spark: .focused
        case .cloud: .calm
        }
    }

    static func resolving(_ legacyArchetype: PetArchetype) -> PetPreset {
        switch legacyArchetype {
        case .warm: .sprout
        case .focused: .spark
        case .calm, .adventurous: .cloud
        }
    }
}

enum PetArchetype: String, Codable, CaseIterable, Identifiable {
    case warm
    case focused
    case calm
    case adventurous

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .warm: "溫暖陪伴"
        case .focused: "專注行動"
        case .calm: "冷靜整理"
        case .adventurous: "好奇探索"
        }
    }

    var summary: String {
        switch self {
        case .warm: "先理解你的感受，再一起往前。"
        case .focused: "把複雜事情拆成下一個可執行步驟。"
        case .calm: "先整理脈絡，再提出安定清楚的下一步。"
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

enum HatchStylePreset: String, Codable, CaseIterable, Identifiable {
    case auto
    case pixel
    case plush
    case clay
    case sticker

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "自動搭配"
        case .pixel: "像素"
        case .plush: "絨毛"
        case .clay: "黏土"
        case .sticker: "貼紙"
        }
    }

    var summary: String {
        switch self {
        case .auto: "由 Hatch 服務在既有角色特徵內選擇合適風格。"
        case .pixel: "清楚輪廓、有限色盤與像素質感。"
        case .plush: "柔軟材質、圓潤比例與玩偶質感。"
        case .clay: "手作黏土、柔和光影與立體質感。"
        case .sticker: "俐落外框、簡潔色塊與貼紙質感。"
        }
    }
}

enum LocalHatchRequestState: String, Codable, Equatable {
    case savedLocally
}

private struct LocalHatchCanonicalPayload {
    let requestSchemaVersion: Int
    let clientRequestID: String
    let petID: String
    let petPreset: String
    let targetStage: String
    let basePackageID: String
    let baseVersion: Int
    let expectedNextVersion: Int
    let appearance: String
    let avoid: String?
    let visualStyle: String
}

private enum LocalHatchCanonicalJSONValue {
    case integer(Int)
    case string(String)

    var serialized: String {
        switch self {
        case let .integer(value): String(value)
        case let .string(value): canonicalJSONString(value)
        }
    }
}

private func canonicalJSONString(_ value: String) -> String {
    var result = "\""
    for scalar in value.unicodeScalars {
        switch scalar.value {
        case 0x08: result += "\\b"
        case 0x09: result += "\\t"
        case 0x0A: result += "\\n"
        case 0x0C: result += "\\f"
        case 0x0D: result += "\\r"
        case 0x22: result += "\\\""
        case 0x5C: result += "\\\\"
        case 0x00...0x1F: result += String(format: "\\u%04x", scalar.value)
        default: result.unicodeScalars.append(scalar)
        }
    }
    result += "\""
    return result
}

private extension LocalHatchCanonicalPayload {
    var data: Data {
        var fields: [(key: String, value: LocalHatchCanonicalJSONValue)] = [
            ("request_schema_version", .integer(requestSchemaVersion)),
            ("client_request_id", .string(clientRequestID)),
            ("pet_id", .string(petID)),
            ("pet_preset", .string(petPreset)),
            ("target_stage", .string(targetStage)),
            ("base_package_id", .string(basePackageID)),
            ("base_version", .integer(baseVersion)),
            ("expected_next_version", .integer(expectedNextVersion)),
            ("appearance", .string(appearance)),
            ("visual_style", .string(visualStyle))
        ]
        if let avoid {
            fields.append(("avoid", .string(avoid)))
        }
        let object = fields
            .sorted { $0.key < $1.key }
            .map { "\(canonicalJSONString($0.key)):\($0.value.serialized)" }
            .joined(separator: ",")
        return Data("{\(object)}".utf8)
    }
}

struct LocalHatchRequest: Identifiable, Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let clientRequestID: UUID
    let petID: UUID
    let petPreset: PetPreset
    let targetStage: PetStage
    let basePackageID: UUID
    let baseVersion: Int
    let expectedNextVersion: Int
    let appearance: String
    let avoid: String?
    let stylePreset: HatchStylePreset
    let state: LocalHatchRequestState
    let canonicalDigest: String
    let createdAt: Date
    let updatedAt: Date

    var id: UUID { clientRequestID }

    init(
        schemaVersion: Int = currentSchemaVersion,
        clientRequestID: UUID = UUID(),
        petID: UUID,
        petPreset: PetPreset,
        targetStage: PetStage,
        basePackageID: UUID,
        baseVersion: Int,
        expectedNextVersion: Int,
        appearance: String,
        avoid: String?,
        stylePreset: HatchStylePreset,
        state: LocalHatchRequestState = .savedLocally,
        canonicalDigest: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.clientRequestID = clientRequestID
        self.petID = petID
        self.petPreset = petPreset
        self.targetStage = targetStage
        self.basePackageID = basePackageID
        self.baseVersion = baseVersion
        self.expectedNextVersion = expectedNextVersion
        self.appearance = appearance
        self.avoid = avoid
        self.stylePreset = stylePreset
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.canonicalDigest = canonicalDigest ?? Self.digest(
            schemaVersion: schemaVersion,
            clientRequestID: clientRequestID,
            petID: petID,
            petPreset: petPreset,
            targetStage: targetStage,
            basePackageID: basePackageID,
            baseVersion: baseVersion,
            expectedNextVersion: expectedNextVersion,
            appearance: appearance,
            avoid: avoid,
            stylePreset: stylePreset
        )
    }

    var isStructurallyValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && state == .savedLocally
            && baseVersion > 0
            && nextVersionIsValid
            && appearance == appearance.trimmingCharacters(in: .whitespacesAndNewlines)
            && (4...280).contains(appearance.count)
            && avoidIsStructurallyValid
            && updatedAt >= createdAt
            && canonicalDigest.count == 64
            && canonicalDigest.allSatisfy { $0.isHexDigit }
            && canonicalDigest == canonicalDigest.lowercased()
            && canonicalDigest == recomputedCanonicalDigest
    }

    private var nextVersionIsValid: Bool {
        let (nextVersion, overflow) = baseVersion.addingReportingOverflow(1)
        return !overflow && expectedNextVersion == nextVersion
    }

    var recomputedCanonicalDigest: String {
        Self.digest(
            schemaVersion: schemaVersion,
            clientRequestID: clientRequestID,
            petID: petID,
            petPreset: petPreset,
            targetStage: targetStage,
            basePackageID: basePackageID,
            baseVersion: baseVersion,
            expectedNextVersion: expectedNextVersion,
            appearance: appearance,
            avoid: avoid,
            stylePreset: stylePreset
        )
    }

    var canonicalPayloadData: Data {
        Self.canonicalPayloadData(
            schemaVersion: schemaVersion,
            clientRequestID: clientRequestID,
            petID: petID,
            petPreset: petPreset,
            targetStage: targetStage,
            basePackageID: basePackageID,
            baseVersion: baseVersion,
            expectedNextVersion: expectedNextVersion,
            appearance: appearance,
            avoid: avoid,
            stylePreset: stylePreset
        )
    }

    private var avoidIsStructurallyValid: Bool {
        guard let avoid else { return true }
        return !avoid.isEmpty
            && avoid.count <= 160
            && avoid == avoid.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func digest(
        schemaVersion: Int,
        clientRequestID: UUID,
        petID: UUID,
        petPreset: PetPreset,
        targetStage: PetStage,
        basePackageID: UUID,
        baseVersion: Int,
        expectedNextVersion: Int,
        appearance: String,
        avoid: String?,
        stylePreset: HatchStylePreset
    ) -> String {
        let data = canonicalPayloadData(
            schemaVersion: schemaVersion,
            clientRequestID: clientRequestID,
            petID: petID,
            petPreset: petPreset,
            targetStage: targetStage,
            basePackageID: basePackageID,
            baseVersion: baseVersion,
            expectedNextVersion: expectedNextVersion,
            appearance: appearance,
            avoid: avoid,
            stylePreset: stylePreset
        )
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalPayloadData(
        schemaVersion: Int,
        clientRequestID: UUID,
        petID: UUID,
        petPreset: PetPreset,
        targetStage: PetStage,
        basePackageID: UUID,
        baseVersion: Int,
        expectedNextVersion: Int,
        appearance: String,
        avoid: String?,
        stylePreset: HatchStylePreset
    ) -> Data {
        let payload = LocalHatchCanonicalPayload(
            requestSchemaVersion: schemaVersion,
            clientRequestID: clientRequestID.uuidString.lowercased(),
            petID: petID.uuidString.lowercased(),
            petPreset: petPreset.rawValue,
            targetStage: targetStage.wireName,
            basePackageID: basePackageID.uuidString.lowercased(),
            baseVersion: baseVersion,
            expectedNextVersion: expectedNextVersion,
            appearance: appearance,
            avoid: avoid,
            visualStyle: stylePreset.rawValue
        )
        return payload.data
    }
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
    var preset: PetPreset?
    var archetype: PetArchetype
    var growth: PetGrowth
    var activePackage: HatchPackageReference
    var pendingHatchJob: HatchJob?
    var pendingHatchRequest: LocalHatchRequest?

    static var initial: PetProfile {
        PetProfile(
            id: UUID(),
            name: PetPreset.sprout.defaultName,
            preset: .sprout,
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
            pendingHatchJob: nil,
            pendingHatchRequest: nil
        )
    }

    var resolvedPreset: PetPreset {
        preset ?? .resolving(archetype)
    }

    var presetStateIsConsistent: Bool {
        guard let preset else { return true }
        return preset.archetype == archetype
    }

    var localHatchStateIsConsistent: Bool {
        guard let request = pendingHatchRequest else { return true }
        return pendingHatchJob == nil
            && request.petID == id
            && request.isStructurallyValid
    }

    var localHatchRequestIsCurrent: Bool {
        guard let request = pendingHatchRequest else { return true }
        let (expectedNextVersion, overflow) = activePackage.version.addingReportingOverflow(1)
        return localHatchStateIsConsistent
            && !overflow
            && request.petPreset == resolvedPreset
            && request.targetStage == growth.stage
            && request.basePackageID == activePackage.id
            && request.baseVersion == activePackage.version
            && request.expectedNextVersion == expectedNextVersion
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
