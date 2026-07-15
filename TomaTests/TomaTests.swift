import XCTest
@testable import Toma

@MainActor
final class TomaTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    func testPrepareRequiresApprovalBeforeReminderOrGrowth() async {
        let persistence = MemorySnapshotStore()
        let reminders = ReminderSpy()
        let gateway = GatewayStub(plan: makePlan())
        let store = makeStore(persistence: persistence, gateway: gateway, reminders: reminders)

        await store.prepareTomorrow()

        XCTAssertNotNil(store.snapshot.pendingPlan)
        XCTAssertNil(store.snapshot.approvedPlan)
        XCTAssertEqual(store.snapshot.petXP, 0)
        XCTAssertEqual(reminders.scheduleCount, 0)
        XCTAssertTrue(store.snapshot.receipts.isEmpty)
    }

    func testApprovedPlanIsVersionBoundVerifiedAndUndoable() async {
        let persistence = MemorySnapshotStore()
        let reminders = ReminderSpy()
        let gateway = GatewayStub(plan: makePlan())
        let store = makeStore(persistence: persistence, gateway: gateway, reminders: reminders)

        await store.prepareTomorrow()
        let itemID = try! XCTUnwrap(store.snapshot.pendingPlan?.items.first?.id)
        store.updateDraftItem(id: itemID, text: "先完成最重要的工作")
        let approvedVersion = try! XCTUnwrap(store.snapshot.pendingPlan?.version)

        await store.approvePendingPlan()

        let receipt = try! XCTUnwrap(store.latestReceipt)
        let approved = try! XCTUnwrap(store.snapshot.approvedPlan)
        XCTAssertEqual(receipt.status, .verified)
        XCTAssertEqual(receipt.planVersion, approvedVersion)
        XCTAssertEqual(receipt.planDigest, approved.approvalDigest)
        XCTAssertEqual(store.snapshot.petXP, 20)
        XCTAssertEqual(reminders.scheduleCount, 1)
        XCTAssertTrue(receipt.canUndo)

        await store.undoLatestExecution()

        XCTAssertNil(store.snapshot.approvedPlan)
        XCTAssertEqual(store.snapshot.petXP, 0)
        XCTAssertNotNil(store.snapshot.petProfile.growth.awards.first?.revokedAt)
        XCTAssertEqual(store.latestReceipt?.status, .reverted)
        XCTAssertEqual(store.latestReceipt?.canUndo, false)
        XCTAssertEqual(reminders.pendingIDs.count, 0)
    }

    func testDeniedNotificationProducesPartialReceiptAndNoGrowth() async {
        let persistence = MemorySnapshotStore()
        let reminders = ReminderSpy(isAuthorized: false)
        let store = makeStore(
            persistence: persistence,
            gateway: GatewayStub(plan: makePlan()),
            reminders: reminders
        )

        await store.prepareTomorrow()
        await store.approvePendingPlan()

        XCTAssertEqual(store.latestReceipt?.status, .partial)
        XCTAssertEqual(store.snapshot.petXP, 0)
        XCTAssertNotNil(store.snapshot.approvedPlan)
        XCTAssertEqual(reminders.scheduleCount, 0)
    }

    func testUndoAfterDeliveredReminderIsPartialButRollsBackLocalState() async {
        let persistence = MemorySnapshotStore()
        let reminders = ReminderSpy()
        let store = makeStore(
            persistence: persistence,
            gateway: GatewayStub(plan: makePlan()),
            reminders: reminders
        )

        await store.prepareTomorrow()
        await store.approvePendingPlan()
        let notificationID = try! XCTUnwrap(store.latestReceipt?.notificationIdentifier)
        reminders.pendingIDs.remove(notificationID)
        reminders.deliveredIDs.insert(notificationID)

        await store.undoLatestExecution()

        XCTAssertNil(store.snapshot.approvedPlan)
        XCTAssertEqual(store.snapshot.petXP, 0)
        XCTAssertEqual(store.latestReceipt?.status, .partial)
        XCTAssertEqual(store.latestReceipt?.canUndo, false)
        XCTAssertEqual(
            store.latestReceipt?.summary,
            "計畫與本次成長值已復原；提醒可能已經送達，無法聲稱已撤回。"
        )
    }

    func testUndoDeliveredAndClearedReminderIsPartial() async {
        let reminders = ReminderSpy()
        let store = makeStore(
            persistence: MemorySnapshotStore(),
            gateway: GatewayStub(plan: makePlan()),
            reminders: reminders
        )

        await store.prepareTomorrow()
        await store.approvePendingPlan()
        let notificationID = try! XCTUnwrap(store.latestReceipt?.notificationIdentifier)
        reminders.pendingIDs.remove(notificationID)

        await store.undoLatestExecution()

        XCTAssertNil(store.snapshot.approvedPlan)
        XCTAssertEqual(store.snapshot.petXP, 0)
        XCTAssertEqual(store.latestReceipt?.status, .partial)
        XCTAssertEqual(store.latestReceipt?.canUndo, false)
    }

    func testUndoCancellationFailureKeepsPlanAndAllowsRetry() async {
        let reminders = ReminderSpy()
        let store = makeStore(
            persistence: MemorySnapshotStore(),
            gateway: GatewayStub(plan: makePlan()),
            reminders: reminders
        )

        await store.prepareTomorrow()
        await store.approvePendingPlan()
        reminders.cancelSucceeds = false

        await store.undoLatestExecution()

        XCTAssertNotNil(store.snapshot.approvedPlan)
        XCTAssertEqual(store.snapshot.petXP, 20)
        XCTAssertEqual(store.latestReceipt?.status, .verified)
        XCTAssertEqual(
            store.latestReceipt?.summary,
            "復原嘗試失敗：提醒尚未撤銷，原計畫與已驗證執行保持不變。"
        )
        XCTAssertEqual(store.latestReceipt?.canUndo, true)
        XCTAssertTrue(store.snapshot.growthLedgerIsConsistent)
    }

    func testRepeatedApprovalDoesNotExecuteTwice() async {
        let persistence = MemorySnapshotStore()
        let reminders = ReminderSpy()
        let store = makeStore(
            persistence: persistence,
            gateway: GatewayStub(plan: makePlan()),
            reminders: reminders
        )

        await store.prepareTomorrow()
        await store.approvePendingPlan()
        await store.approvePendingPlan()

        XCTAssertEqual(reminders.scheduleCount, 1)
        XCTAssertEqual(store.snapshot.receipts.count, 1)
        XCTAssertEqual(store.snapshot.petXP, 20)
    }

    func testMalformedGatewayDraftIsRejectedBeforeStateChange() async {
        let badPlan = TomorrowPlan(
            title: "",
            items: [TomorrowPlanItem(text: String(repeating: "x", count: 500))],
            reminderEnabled: true,
            createdAt: fixedNow
        )
        let persistence = MemorySnapshotStore()
        let reminders = ReminderSpy()
        let store = makeStore(
            persistence: persistence,
            gateway: GatewayStub(plan: badPlan),
            reminders: reminders
        )

        await store.prepareTomorrow()

        XCTAssertNil(store.snapshot.pendingPlan)
        XCTAssertNil(store.snapshot.approvedPlan)
        XCTAssertEqual(reminders.scheduleCount, 0)
        XCTAssertEqual(store.activity, .failed)
    }

    func testDuplicateDraftItemIDsAreRejected() async {
        let duplicateID = UUID()
        let badPlan = TomorrowPlan(
            title: "明日準備",
            items: [
                TomorrowPlanItem(id: duplicateID, text: "第一步"),
                TomorrowPlanItem(id: duplicateID, text: "第二步")
            ],
            reminderEnabled: false,
            createdAt: fixedNow
        )
        let reminders = ReminderSpy()
        let store = makeStore(
            persistence: MemorySnapshotStore(),
            gateway: GatewayStub(plan: badPlan),
            reminders: reminders
        )

        await store.prepareTomorrow()

        XCTAssertNil(store.snapshot.pendingPlan)
        XCTAssertEqual(reminders.scheduleCount, 0)
        XCTAssertEqual(store.activity, .failed)
    }

    func testPreviouslyUsedPlanIDIsRejected() async {
        let reusedPlan = makePlan()
        var snapshot = AppSnapshot.initial
        snapshot.receipts = [
            TaskReceipt(
                petID: snapshot.petProfile.id,
                planID: reusedPlan.id,
                planVersion: reusedPlan.version,
                planDigest: reusedPlan.approvalDigest,
                status: .reverted,
                summary: "先前已完成",
                createdAt: fixedNow,
                canUndo: false
            )
        ]
        let store = makeStore(
            persistence: MemorySnapshotStore(initial: snapshot),
            gateway: GatewayStub(plan: reusedPlan)
        )

        await store.prepareTomorrow()

        XCTAssertNil(store.snapshot.pendingPlan)
        XCTAssertEqual(store.snapshot.receipts.count, 1)
        XCTAssertEqual(store.activity, .failed)
    }

    func testInterruptedExecutionIsRecoveredWithoutApplyingPlan() {
        let plan = makePlan()
        let operationID = UUID()
        let notificationID = "toma.plan.\(plan.id.uuidString)"
        var snapshot = AppSnapshot.initial
        snapshot.pendingPlan = plan
        snapshot.inFlightExecution = InFlightExecution(
            operationID: operationID,
            petID: snapshot.petProfile.id,
            planID: plan.id,
            planVersion: plan.version,
            planDigest: plan.approvalDigest,
            notificationIdentifier: notificationID,
            preparedAt: fixedNow
        )

        let persistence = MemorySnapshotStore(initial: snapshot)
        let reminders = ReminderSpy()
        reminders.pendingIDs.insert(notificationID)

        let store = makeStore(
            persistence: persistence,
            gateway: GatewayStub(plan: plan),
            reminders: reminders
        )

        XCTAssertNil(store.snapshot.inFlightExecution)
        XCTAssertNotNil(store.snapshot.pendingPlan)
        XCTAssertNil(store.snapshot.approvedPlan)
        XCTAssertEqual(store.snapshot.petXP, 0)
        XCTAssertEqual(store.latestReceipt?.id, operationID)
        XCTAssertEqual(store.latestReceipt?.status, .failed)
        XCTAssertFalse(reminders.pendingIDs.contains(notificationID))
    }

    func testMemoryPermissionAndDeletionSurviveReload() async {
        let persistence = MemorySnapshotStore()
        var store = makeStore(persistence: persistence)

        store.addMemory("明天先寫提案")
        let memoryID = try! XCTUnwrap(store.snapshot.memories.first?.id)
        store.setMemoryEnabled(id: memoryID, enabled: false)

        store = makeStore(persistence: persistence)
        XCTAssertEqual(store.snapshot.memories.first?.isEnabledForAgent, false)

        await store.deleteMemory(id: memoryID)
        store = makeStore(persistence: persistence)
        XCTAssertTrue(store.snapshot.memories.isEmpty)
    }

    func testMemoryDeletionRedactsDerivedOutputAndPreservesReceiptBinding() async {
        let sensitiveText = "明天先寫秘密提案"
        let memory = MemoryEntry(text: sensitiveText, createdAt: fixedNow)
        var plan = TomorrowPlan(
            title: "\(sensitiveText) 的明日準備",
            items: [TomorrowPlanItem(text: "先處理：\(sensitiveText)")],
            reminderEnabled: false,
            status: .approved,
            createdAt: fixedNow
        )
        let originalDigest = plan.approvalDigest
        plan.approvedContentDigest = originalDigest

        var snapshot = AppSnapshot.initial
        snapshot.messages.append(
            ChatMessage(role: .pet, text: "我記得：\(sensitiveText)", createdAt: fixedNow)
        )
        snapshot.memories = [memory]
        snapshot.approvedPlan = plan
        let receipt = TaskReceipt(
            petID: snapshot.petProfile.id,
            planID: plan.id,
            planVersion: plan.version,
            planDigest: originalDigest,
            status: .verified,
            summary: "計畫已保存",
            createdAt: fixedNow,
            xpAwarded: 20,
            observedEffects: ["先處理：\(sensitiveText)"],
            canUndo: true
        )
        snapshot.receipts = [receipt]
        XCTAssertTrue(snapshot.petProfile.applyVerifiedReceipt(receipt))
        let store = makeStore(persistence: MemorySnapshotStore(initial: snapshot))

        await store.deleteMemory(id: memory.id)

        XCTAssertTrue(store.snapshot.memories.isEmpty)
        XCTAssertFalse(store.snapshot.messages.contains { $0.text.contains(sensitiveText) })
        XCTAssertFalse(store.snapshot.approvedPlan?.title.contains(sensitiveText) == true)
        XCTAssertFalse(store.snapshot.approvedPlan?.items.contains { $0.text.contains(sensitiveText) } == true)
        XCTAssertFalse(store.latestReceipt?.observedEffects.contains { $0.contains(sensitiveText) } == true)
        XCTAssertEqual(store.snapshot.approvedPlan?.approvalDigest, originalDigest)

        await store.undoLatestExecution()
        XCTAssertNil(store.snapshot.approvedPlan)
        XCTAssertEqual(store.latestReceipt?.status, .reverted)
    }

    func testDeletingMemoryCancelsApprovedReminderContainingDerivedText() async {
        let sensitiveText = "秘密提案"
        let memory = MemoryEntry(text: sensitiveText, createdAt: fixedNow)
        let plan = TomorrowPlan(
            title: "明日處理\(sensitiveText)",
            items: [TomorrowPlanItem(text: "先完成\(sensitiveText)")],
            reminderEnabled: true,
            createdAt: fixedNow
        )
        var initial = AppSnapshot.initial
        initial.memories = [memory]
        let reminders = ReminderSpy()
        let store = makeStore(
            persistence: MemorySnapshotStore(initial: initial),
            gateway: GatewayStub(plan: plan),
            reminders: reminders
        )

        await store.prepareTomorrow()
        await store.approvePendingPlan()
        let originalDigest = try! XCTUnwrap(store.snapshot.approvedPlan?.approvalDigest)
        let notificationID = try! XCTUnwrap(store.latestReceipt?.notificationIdentifier)
        XCTAssertTrue(reminders.pendingIDs.contains(notificationID))

        await store.deleteMemory(id: memory.id)

        XCTAssertFalse(reminders.pendingIDs.contains(notificationID))
        XCTAssertFalse(store.snapshot.approvedPlan?.title.contains(sensitiveText) == true)
        XCTAssertEqual(store.snapshot.approvedPlan?.approvalDigest, originalDigest)
        XCTAssertEqual(store.latestReceipt?.status, .partial)
        XCTAssertEqual(store.snapshot.petXP, 0)
        XCTAssertNotNil(store.snapshot.petProfile.growth.awards.first?.revokedAt)
        XCTAssertEqual(
            store.latestReceipt?.summary,
            "記憶已刪除；為避免保留舊內容，相關提醒已取消並讀回確認。"
        )
    }

    func testDeletingMemoryReportsReminderCancellationFailure() async {
        let sensitiveText = "不能留在提醒的內容"
        let memory = MemoryEntry(text: sensitiveText, createdAt: fixedNow)
        let plan = TomorrowPlan(
            title: sensitiveText,
            items: [TomorrowPlanItem(text: sensitiveText)],
            reminderEnabled: true,
            createdAt: fixedNow
        )
        var initial = AppSnapshot.initial
        initial.memories = [memory]
        let reminders = ReminderSpy()
        let store = makeStore(
            persistence: MemorySnapshotStore(initial: initial),
            gateway: GatewayStub(plan: plan),
            reminders: reminders
        )

        await store.prepareTomorrow()
        await store.approvePendingPlan()
        let notificationID = try! XCTUnwrap(store.latestReceipt?.notificationIdentifier)
        reminders.cancelSucceeds = false

        await store.deleteMemory(id: memory.id)

        XCTAssertTrue(reminders.pendingIDs.contains(notificationID))
        XCTAssertEqual(store.latestReceipt?.status, .partial)
        XCTAssertEqual(
            store.latestReceipt?.summary,
            "記憶已刪除，但相關提醒未能撤銷；請在通知中心手動清除。"
        )
        XCTAssertEqual(store.activity, .failed)
    }

    func testMemoryDeletionWhileAwaitingAuthorizationAbortsApproval() async {
        let sensitiveText = "不要保留的行程"
        let memory = MemoryEntry(text: sensitiveText, createdAt: fixedNow)
        let plan = TomorrowPlan(
            title: sensitiveText,
            items: [TomorrowPlanItem(text: sensitiveText)],
            reminderEnabled: true,
            createdAt: fixedNow
        )
        var initial = AppSnapshot.initial
        initial.memories = [memory]
        let reminders = GatedReminderSpy(pausePoint: .authorization)
        let store = makeStore(
            persistence: MemorySnapshotStore(initial: initial),
            gateway: GatewayStub(plan: plan),
            reminders: reminders
        )

        await store.prepareTomorrow()
        let approval = Task { await store.approvePendingPlan() }
        await waitUntil { reminders.authorizationStarted }
        await store.deleteMemory(id: memory.id)
        reminders.resumeAuthorization()
        await approval.value

        XCTAssertEqual(reminders.scheduleCount, 0)
        XCTAssertTrue(reminders.pendingIDs.isEmpty)
        XCTAssertNil(store.snapshot.inFlightExecution)
        XCTAssertNil(store.snapshot.pendingPlan)
        XCTAssertNil(store.snapshot.approvedPlan)
        XCTAssertEqual(store.snapshot.petXP, 0)
        XCTAssertEqual(store.latestReceipt?.status, .failed)
        XCTAssertFalse(store.snapshot.receipts.contains { $0.summary.contains(sensitiveText) })
    }

    func testMemoryDeletionWhileDraftIsGeneratingDiscardsOutput() async {
        let sensitiveText = "不再允許的偏好"
        let memory = MemoryEntry(text: sensitiveText, createdAt: fixedNow)
        let plan = TomorrowPlan(
            title: sensitiveText,
            items: [TomorrowPlanItem(text: sensitiveText)],
            reminderEnabled: false,
            createdAt: fixedNow
        )
        var initial = AppSnapshot.initial
        initial.memories = [memory]
        let gateway = GatedGateway(plan: plan)
        let store = makeStore(
            persistence: MemorySnapshotStore(initial: initial),
            gateway: gateway
        )

        let generation = Task { await store.prepareTomorrow() }
        await waitUntil { gateway.prepareStarted }
        await store.deleteMemory(id: memory.id)
        gateway.resumePrepare()
        await generation.value

        XCTAssertTrue(store.snapshot.memories.isEmpty)
        XCTAssertNil(store.snapshot.pendingPlan)
        XCTAssertNil(store.snapshot.approvedPlan)
        XCTAssertFalse(store.snapshot.messages.contains { $0.text.contains(sensitiveText) })
    }

    func testMemoryDeletionWhileSchedulingCancelsLateNotification() async {
        let sensitiveText = "不要排程的行程"
        let memory = MemoryEntry(text: sensitiveText, createdAt: fixedNow)
        let plan = TomorrowPlan(
            title: sensitiveText,
            items: [TomorrowPlanItem(text: sensitiveText)],
            reminderEnabled: true,
            createdAt: fixedNow
        )
        var initial = AppSnapshot.initial
        initial.memories = [memory]
        let reminders = GatedReminderSpy(pausePoint: .scheduling)
        let store = makeStore(
            persistence: MemorySnapshotStore(initial: initial),
            gateway: GatewayStub(plan: plan),
            reminders: reminders
        )

        await store.prepareTomorrow()
        let approval = Task { await store.approvePendingPlan() }
        await waitUntil { reminders.schedulingStarted }
        await store.deleteMemory(id: memory.id)
        let notificationID = "toma.plan.\(plan.id.uuidString)"
        XCTAssertTrue(store.snapshot.pendingNotificationCleanupIDs.contains(notificationID))
        reminders.resumeScheduling()
        await approval.value

        XCTAssertEqual(reminders.scheduleCount, 1)
        XCTAssertTrue(reminders.pendingIDs.isEmpty)
        XCTAssertNil(store.snapshot.inFlightExecution)
        XCTAssertNil(store.snapshot.approvedPlan)
        XCTAssertTrue(store.snapshot.pendingNotificationCleanupIDs.isEmpty)
        XCTAssertEqual(store.snapshot.petXP, 0)
        XCTAssertEqual(store.latestReceipt?.status, .failed)
    }

    func testVerifiedTaskGrowsPet() async {
        let store = makeStore(
            persistence: MemorySnapshotStore(),
            gateway: GatewayStub(plan: makePlan(reminderEnabled: false))
        )

        await store.prepareTomorrow()
        await store.approvePendingPlan()

        XCTAssertEqual(store.snapshot.petXP, 20)
        XCTAssertEqual(store.stage, .companion)
        XCTAssertEqual(store.snapshot.receipts.filter { $0.status == .verified }.count, 1)
    }

    func testThreeFinishedVerifiedTasksReachGuardian() async {
        let plans = (0..<3).map { _ in makePlan(reminderEnabled: false) }
        let gateway = SequenceGateway(plans: plans)
        let store = makeStore(persistence: MemorySnapshotStore(), gateway: gateway)

        for index in plans.indices {
            await store.prepareTomorrow()
            await store.approvePendingPlan()
            XCTAssertEqual(store.latestReceipt?.status, .verified)
            XCTAssertTrue(store.snapshot.growthLedgerIsConsistent)
            if index < plans.count - 1 {
                store.finishLatestExecution()
                XCTAssertNil(store.snapshot.approvedPlan)
                XCTAssertEqual(store.latestReceipt?.canUndo, false)
                XCTAssertFalse(store.latestReceipt?.observedEffects.isEmpty ?? true)
            }
        }

        XCTAssertEqual(store.snapshot.receipts.count, 3)
        XCTAssertEqual(store.snapshot.petProfile.growth.awards.filter { $0.revokedAt == nil }.count, 3)
        XCTAssertEqual(store.snapshot.petXP, 60)
        XCTAssertEqual(store.stage, .guardian)
    }

    func testPendingNotificationCleanupReplaysOnRestart() async {
        let notificationID = "toma.cleanup.\(UUID().uuidString)"
        var snapshot = AppSnapshot.initial
        snapshot.pendingNotificationCleanupIDs.insert(notificationID)
        let reminders = ReminderSpy()
        reminders.pendingIDs.insert(notificationID)

        let store = makeStore(
            persistence: MemorySnapshotStore(initial: snapshot),
            reminders: reminders
        )

        XCTAssertFalse(reminders.pendingIDs.contains(notificationID))
        await waitUntil { store.snapshot.pendingNotificationCleanupIDs.isEmpty }
        XCTAssertTrue(store.snapshot.pendingNotificationCleanupIDs.isEmpty)
    }

    func testJSONSnapshotStorePersistsPetProfileAndSchema() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TomaTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        var snapshot = AppSnapshot.initial
        snapshot.petProfile.name = "小拓"
        snapshot.petProfile.preset = .spark
        snapshot.petProfile.archetype = .focused
        let persistence = JSONSnapshotStore(fileURL: fileURL)

        try persistence.save(snapshot)
        let reloaded = try XCTUnwrap(persistence.load())

        XCTAssertEqual(reloaded.schemaVersion, 2)
        XCTAssertEqual(reloaded.petProfile.id, snapshot.petProfile.id)
        XCTAssertEqual(reloaded.petProfile.name, "小拓")
        XCTAssertEqual(reloaded.petProfile.resolvedPreset, .spark)
        XCTAssertEqual(reloaded.petProfile.archetype, .focused)
        XCTAssertTrue(reloaded.growthLedgerIsConsistent)
    }

    func testPetProfileCanBePersonalizedAndPersists() {
        let persistence = MemorySnapshotStore()
        var store = makeStore(persistence: persistence)

        XCTAssertTrue(store.updatePetProfile(name: "  小拓  ", preset: .cloud))
        store = makeStore(persistence: persistence)

        XCTAssertEqual(store.snapshot.petProfile.name, "小拓")
        XCTAssertEqual(store.snapshot.petProfile.resolvedPreset, .cloud)
        XCTAssertEqual(store.snapshot.petProfile.archetype, .calm)
        XCTAssertEqual(store.snapshot.petXP, 0)
    }

    func testFirstVersionHasExactlyThreePetPresetsAndThreeEvolutionStages() {
        XCTAssertEqual(PetPreset.allCases, [.sprout, .spark, .cloud])
        XCTAssertEqual(PetPreset.allCases.map(\.defaultName), ["芽芽", "火花", "雲朵"])
        XCTAssertEqual(PetStage.allCases, [.hatchling, .companion, .guardian])
        XCTAssertEqual(PetPreset.sprout.archetype, .warm)
        XCTAssertEqual(PetPreset.spark.archetype, .focused)
        XCTAssertEqual(PetPreset.cloud.archetype, .calm)
    }

    func testLocalHatchRequestTrimsBindsAndPersistsWithStableDigest() throws {
        let persistence = MemorySnapshotStore()
        var store = makeStore(persistence: persistence)
        let originalProfile = store.snapshot.petProfile

        XCTAssertTrue(
            store.saveLocalHatchRequest(
                appearance: "  雲朵般的白色小鳥  ",
                avoid: "  皇冠  ",
                stylePreset: .plush
            )
        )

        let request = try XCTUnwrap(store.snapshot.petProfile.pendingHatchRequest)
        XCTAssertEqual(request.schemaVersion, LocalHatchRequest.currentSchemaVersion)
        XCTAssertEqual(request.state, .savedLocally)
        XCTAssertEqual(request.petID, originalProfile.id)
        XCTAssertEqual(request.petPreset, .sprout)
        XCTAssertEqual(request.targetStage, originalProfile.growth.stage)
        XCTAssertEqual(request.basePackageID, originalProfile.activePackage.id)
        XCTAssertEqual(request.baseVersion, originalProfile.activePackage.version)
        XCTAssertEqual(request.expectedNextVersion, originalProfile.activePackage.version + 1)
        XCTAssertEqual(request.appearance, "雲朵般的白色小鳥")
        XCTAssertEqual(request.avoid, "皇冠")
        XCTAssertEqual(request.stylePreset, .plush)
        XCTAssertEqual(request.canonicalDigest.count, 64)
        XCTAssertEqual(request.canonicalDigest, request.recomputedCanonicalDigest)
        XCTAssertTrue(request.isStructurallyValid)

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(LocalHatchRequest.self, from: encoded)
        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.canonicalDigest, request.canonicalDigest)

        store = makeStore(persistence: persistence)
        XCTAssertEqual(store.snapshot.petProfile.pendingHatchRequest, request)
        XCTAssertNil(store.snapshot.petProfile.pendingHatchJob)
        XCTAssertEqual(store.snapshot.petProfile.activePackage, originalProfile.activePackage)
        XCTAssertEqual(store.snapshot.petProfile.growth, originalProfile.growth)
    }

    func testLocalHatchCanonicalWirePayloadMatchesGoldenVector() throws {
        let request = LocalHatchRequest(
            clientRequestID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            petID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            petPreset: .sprout,
            targetStage: .hatchling,
            basePackageID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            baseVersion: 1,
            expectedNextVersion: 2,
            appearance: "芽/芽 \"雲\"\\路\n下一行\t結尾",
            avoid: "\u{0001}不要/標誌",
            stylePreset: .pixel,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
        let expectedJSON = #"{"appearance":"芽/芽 \"雲\"\\路\n下一行\t結尾","avoid":"\u0001不要/標誌","base_package_id":"33333333-3333-3333-3333-333333333333","base_version":1,"client_request_id":"11111111-1111-1111-1111-111111111111","expected_next_version":2,"pet_id":"22222222-2222-2222-2222-222222222222","pet_preset":"sprout","request_schema_version":1,"target_stage":"hatchling","visual_style":"pixel"}"#

        XCTAssertEqual(
            String(data: request.canonicalPayloadData, encoding: .utf8),
            expectedJSON
        )
        XCTAssertEqual(
            request.canonicalDigest,
            "133f6b1c4fa89ff6a440d8d55ac59aef809629df5a1572608058014b7b0f0f74"
        )
    }

    func testLocalHatchRequestRejectsInvalidAndConcurrentInputWithoutReplacingState() throws {
        let store = makeStore(persistence: MemorySnapshotStore())
        let originalProfile = store.snapshot.petProfile

        XCTAssertFalse(store.saveLocalHatchRequest(appearance: "  ", avoid: nil, stylePreset: .auto))
        XCTAssertFalse(store.saveLocalHatchRequest(appearance: "abc", avoid: nil, stylePreset: .pixel))
        XCTAssertFalse(
            store.saveLocalHatchRequest(
                appearance: String(repeating: "外", count: 281),
                avoid: nil,
                stylePreset: .clay
            )
        )
        XCTAssertFalse(
            store.saveLocalHatchRequest(
                appearance: "白色圓耳小鳥",
                avoid: String(repeating: "避", count: 161),
                stylePreset: .sticker
            )
        )
        XCTAssertNil(store.snapshot.petProfile.pendingHatchRequest)

        XCTAssertTrue(
            store.saveLocalHatchRequest(
                appearance: "白色圓耳小鳥",
                avoid: nil,
                stylePreset: .pixel
            )
        )
        let saved = try XCTUnwrap(store.snapshot.petProfile.pendingHatchRequest)
        XCTAssertFalse(
            store.saveLocalHatchRequest(
                appearance: "另一隻不同的小鳥",
                avoid: nil,
                stylePreset: .clay
            )
        )
        XCTAssertEqual(store.snapshot.petProfile.pendingHatchRequest, saved)
        XCTAssertNil(store.snapshot.petProfile.pendingHatchJob)
        XCTAssertEqual(store.snapshot.petProfile.activePackage, originalProfile.activePackage)
        XCTAssertEqual(store.snapshot.petProfile.growth, originalProfile.growth)
    }

    func testEditingLocalHatchRequestCreatesNewIdentityAndDigest() throws {
        let persistence = MemorySnapshotStore()
        let store = makeStore(persistence: persistence)
        let originalProfile = store.snapshot.petProfile
        XCTAssertTrue(
            store.saveLocalHatchRequest(
                appearance: "圓潤的白色小鳥",
                avoid: "帽子",
                stylePreset: .plush
            )
        )
        let first = try XCTUnwrap(store.snapshot.petProfile.pendingHatchRequest)

        XCTAssertTrue(
            store.updateLocalHatchRequest(
                appearance: "  黏土質感的藍色小鳥  ",
                avoid: "   ",
                stylePreset: .clay
            )
        )
        let edited = try XCTUnwrap(store.snapshot.petProfile.pendingHatchRequest)

        XCTAssertNotEqual(edited.clientRequestID, first.clientRequestID)
        XCTAssertNotEqual(edited.canonicalDigest, first.canonicalDigest)
        XCTAssertEqual(edited.createdAt, first.createdAt)
        XCTAssertGreaterThanOrEqual(edited.updatedAt, edited.createdAt)
        XCTAssertEqual(edited.appearance, "黏土質感的藍色小鳥")
        XCTAssertNil(edited.avoid)
        XCTAssertEqual(edited.stylePreset, .clay)
        XCTAssertEqual(edited.canonicalDigest, edited.recomputedCanonicalDigest)
        XCTAssertNil(store.snapshot.petProfile.pendingHatchJob)
        XCTAssertEqual(store.snapshot.petProfile.activePackage, originalProfile.activePackage)
        XCTAssertEqual(store.snapshot.petProfile.growth, originalProfile.growth)
    }

    func testGrowthContinuesWhileLocalHatchRequestBecomesStale() async throws {
        let persistence = MemorySnapshotStore()
        let store = makeStore(
            persistence: persistence,
            gateway: GatewayStub(plan: makePlan(reminderEnabled: false))
        )
        XCTAssertTrue(
            store.saveLocalHatchRequest(
                appearance: "薄荷綠、耳朵像兩片嫩芽",
                avoid: nil,
                stylePreset: .plush
            )
        )
        let first = try XCTUnwrap(store.snapshot.petProfile.pendingHatchRequest)
        XCTAssertTrue(store.snapshot.petProfile.localHatchRequestIsCurrent)

        await store.prepareTomorrow()
        await store.approvePendingPlan()

        XCTAssertEqual(store.snapshot.petXP, 20)
        XCTAssertEqual(store.stage, .companion)
        XCTAssertEqual(store.snapshot.petProfile.pendingHatchRequest, first)
        XCTAssertTrue(store.snapshot.petProfile.localHatchStateIsConsistent)
        XCTAssertFalse(store.snapshot.petProfile.localHatchRequestIsCurrent)

        XCTAssertTrue(
            store.updateLocalHatchRequest(
                appearance: first.appearance,
                avoid: first.avoid,
                stylePreset: first.stylePreset
            )
        )
        let rebound = try XCTUnwrap(store.snapshot.petProfile.pendingHatchRequest)
        XCTAssertNotEqual(rebound.clientRequestID, first.clientRequestID)
        XCTAssertNotEqual(rebound.canonicalDigest, first.canonicalDigest)
        XCTAssertEqual(rebound.targetStage, .companion)
        XCTAssertTrue(store.snapshot.petProfile.localHatchRequestIsCurrent)
    }

    func testChangingPetPresetMakesLocalHatchRequestStaleUntilResaved() throws {
        let store = makeStore(persistence: MemorySnapshotStore())
        XCTAssertTrue(
            store.saveLocalHatchRequest(
                appearance: "嫩芽耳朵與柔和的綠色",
                avoid: nil,
                stylePreset: .plush
            )
        )
        let sproutRequest = try XCTUnwrap(store.snapshot.petProfile.pendingHatchRequest)
        XCTAssertEqual(sproutRequest.petPreset, .sprout)

        XCTAssertTrue(store.updatePetProfile(name: "火花", preset: .spark))
        XCTAssertEqual(store.snapshot.petProfile.resolvedPreset, .spark)
        XCTAssertTrue(store.snapshot.petProfile.localHatchStateIsConsistent)
        XCTAssertFalse(store.snapshot.petProfile.localHatchRequestIsCurrent)

        XCTAssertTrue(
            store.updateLocalHatchRequest(
                appearance: "明亮、有速度感的橘紅色",
                avoid: nil,
                stylePreset: .sticker
            )
        )
        let sparkRequest = try XCTUnwrap(store.snapshot.petProfile.pendingHatchRequest)
        XCTAssertEqual(sparkRequest.petPreset, .spark)
        XCTAssertNotEqual(sparkRequest.clientRequestID, sproutRequest.clientRequestID)
        XCTAssertTrue(store.snapshot.petProfile.localHatchRequestIsCurrent)
    }

    func testDeletingLocalHatchRequestDoesNotChangeEvolutionState() {
        let persistence = MemorySnapshotStore()
        var store = makeStore(persistence: persistence)
        let originalProfile = store.snapshot.petProfile
        XCTAssertTrue(
            store.saveLocalHatchRequest(
                appearance: "像素風格的藍色小鳥",
                avoid: nil,
                stylePreset: .pixel
            )
        )

        XCTAssertTrue(store.deleteLocalHatchRequest())
        XCTAssertNil(store.snapshot.petProfile.pendingHatchRequest)
        XCTAssertNil(store.snapshot.petProfile.pendingHatchJob)
        XCTAssertEqual(store.snapshot.petProfile.activePackage, originalProfile.activePackage)
        XCTAssertEqual(store.snapshot.petProfile.growth, originalProfile.growth)
        XCTAssertFalse(store.deleteLocalHatchRequest())

        store = makeStore(persistence: persistence)
        XCTAssertNil(store.snapshot.petProfile.pendingHatchRequest)
        XCTAssertEqual(store.snapshot.petProfile.activePackage, originalProfile.activePackage)
        XCTAssertEqual(store.snapshot.petProfile.growth, originalProfile.growth)
    }

    func testLocalHatchRequestNeverReplacesAcceptedGatewayJob() {
        var snapshot = AppSnapshot.initial
        let job = HatchJob(
            id: UUID(),
            petID: snapshot.petProfile.id,
            targetStage: snapshot.petProfile.growth.stage,
            phase: .queued,
            package: nil,
            failureCode: nil
        )
        snapshot.petProfile.pendingHatchJob = job
        let store = makeStore(persistence: MemorySnapshotStore(initial: snapshot))
        let originalPackage = store.snapshot.petProfile.activePackage
        let originalGrowth = store.snapshot.petProfile.growth

        XCTAssertFalse(
            store.saveLocalHatchRequest(
                appearance: "柔軟的白色小鳥",
                avoid: nil,
                stylePreset: .plush
            )
        )
        XCTAssertEqual(store.snapshot.petProfile.pendingHatchJob, job)
        XCTAssertNil(store.snapshot.petProfile.pendingHatchRequest)
        XCTAssertEqual(store.snapshot.petProfile.activePackage, originalPackage)
        XCTAssertEqual(store.snapshot.petProfile.growth, originalGrowth)
    }

    func testLoadedSnapshotRejectsTamperedLocalHatchDigest() {
        var snapshot = AppSnapshot.initial
        let activePackage = snapshot.petProfile.activePackage
        snapshot.petProfile.pendingHatchRequest = LocalHatchRequest(
            petID: snapshot.petProfile.id,
            petPreset: snapshot.petProfile.resolvedPreset,
            targetStage: snapshot.petProfile.growth.stage,
            basePackageID: activePackage.id,
            baseVersion: activePackage.version,
            expectedNextVersion: activePackage.version + 1,
            appearance: "柔軟的白色小鳥",
            avoid: nil,
            stylePreset: .plush,
            canonicalDigest: "tampered",
            createdAt: fixedNow,
            updatedAt: fixedNow
        )

        let store = makeStore(persistence: MemorySnapshotStore(initial: snapshot))

        XCTAssertNil(store.snapshot.petProfile.pendingHatchRequest)
        XCTAssertNotNil(store.errorBanner)
    }

    func testPetProfileDecodesSnapshotWithoutLocalHatchRequestField() throws {
        let encoded = try JSONEncoder().encode(PetProfile.initial)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertNil(object["pendingHatchRequest"])

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(PetProfile.self, from: legacyData)

        XCTAssertNil(decoded.pendingHatchRequest)
        XCTAssertTrue(decoded.localHatchStateIsConsistent)
    }

    func testPetProfileDecodesLegacySnapshotWithoutPresetField() throws {
        let encoded = try JSONEncoder().encode(PetProfile.initial)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "preset")
        object["archetype"] = PetArchetype.adventurous.rawValue

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(PetProfile.self, from: legacyData)

        XCTAssertNil(decoded.preset)
        XCTAssertEqual(decoded.resolvedPreset, .cloud)
        XCTAssertTrue(decoded.presetStateIsConsistent)
    }

    func testGrowthAwardIsIdempotentAndBoundToOnePet() {
        var profile = PetProfile.initial
        let receipt = makeReceipt(petID: profile.id)

        XCTAssertTrue(profile.applyVerifiedReceipt(receipt))
        XCTAssertFalse(profile.applyVerifiedReceipt(receipt))
        XCTAssertEqual(profile.growth.xp, 20)

        let wrongPetReceipt = makeReceipt(petID: UUID())
        XCTAssertFalse(profile.applyVerifiedReceipt(wrongPetReceipt))
        XCTAssertFalse(profile.applyVerifiedReceipt(makeReceipt(petID: profile.id, status: .partial)))
        XCTAssertFalse(profile.applyVerifiedReceipt(makeReceipt(petID: profile.id, xpAwarded: 40)))
        XCTAssertEqual(profile.growth.xp, 20)
    }

    func testGrowthThresholdsAreExact() {
        XCTAssertEqual(PetStage(xp: 0), .hatchling)
        XCTAssertEqual(PetStage(xp: 19), .hatchling)
        XCTAssertEqual(PetStage(xp: 20), .companion)
        XCTAssertEqual(PetStage(xp: 59), .companion)
        XCTAssertEqual(PetStage(xp: 60), .guardian)
    }

    func testLedgerRejectsVerifiedReceiptWithoutMatchingAward() {
        var snapshot = AppSnapshot.initial
        snapshot.receipts.append(makeReceipt(petID: snapshot.petProfile.id))

        XCTAssertFalse(snapshot.growthLedgerIsConsistent)
    }

    func testOnlyPendingReadyValidatedV2HatchCanActivate() {
        var profile = PetProfile.initial
        let package = HatchPackageReference(
            id: UUID(),
            version: 2,
            targetStage: .hatchling,
            spriteVersionNumber: 2,
            atlasSHA256: String(repeating: "a", count: 64),
            validationReceiptID: UUID()
        )
        var job = HatchJob(
            id: UUID(),
            petID: profile.id,
            targetStage: .hatchling,
            phase: .validating,
            package: package,
            failureCode: nil
        )
        profile.pendingHatchJob = job

        XCTAssertFalse(profile.activateReadyHatch(downloadedAtlasSHA256: package.atlasSHA256))
        XCTAssertEqual(profile.activePackage.version, 1)

        job.phase = .ready
        profile.pendingHatchJob = job
        XCTAssertFalse(profile.activateReadyHatch(downloadedAtlasSHA256: String(repeating: "b", count: 64)))
        XCTAssertTrue(profile.activateReadyHatch(downloadedAtlasSHA256: package.atlasSHA256))
        XCTAssertEqual(profile.activePackage.version, 2)
        XCTAssertNil(profile.pendingHatchJob)
    }

    func testSelectedProviderFlowsThroughNeutralGateway() async {
        let gateway = GatewayStub(plan: makePlan())
        let store = makeStore(persistence: MemorySnapshotStore(), gateway: gateway)

        store.selectProvider(.claude)
        await store.send("你好")

        XCTAssertEqual(gateway.lastReplyProvider, .claude)
        XCTAssertEqual(store.snapshot.messages.last?.role, .pet)
    }

    private func makePlan(reminderEnabled: Bool = true) -> TomorrowPlan {
        TomorrowPlan(
            title: "明日準備",
            items: [
                TomorrowPlanItem(text: "選出最重要的一件事"),
                TomorrowPlanItem(text: "設定第一個步驟")
            ],
            reminderEnabled: reminderEnabled,
            createdAt: fixedNow
        )
    }

    private func makeReceipt(
        petID: UUID,
        status: ReceiptStatus = .verified,
        xpAwarded: Int = 20
    ) -> TaskReceipt {
        TaskReceipt(
            petID: petID,
            planID: UUID(),
            planVersion: 1,
            planDigest: String(repeating: "a", count: 64),
            status: status,
            summary: "已驗證",
            createdAt: fixedNow,
            xpAwarded: xpAwarded,
            canUndo: true
        )
    }

    private func makeStore(
        persistence: MemorySnapshotStore,
        gateway: (any AgentGateway)? = nil,
        reminders: (any ReminderScheduling)? = nil
    ) -> AppStore {
        AppStore(
            snapshotStore: persistence,
            gateway: gateway ?? GatewayStub(plan: makePlan()),
            reminders: reminders ?? ReminderSpy(),
            now: { self.fixedNow }
        )
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for async test gate")
    }
}

private final class MemorySnapshotStore: SnapshotPersisting {
    var snapshot: AppSnapshot?
    var shouldFailSave = false

    init(initial: AppSnapshot? = nil) {
        self.snapshot = initial
    }

    func load() throws -> AppSnapshot? {
        snapshot
    }

    func save(_ snapshot: AppSnapshot) throws {
        if shouldFailSave { throw TestError.forced }
        self.snapshot = snapshot
    }
}

private final class GatewayStub: AgentGateway {
    let plan: TomorrowPlan
    var lastReplyProvider: ModelProvider?

    init(plan: TomorrowPlan) {
        self.plan = plan
    }

    func reply(
        to message: String,
        provider: ModelProvider,
        memories: [MemoryEntry]
    ) async throws -> String {
        lastReplyProvider = provider
        return "收到"
    }

    func prepareTomorrow(
        provider: ModelProvider,
        memories: [MemoryEntry],
        now: Date
    ) async throws -> TomorrowPlan {
        plan
    }
}

private final class SequenceGateway: AgentGateway {
    private let plans: [TomorrowPlan]
    private var nextPlanIndex = 0

    init(plans: [TomorrowPlan]) {
        self.plans = plans
    }

    func reply(
        to message: String,
        provider: ModelProvider,
        memories: [MemoryEntry]
    ) async throws -> String {
        "收到"
    }

    func prepareTomorrow(
        provider: ModelProvider,
        memories: [MemoryEntry],
        now: Date
    ) async throws -> TomorrowPlan {
        guard plans.indices.contains(nextPlanIndex) else { throw TestError.forced }
        defer { nextPlanIndex += 1 }
        return plans[nextPlanIndex]
    }
}

private final class GatedGateway: AgentGateway {
    let plan: TomorrowPlan
    var prepareStarted = false

    private var prepareContinuation: CheckedContinuation<Void, Never>?

    init(plan: TomorrowPlan) {
        self.plan = plan
    }

    func reply(
        to message: String,
        provider: ModelProvider,
        memories: [MemoryEntry]
    ) async throws -> String {
        "收到"
    }

    func prepareTomorrow(
        provider: ModelProvider,
        memories: [MemoryEntry],
        now: Date
    ) async throws -> TomorrowPlan {
        prepareStarted = true
        await withCheckedContinuation { continuation in
            prepareContinuation = continuation
        }
        return plan
    }

    func resumePrepare() {
        let continuation = prepareContinuation
        prepareContinuation = nil
        continuation?.resume()
    }
}

private final class ReminderSpy: ReminderScheduling {
    let isAuthorized: Bool
    var scheduleCount = 0
    var pendingIDs: Set<String> = []
    var deliveredIDs: Set<String> = []
    var cancelSucceeds = true

    init(isAuthorized: Bool = true) {
        self.isAuthorized = isAuthorized
    }

    func requestAuthorization() async -> Bool {
        isAuthorized
    }

    func scheduleTomorrowMorning(for plan: TomorrowPlan, identifier: String) async throws {
        scheduleCount += 1
        pendingIDs.insert(identifier)
    }

    func cancel(identifier: String) {
        guard cancelSucceeds else { return }
        pendingIDs.remove(identifier)
        deliveredIDs.remove(identifier)
    }

    func isPending(identifier: String) async -> Bool {
        pendingIDs.contains(identifier)
    }

    func isDelivered(identifier: String) async -> Bool {
        deliveredIDs.contains(identifier)
    }
}

private final class GatedReminderSpy: ReminderScheduling {
    enum PausePoint {
        case authorization
        case scheduling
    }

    let pausePoint: PausePoint
    var authorizationStarted = false
    var schedulingStarted = false
    var scheduleCount = 0
    var pendingIDs: Set<String> = []

    private var authorizationContinuation: CheckedContinuation<Bool, Never>?
    private var schedulingContinuation: CheckedContinuation<Void, Never>?

    init(pausePoint: PausePoint) {
        self.pausePoint = pausePoint
    }

    func requestAuthorization() async -> Bool {
        guard pausePoint == .authorization else { return true }
        authorizationStarted = true
        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
        }
    }

    func resumeAuthorization() {
        let continuation = authorizationContinuation
        authorizationContinuation = nil
        continuation?.resume(returning: true)
    }

    func scheduleTomorrowMorning(for plan: TomorrowPlan, identifier: String) async throws {
        scheduleCount += 1
        if pausePoint == .scheduling {
            schedulingStarted = true
            await withCheckedContinuation { continuation in
                schedulingContinuation = continuation
            }
        }
        pendingIDs.insert(identifier)
    }

    func resumeScheduling() {
        let continuation = schedulingContinuation
        schedulingContinuation = nil
        continuation?.resume()
    }

    func cancel(identifier: String) {
        pendingIDs.remove(identifier)
    }

    func isPending(identifier: String) async -> Bool {
        pendingIDs.contains(identifier)
    }

    func isDelivered(identifier: String) async -> Bool {
        false
    }
}

private enum TestError: Error {
    case forced
}
