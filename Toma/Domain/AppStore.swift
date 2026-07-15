import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot: AppSnapshot
    @Published private(set) var activity: PetActivity
    @Published var errorBanner: String?

    private let snapshotStore: any SnapshotPersisting
    private let gateway: any AgentGateway
    private let reminders: any ReminderScheduling
    private let now: () -> Date

    init(
        snapshotStore: any SnapshotPersisting = JSONSnapshotStore(),
        gateway: any AgentGateway = DemoAgentGateway(),
        reminders: any ReminderScheduling = LocalReminderScheduler(),
        now: @escaping () -> Date = Date.init
    ) {
        self.snapshotStore = snapshotStore
        self.gateway = gateway
        self.reminders = reminders
        self.now = now

        let initialSnapshot: AppSnapshot
        let initialError: String?
        do {
            let loaded = try snapshotStore.load() ?? .initial
            guard loaded.schemaVersion == 2,
                  loaded.growthLedgerIsConsistent,
                  loaded.petProfile.presetStateIsConsistent,
                  loaded.petProfile.localHatchStateIsConsistent else {
                throw ValidationError.invalidSnapshot
            }
            initialSnapshot = loaded
            initialError = nil
        } catch {
            initialSnapshot = .initial
            initialError = "本機記錄損毀，已安全地重新開始。"
        }
        self.snapshot = initialSnapshot
        self.errorBanner = initialError
        self.activity = initialSnapshot.pendingPlan == nil ? .idle : .waitingForApproval
        recoverInterruptedExecutionIfNeeded()
        recoverPendingNotificationCleanupIfNeeded()
    }

    var latestReceipt: TaskReceipt? { snapshot.receipts.last }
    var stage: PetStage { snapshot.petProfile.growth.stage }

    func clearError() {
        errorBanner = nil
    }

    func setListening(_ isListening: Bool) {
        if isListening {
            activity = .listening
        } else if snapshot.pendingPlan != nil {
            activity = .waitingForApproval
        } else {
            activity = .idle
        }
    }

    func selectProvider(_ provider: ModelProvider) {
        var candidate = snapshot
        candidate.selectedProvider = provider
        _ = commit(candidate, failureMessage: "無法保存模型選擇。")
    }

    func updatePetProfile(name rawName: String, preset: PetPreset) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 20 else {
            errorBanner = "寵物名字請控制在 1 到 20 個字。"
            return false
        }

        var candidate = snapshot
        candidate.petProfile.name = name
        candidate.petProfile.preset = preset
        candidate.petProfile.archetype = preset.archetype
        return commit(candidate, failureMessage: "寵物設定沒有保存。")
    }

    func reviewLocalHatchRequest(
        appearance rawAppearance: String,
        avoid rawAvoid: String?,
        stylePreset: HatchStylePreset,
        replacing requestID: UUID? = nil
    ) -> LocalHatchReview? {
        guard localHatchSlotIsAvailable(replacing: requestID),
              let input = normalizedLocalHatchInput(
                  appearance: rawAppearance,
                  avoid: rawAvoid
              ) else {
            return nil
        }
        return makeLocalHatchReview(
            appearance: input.appearance,
            avoid: input.avoid,
            stylePreset: stylePreset
        )
    }

    func saveLocalHatchReview(
        _ review: LocalHatchReview,
        replacing requestID: UUID? = nil
    ) -> Bool {
        guard localHatchSlotIsAvailable(replacing: requestID) else { return false }
        guard review.isStructurallyValid else {
            errorBanner = "Hatch 設計單內容不完整，請返回重新檢查。"
            return false
        }
        guard localHatchReviewIsCurrent(review) else {
            errorBanner = "Pet 身份、成長階段或外觀版本已改變；請重新檢查設計單。"
            return false
        }

        let existingRequest = requestID.flatMap { id in
            snapshot.petProfile.pendingHatchRequest.flatMap {
                $0.clientRequestID == id ? $0 : nil
            }
        }
        let timestamp = now()
        let createdAt = existingRequest?.createdAt ?? timestamp
        let request = LocalHatchRequest(
            schemaVersion: review.schemaVersion,
            petID: review.petID,
            petPreset: review.petPreset,
            targetStage: review.targetStage,
            basePackageID: review.basePackageID,
            baseVersion: review.baseVersion,
            expectedNextVersion: review.expectedNextVersion,
            appearance: review.appearance,
            avoid: review.avoid,
            stylePreset: review.stylePreset,
            createdAt: createdAt,
            updatedAt: max(timestamp, createdAt)
        )

        var candidate = snapshot
        candidate.petProfile.pendingHatchRequest = request
        return commit(
            candidate,
            failureMessage: requestID == nil
                ? "孵化請求沒有保存在本機。"
                : "孵化請求的編輯沒有保存。"
        )
    }

    func deleteLocalHatchRequest() -> Bool {
        guard snapshot.petProfile.pendingHatchRequest != nil else {
            errorBanner = "目前沒有保存在本機的孵化請求。"
            return false
        }

        var candidate = snapshot
        candidate.petProfile.pendingHatchRequest = nil
        return commit(candidate, failureMessage: "本機孵化請求沒有刪除。")
    }

    func send(_ rawMessage: String) async {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 1_000 else {
            errorBanner = "請輸入 1 到 1000 個字。"
            return
        }

        var candidate = snapshot
        candidate.messages.append(ChatMessage(role: .user, text: message, createdAt: now()))
        guard commit(candidate, failureMessage: "訊息沒有保存，尚未送出。") else { return }

        activity = .working
        let provider = snapshot.selectedProvider
        let memories = enabledMemories
        do {
            let response = try await gateway.reply(
                to: message,
                provider: provider,
                memories: memories
            )
            guard enabledMemories == memories else {
                errorBanner = "記憶設定已改變，這次回覆沒有保存。"
                activity = .failed
                return
            }
            let safeResponse = try validateReply(response)
            candidate = snapshot
            candidate.messages.append(ChatMessage(role: .pet, text: safeResponse, createdAt: now()))
            if commit(candidate, failureMessage: "回覆產生了，但沒有保存。") {
                activity = .idle
            } else {
                activity = .failed
            }
        } catch {
            errorBanner = "示範 Agent 沒有產生可用回覆。"
            activity = .failed
        }
    }

    func prepareTomorrow() async {
        guard snapshot.inFlightExecution == nil else { return }
        guard snapshot.pendingPlan == nil else {
            errorBanner = "目前已有一份待確認草稿。"
            return
        }
        guard snapshot.approvedPlan == nil else {
            errorBanner = "請先復原目前的明日計畫，再建立新草稿。"
            return
        }

        activity = .working
        let provider = snapshot.selectedProvider
        let memories = enabledMemories
        do {
            let output = try await gateway.prepareTomorrow(
                provider: provider,
                memories: memories,
                now: now()
            )
            guard enabledMemories == memories else {
                errorBanner = "記憶設定已改變，這次草稿沒有保存。"
                activity = .failed
                return
            }
            let draft = try validateDraft(output)
            var candidate = snapshot
            candidate.pendingPlan = draft
            if commit(candidate, failureMessage: "草稿沒有保存，沒有執行任何動作。") {
                activity = .waitingForApproval
            } else {
                activity = .failed
            }
        } catch {
            errorBanner = "Agent 回傳的明日計畫不符合安全格式。"
            activity = .failed
        }
    }

    func updateDraftTitle(_ title: String) {
        editDraft { $0.title = String(title.prefix(80)) }
    }

    func updateDraftItem(id: UUID, text: String) {
        editDraft { plan in
            guard let index = plan.items.firstIndex(where: { $0.id == id }) else { return }
            plan.items[index].text = String(text.prefix(160))
        }
    }

    func setDraftItemEnabled(id: UUID, enabled: Bool) {
        editDraft { plan in
            guard let index = plan.items.firstIndex(where: { $0.id == id }) else { return }
            plan.items[index].isEnabled = enabled
        }
    }

    func setDraftReminderEnabled(_ enabled: Bool) {
        editDraft { $0.reminderEnabled = enabled }
    }

    func discardDraft() {
        guard snapshot.inFlightExecution == nil else { return }
        var candidate = snapshot
        candidate.pendingPlan = nil
        if commit(candidate, failureMessage: "無法移除草稿。") {
            activity = .idle
        }
    }

    func approvePendingPlan() async {
        guard snapshot.inFlightExecution == nil,
              snapshot.approvedPlan == nil,
              let pending = snapshot.pendingPlan,
              let plan = try? validateDraft(pending) else {
            errorBanner = "這份草稿已變更或無法批准，請重新檢查。"
            return
        }

        let operationID = UUID()
        let digest = plan.approvalDigest
        let notificationID = plan.reminderEnabled ? "toma.plan.\(plan.id.uuidString)" : nil
        let journal = InFlightExecution(
            operationID: operationID,
            petID: snapshot.petProfile.id,
            planID: plan.id,
            planVersion: plan.version,
            planDigest: digest,
            notificationIdentifier: notificationID,
            preparedAt: now()
        )

        var preparedSnapshot = snapshot
        preparedSnapshot.inFlightExecution = journal
        guard commit(preparedSnapshot, failureMessage: "批准尚未開始，沒有執行任何動作。") else {
            activity = .failed
            return
        }

        activity = .working
        var reminderWasScheduled = false
        if let notificationID {
            let authorized = await reminders.requestAuthorization()
            guard executionIsCurrent(journal) else {
                await cancelStaleExecution(journal, notificationID: notificationID)
                return
            }
            if authorized {
                do {
                    try await reminders.scheduleTomorrowMorning(for: plan, identifier: notificationID)
                    guard executionIsCurrent(journal) else {
                        await cancelStaleExecution(journal, notificationID: notificationID)
                        return
                    }
                    reminderWasScheduled = await reminders.isPending(identifier: notificationID)
                    guard executionIsCurrent(journal) else {
                        await cancelStaleExecution(journal, notificationID: notificationID)
                        return
                    }
                } catch {
                    reminderWasScheduled = false
                }
            }
        }

        guard executionIsCurrent(journal) else {
            await cancelStaleExecution(journal, notificationID: notificationID)
            return
        }

        let executionVerified = notificationID == nil || reminderWasScheduled
        let receiptStatus: ReceiptStatus = executionVerified ? .verified : .partial
        let xpAwarded = executionVerified ? 20 : 0

        var approvedPlan = plan
        approvedPlan.status = .approved
        approvedPlan.approvedContentDigest = digest
        var finalSnapshot = snapshot
        finalSnapshot.pendingPlan = nil
        finalSnapshot.approvedPlan = approvedPlan
        finalSnapshot.inFlightExecution = nil
        let receipt = TaskReceipt(
            id: operationID,
            petID: journal.petID,
            planID: plan.id,
            planVersion: plan.version,
            planDigest: digest,
            status: receiptStatus,
            summary: executionVerified
                ? "計畫已保存，執行結果已讀回確認。"
                : "計畫已保存，但早晨提醒未完成。",
            createdAt: now(),
            notificationIdentifier: reminderWasScheduled ? notificationID : nil,
            xpAwarded: xpAwarded,
            observedEffects: plan.items.filter(\.isEnabled).map(\.text),
            canUndo: true
        )
        finalSnapshot.receipts.append(receipt)
        _ = finalSnapshot.petProfile.applyVerifiedReceipt(receipt)

        if commit(finalSnapshot, failureMessage: "執行結果無法保存，已清理提醒。") {
            activity = executionVerified ? .celebrating : .failed
        } else {
            if let notificationID { reminders.cancel(identifier: notificationID) }
            recoverInterruptedExecutionIfNeeded()
        }
    }

    func undoLatestExecution() async {
        guard let receiptIndex = snapshot.receipts.lastIndex(where: \.canUndo),
              snapshot.receipts[receiptIndex].status != .reverted else { return }

        let receipt = snapshot.receipts[receiptIndex]
        guard snapshot.petProfile.id == receipt.petID,
              snapshot.approvedPlan?.id == receipt.planID,
              snapshot.approvedPlan?.version == receipt.planVersion,
              snapshot.approvedPlan?.approvalDigest == receipt.planDigest else {
            errorBanner = "目前狀態已改變，不能用舊收據覆蓋新計畫。"
            return
        }

        var canClaimFullReminderUndo = true
        if let notificationID = receipt.notificationIdentifier {
            let wasPending = await reminders.isPending(identifier: notificationID)
            let wasDelivered = await reminders.isDelivered(identifier: notificationID)
            reminders.cancel(identifier: notificationID)
            let stillPending = await reminders.isPending(identifier: notificationID)
            if stillPending {
                var partial = snapshot
                partial.receipts[receiptIndex].summary = "復原嘗試失敗：提醒尚未撤銷，原計畫與已驗證執行保持不變。"
                _ = commit(partial, failureMessage: "撤銷狀態無法保存。")
                errorBanner = "提醒尚未撤銷；原計畫、收據與成長保持不變，可以稍後再試。"
                activity = .failed
                return
            }
            canClaimFullReminderUndo = wasPending && !wasDelivered
        }

        var candidate = snapshot
        candidate.approvedPlan = nil
        _ = candidate.petProfile.revokeGrowth(for: receipt.id, at: now())
        candidate.receipts[receiptIndex].status = canClaimFullReminderUndo ? .reverted : .partial
        candidate.receipts[receiptIndex].summary = canClaimFullReminderUndo
            ? "計畫、提醒與本次成長值都已復原。"
            : "計畫與本次成長值已復原；提醒可能已經送達，無法聲稱已撤回。"
        candidate.receipts[receiptIndex].canUndo = false

        if commit(candidate, failureMessage: "復原沒有完整保存，請再試一次。") {
            activity = canClaimFullReminderUndo ? .idle : .failed
        } else {
            activity = .failed
        }
    }

    func finishLatestExecution() {
        guard let receiptIndex = snapshot.receipts.lastIndex(where: \.canUndo),
              snapshot.receipts[receiptIndex].notificationIdentifier == nil else {
            errorBanner = "仍有提醒綁定這次任務；請先保留或復原提醒。"
            return
        }

        let receipt = snapshot.receipts[receiptIndex]
        guard snapshot.petProfile.id == receipt.petID,
              snapshot.approvedPlan?.id == receipt.planID,
              snapshot.approvedPlan?.version == receipt.planVersion,
              snapshot.approvedPlan?.approvalDigest == receipt.planDigest else {
            errorBanner = "目前狀態已改變，不能封存這張舊收據。"
            return
        }

        var candidate = snapshot
        candidate.approvedPlan = nil
        candidate.receipts[receiptIndex].canUndo = false
        candidate.receipts[receiptIndex].summary += " 任務已由使用者封存。"
        if commit(candidate, failureMessage: "任務沒有封存，仍可復原。") {
            activity = .idle
        }
    }

    func addMemory(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 200 else {
            errorBanner = "記憶請控制在 1 到 200 個字。"
            return
        }
        var candidate = snapshot
        candidate.memories.append(MemoryEntry(text: text, createdAt: now()))
        _ = commit(candidate, failureMessage: "這則記憶沒有保存。")
    }

    func deleteMemory(id: UUID) async {
        guard let memory = snapshot.memories.first(where: { $0.id == id }) else { return }
        let journal = snapshot.inFlightExecution
        let deferredCleanupIDs = Set([journal?.notificationIdentifier].compactMap { $0 })
        let approvedPlanBeforeRedaction = snapshot.approvedPlan
        let approvedPlanUsedMemory = approvedPlanBeforeRedaction.map {
            contains(memory.text, in: $0)
        } ?? false
        var notificationIDsToCancel = Set<String>()
        if let notificationID = journal?.notificationIdentifier {
            notificationIDsToCancel.insert(notificationID)
        }

        var candidate = snapshot
        candidate.memories.removeAll { $0.id == id }
        candidate.messages = candidate.messages.map { message in
            guard message.role == .pet else { return message }
            return ChatMessage(
                id: message.id,
                role: message.role,
                text: redacting(memory.text, from: message.text),
                createdAt: message.createdAt
            )
        }
        candidate.pendingPlan = candidate.pendingPlan.map {
            redacting(memory.text, from: $0, incrementDraftVersion: true)
        }
        candidate.approvedPlan = candidate.approvedPlan.map {
            redacting(memory.text, from: $0, incrementDraftVersion: false)
        }
        candidate.receipts = candidate.receipts.map { receipt in
            var receipt = receipt
            receipt.summary = redacting(memory.text, from: receipt.summary)
            receipt.observedEffects = receipt.observedEffects.map {
                redacting(memory.text, from: $0)
            }
            return receipt
        }

        if approvedPlanUsedMemory, let approvedPlanBeforeRedaction {
            for index in candidate.receipts.indices
            where candidate.receipts[index].planID == approvedPlanBeforeRedaction.id
                && candidate.receipts[index].planVersion == approvedPlanBeforeRedaction.version
                && candidate.receipts[index].planDigest == approvedPlanBeforeRedaction.approvalDigest {
                if let notificationID = candidate.receipts[index].notificationIdentifier {
                    notificationIDsToCancel.insert(notificationID)
                    if candidate.receipts[index].status == .verified {
                        _ = candidate.petProfile.revokeGrowth(
                            for: candidate.receipts[index].id,
                            at: now()
                        )
                    }
                    candidate.receipts[index].status = .partial
                    candidate.receipts[index].summary = "記憶已刪除；正在確認相關提醒已清理。"
                }
            }
        }

        if let journal {
            candidate.pendingPlan = nil
            candidate.inFlightExecution = nil
            candidate.receipts.append(
                TaskReceipt(
                    id: journal.operationID,
                    petID: journal.petID,
                    planID: journal.planID,
                    planVersion: journal.planVersion,
                    planDigest: journal.planDigest,
                    status: .failed,
                    summary: "批准因記憶刪除而取消；正在確認可能的提醒已清理。",
                    createdAt: now(),
                    notificationIdentifier: nil,
                    xpAwarded: 0,
                    canUndo: false
                )
            )
        }

        candidate.pendingNotificationCleanupIDs.formUnion(notificationIDsToCancel)

        guard commit(candidate, failureMessage: "這則記憶沒有刪除。") else { return }
        var unclearedNotificationIDs = Set<String>()
        for notificationID in notificationIDsToCancel {
            reminders.cancel(identifier: notificationID)
            let isPending = await reminders.isPending(identifier: notificationID)
            let isDelivered = await reminders.isDelivered(identifier: notificationID)
            if isPending || isDelivered {
                unclearedNotificationIDs.insert(notificationID)
            }
        }
        let remindersWereCleared = unclearedNotificationIDs.isEmpty

        var verified = snapshot
        verified.pendingNotificationCleanupIDs.subtract(
            notificationIDsToCancel.subtracting(deferredCleanupIDs)
        )
        verified.pendingNotificationCleanupIDs.formUnion(unclearedNotificationIDs)
        if approvedPlanUsedMemory, let approvedPlanBeforeRedaction {
            for index in verified.receipts.indices
            where verified.receipts[index].planID == approvedPlanBeforeRedaction.id
                && verified.receipts[index].planVersion == approvedPlanBeforeRedaction.version
                && verified.receipts[index].planDigest == approvedPlanBeforeRedaction.approvalDigest
                && verified.receipts[index].notificationIdentifier != nil {
                verified.receipts[index].summary = remindersWereCleared
                    ? "記憶已刪除；為避免保留舊內容，相關提醒已取消並讀回確認。"
                    : "記憶已刪除，但相關提醒未能撤銷；請在通知中心手動清除。"
            }
        }
        if let journal,
           let receiptIndex = verified.receipts.firstIndex(where: { $0.id == journal.operationID }) {
            if !deferredCleanupIDs.isEmpty {
                verified.receipts[receiptIndex].summary = "批准因記憶刪除而取消；等待原排程返回後再次確認提醒清理。"
            } else {
                verified.receipts[receiptIndex].summary = remindersWereCleared
                    ? "批准因記憶刪除而取消；可能的提醒已清理並讀回確認。"
                    : "批准已取消，但可能的提醒未能撤銷；請在通知中心手動清除。"
            }
        }
        _ = commit(verified, failureMessage: "記憶已刪除，但提醒清理結果沒有保存。")
        activity = remindersWereCleared && journal == nil
            ? (verified.pendingPlan == nil ? .idle : .waitingForApproval)
            : .failed
    }

    func setMemoryEnabled(id: UUID, enabled: Bool) {
        var candidate = snapshot
        guard let index = candidate.memories.firstIndex(where: { $0.id == id }) else { return }
        candidate.memories[index].isEnabledForAgent = enabled
        _ = commit(candidate, failureMessage: "記憶權限沒有保存。")
    }

    func continuePendingTask() {
        if snapshot.pendingPlan != nil {
            activity = .waitingForApproval
        } else {
            errorBanner = "目前沒有待確認任務。"
        }
    }

    private func editDraft(_ edit: (inout TomorrowPlan) -> Void) {
        guard snapshot.inFlightExecution == nil, var plan = snapshot.pendingPlan else { return }
        edit(&plan)
        plan.version += 1
        var candidate = snapshot
        candidate.pendingPlan = plan
        _ = commit(candidate, failureMessage: "草稿變更沒有保存。")
    }

    private var enabledMemories: [MemoryEntry] {
        snapshot.memories.filter(\.isEnabledForAgent)
    }

    private func normalizedLocalHatchInput(
        appearance rawAppearance: String,
        avoid rawAvoid: String?
    ) -> (appearance: String, avoid: String?)? {
        let appearance = rawAppearance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (4...280).contains(appearance.count) else {
            errorBanner = "外觀描述請控制在 4 到 280 個字。"
            return nil
        }

        let trimmedAvoid = rawAvoid?.trimmingCharacters(in: .whitespacesAndNewlines)
        let avoid = trimmedAvoid?.isEmpty == true ? nil : trimmedAvoid
        guard (avoid?.count ?? 0) <= 160 else {
            errorBanner = "避免項目請控制在 160 個字內。"
            return nil
        }
        return (appearance, avoid)
    }

    private func makeLocalHatchReview(
        appearance: String,
        avoid: String?,
        stylePreset: HatchStylePreset
    ) -> LocalHatchReview? {
        let activePackage = snapshot.petProfile.activePackage
        let (expectedNextVersion, overflow) = activePackage.version.addingReportingOverflow(1)
        guard !overflow else {
            errorBanner = "目前外觀版本無法建立下一版請求。"
            return nil
        }

        return LocalHatchReview(
            schemaVersion: LocalHatchRequest.currentSchemaVersion,
            petID: snapshot.petProfile.id,
            petPreset: snapshot.petProfile.resolvedPreset,
            targetStage: snapshot.petProfile.growth.stage,
            basePackageID: activePackage.id,
            baseVersion: activePackage.version,
            expectedNextVersion: expectedNextVersion,
            appearance: appearance,
            avoid: avoid,
            stylePreset: stylePreset
        )
    }

    private func localHatchSlotIsAvailable(replacing requestID: UUID?) -> Bool {
        if let requestID {
            guard let request = snapshot.petProfile.pendingHatchRequest else {
                errorBanner = "目前沒有可編輯的本機孵化請求。"
                return false
            }
            guard request.clientRequestID == requestID else {
                errorBanner = "本機孵化請求已改變；請重新開啟後再編輯。"
                return false
            }
        } else if snapshot.petProfile.pendingHatchRequest != nil {
            errorBanner = "已有一份保存在本機的孵化請求；請編輯或刪除它。"
            return false
        }

        guard snapshot.petProfile.pendingHatchJob == nil else {
            errorBanner = requestID == nil
                ? "已有進行中的 Hatch 工作，不能建立新的本機請求。"
                : "Hatch 工作已開始，不能覆蓋原本的本機請求。"
            return false
        }
        return true
    }

    private func localHatchReviewIsCurrent(_ review: LocalHatchReview) -> Bool {
        let profile = snapshot.petProfile
        return review.petID == profile.id
            && review.petPreset == profile.resolvedPreset
            && review.targetStage == profile.growth.stage
            && review.basePackageID == profile.activePackage.id
            && review.baseVersion == profile.activePackage.version
    }

    private func validateReply(_ reply: String) throws -> String {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2_000 else { throw ValidationError.invalidReply }
        return trimmed
    }

    private func validateDraft(_ output: TomorrowPlan) throws -> TomorrowPlan {
        var draft = output
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.items = draft.items.map { item in
            var item = item
            item.text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return item
        }

        guard draft.status == .draft,
              draft.approvedContentDigest == nil,
              draft.version >= 1,
              !draft.title.isEmpty,
              draft.title.count <= 80,
              (1...8).contains(draft.items.count),
              draft.items.allSatisfy({ !$0.text.isEmpty && $0.text.count <= 160 }),
              Set(draft.items.map(\.id)).count == draft.items.count,
              draft.items.contains(where: \.isEnabled),
              snapshot.approvedPlan?.id != draft.id,
              !snapshot.receipts.contains(where: { $0.planID == draft.id }),
              abs(draft.createdAt.timeIntervalSince(now())) <= 10 * 60 else {
            throw ValidationError.invalidDraft
        }
        return draft
    }

    private func redacting(_ sensitiveText: String, from text: String) -> String {
        text.replacingOccurrences(of: sensitiveText, with: "（已刪除的記憶）")
    }

    private func contains(_ sensitiveText: String, in plan: TomorrowPlan) -> Bool {
        plan.title.contains(sensitiveText)
            || plan.items.contains { $0.text.contains(sensitiveText) }
    }

    private func redacting(
        _ sensitiveText: String,
        from source: TomorrowPlan,
        incrementDraftVersion: Bool
    ) -> TomorrowPlan {
        var plan = source
        let originalDigest = plan.approvalDigest
        let title = redacting(sensitiveText, from: plan.title)
        let items = plan.items.map { item in
            var item = item
            item.text = redacting(sensitiveText, from: item.text)
            return item
        }
        guard title != plan.title || items != plan.items else { return plan }

        plan.title = title
        plan.items = items
        if incrementDraftVersion {
            plan.version += 1
        } else {
            plan.approvedContentDigest = originalDigest
        }
        return plan
    }

    private func executionIsCurrent(_ journal: InFlightExecution) -> Bool {
        guard snapshot.inFlightExecution == journal,
              snapshot.petProfile.id == journal.petID,
              let pending = snapshot.pendingPlan else { return false }
        return pending.id == journal.planID
            && pending.version == journal.planVersion
            && pending.approvalDigest == journal.planDigest
    }

    private func cancelStaleExecution(
        _ journal: InFlightExecution,
        notificationID: String?
    ) async {
        var reminderWasCleared = true
        if let notificationID {
            var journaled = snapshot
            journaled.pendingNotificationCleanupIDs.insert(notificationID)
            guard commit(journaled, failureMessage: "提醒清理日誌沒有保存。") else {
                reminders.cancel(identifier: notificationID)
                activity = .failed
                return
            }

            reminders.cancel(identifier: notificationID)
            let isPending = await reminders.isPending(identifier: notificationID)
            let isDelivered = await reminders.isDelivered(identifier: notificationID)
            reminderWasCleared = !isPending && !isDelivered
        }
        var candidate = snapshot
        if let notificationID, reminderWasCleared {
            candidate.pendingNotificationCleanupIDs.remove(notificationID)
        }
        if let receiptIndex = candidate.receipts.firstIndex(where: { $0.id == journal.operationID }) {
            candidate.receipts[receiptIndex].summary = reminderWasCleared
                ? "批准因記憶刪除而取消；可能的提醒已清理並讀回確認。"
                : "批准已取消，但可能的提醒未能撤銷；請在通知中心手動清除。"
        }
        _ = commit(candidate, failureMessage: "提醒清理結果沒有保存。")
        activity = snapshot.pendingPlan == nil ? .failed : .waitingForApproval
    }

    @discardableResult
    private func commit(_ candidate: AppSnapshot, failureMessage: String) -> Bool {
        guard candidate.schemaVersion == 2,
              candidate.growthLedgerIsConsistent,
              candidate.petProfile.presetStateIsConsistent,
              candidate.petProfile.localHatchStateIsConsistent else {
            errorBanner = "本機狀態不一致，這次變更沒有保存。"
            return false
        }
        do {
            try snapshotStore.save(candidate)
            guard try snapshotStore.load() == candidate else {
                errorBanner = failureMessage
                return false
            }
            snapshot = candidate
            return true
        } catch {
            errorBanner = failureMessage
            return false
        }
    }

    private func recoverInterruptedExecutionIfNeeded() {
        guard let journal = snapshot.inFlightExecution else { return }

        var recovered = snapshot
        recovered.inFlightExecution = nil
        if let notificationID = journal.notificationIdentifier {
            reminders.cancel(identifier: notificationID)
            recovered.pendingNotificationCleanupIDs.insert(notificationID)
        }
        recovered.receipts.append(
            TaskReceipt(
                id: journal.operationID,
                petID: journal.petID,
                planID: journal.planID,
                planVersion: journal.planVersion,
                planDigest: journal.planDigest,
                status: .failed,
                summary: "上次執行中斷；沒有套用計畫，可能的提醒已排入清理。",
                createdAt: now(),
                notificationIdentifier: nil,
                xpAwarded: 0,
                canUndo: false
            )
        )
        _ = commit(recovered, failureMessage: "中斷復原狀態無法保存。")
        activity = recovered.pendingPlan == nil ? .failed : .waitingForApproval
    }

    private func recoverPendingNotificationCleanupIfNeeded() {
        let notificationIDs = snapshot.pendingNotificationCleanupIDs
        guard !notificationIDs.isEmpty else { return }

        for notificationID in notificationIDs {
            reminders.cancel(identifier: notificationID)
        }
        Task { await verifyRecoveredNotificationCleanup(notificationIDs) }
    }

    private func verifyRecoveredNotificationCleanup(_ notificationIDs: Set<String>) async {
        var unclearedNotificationIDs = Set<String>()
        for notificationID in notificationIDs {
            let isPending = await reminders.isPending(identifier: notificationID)
            let isDelivered = await reminders.isDelivered(identifier: notificationID)
            if isPending || isDelivered {
                unclearedNotificationIDs.insert(notificationID)
            }
        }

        var candidate = snapshot
        candidate.pendingNotificationCleanupIDs.subtract(notificationIDs)
        candidate.pendingNotificationCleanupIDs.formUnion(unclearedNotificationIDs)
        guard commit(candidate, failureMessage: "提醒清理紀錄沒有保存。") else {
            activity = .failed
            return
        }
        if !unclearedNotificationIDs.isEmpty {
            errorBanner = "部分已刪除內容的提醒仍未清理，請稍後再試。"
            activity = .failed
        }
    }

    private enum ValidationError: Error {
        case invalidReply
        case invalidDraft
        case invalidSnapshot
    }
}
