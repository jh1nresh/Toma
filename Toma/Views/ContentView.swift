import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var intentHandoff: IntentHandoffStore
    @StateObject private var speech = SpeechInput()
    @State private var composer = ""
    @State private var presentedSheet: SheetDestination?

    var body: some View {
        ScrollViewReader { proxy in
            NavigationStack {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        PetCard()
                        QuickActionCard()

                        if store.snapshot.pendingPlan != nil {
                            DraftPlanCard()
                                .id("pending-plan")
                        }

                        if let plan = store.snapshot.approvedPlan {
                            ApprovedPlanCard(plan: plan)
                        }

                        if let receipt = store.latestReceipt {
                            ReceiptCard(receipt: receipt)
                        }

                        ConversationCard()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .background(AppBackground())
                .navigationTitle(store.snapshot.petProfile.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ProviderMenu()
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            presentedSheet = .petProfile
                        } label: {
                            Label("我的 Hatch Pet", systemImage: "pawprint.fill")
                        }
                        .accessibilityIdentifier("pet.profile")

                        Button {
                            presentedSheet = .memoryBook
                        } label: {
                            Label("記憶簿", systemImage: "book.pages")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    ComposerBar(text: $composer, speech: speech)
                }
            }
            .tint(.indigo)
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case .petProfile:
                    PetProfileView(profile: store.snapshot.petProfile)
                        .environmentObject(store)
                case .memoryBook:
                    MemoryBookView()
                        .environmentObject(store)
                }
            }
            .onChange(of: speech.transcript) { _, transcript in
                composer = transcript
            }
            .onChange(of: speech.isRecording) { _, recording in
                store.setListening(recording)
            }
            .onChange(of: intentHandoff.pendingAction, initial: true) { _, action in
                guard let action else { return }
                Task { @MainActor in
                    switch action.kind {
                    case .askPet:
                        if let question = action.question {
                            await store.send(question)
                        }
                    case .prepareTomorrow:
                        await store.prepareTomorrow()
                    case .continuePendingTask:
                        store.continuePendingTask()
                        await Task.yield()
                        withAnimation {
                            proxy.scrollTo("pending-plan", anchor: .top)
                        }
                    }
                    intentHandoff.consume(id: action.id)
                }
            }
            .alert(
                "\(store.snapshot.petProfile.name) 需要你看看",
                isPresented: Binding(
                    get: { store.errorBanner != nil },
                    set: { if !$0 { store.clearError() } }
                )
            ) {
                Button("知道了") { store.clearError() }
            } message: {
                Text(store.errorBanner ?? "")
            }
        }
    }
}

private enum SheetDestination: String, Identifiable {
    case petProfile
    case memoryBook

    var id: String { rawValue }
}

private struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.96, blue: 1),
                Color(red: 1, green: 0.97, blue: 0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct PetCard: View {
    @EnvironmentObject private var store: AppStore

    private var growthProgress: Double {
        let xp = store.snapshot.petXP
        if xp < 20 { return Double(xp) / 20 }
        if xp < 60 { return Double(xp - 20) / 40 }
        return 1
    }

    private var nextMilestone: String {
        let xp = store.snapshot.petXP
        if xp < 20 { return "再 \(20 - xp) XP 成為默契夥伴" }
        if xp < 60 { return "再 \(60 - xp) XP 成為日常守護者" }
        return "已完成目前成長階段"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.stage.title)
                        .font(.headline)
                        .accessibilityIdentifier("pet.stage")
                    Text(store.snapshot.petProfile.archetype.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(store.activity.label, systemImage: activityIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(store.snapshot.petXP) XP")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.indigo.opacity(0.11), in: Capsule())
                    .accessibilityIdentifier("pet.xp")
            }

            PetSpriteView(
                name: store.snapshot.petProfile.name,
                activity: store.activity,
                stage: store.stage
            )

            ProgressView(value: growthProgress)
                .tint(.indigo)
                .accessibilityLabel("成長進度")
            Text(nextMilestone)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .cardStyle()
    }

    private var activityIcon: String {
        switch store.activity {
        case .idle: "heart.fill"
        case .listening: "waveform"
        case .working: "sparkles"
        case .waitingForApproval: "hand.raised.fill"
        case .celebrating: "party.popper.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

private struct ProviderMenu: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Menu {
            ForEach(ModelProvider.allCases) { provider in
                Button {
                    store.selectProvider(provider)
                } label: {
                    if provider == store.snapshot.selectedProvider {
                        Label(provider.displayName, systemImage: "checkmark")
                    } else {
                        Text(provider.displayName)
                    }
                }
            }
        } label: {
            Label(
                "\(store.snapshot.selectedProvider.displayName) · Demo",
                systemImage: "point.3.connected.trianglepath.dotted"
            )
            .font(.caption.weight(.semibold))
        }
        .accessibilityHint("這個原型的三個選項都使用本機示範路由")
    }
}

private struct QuickActionCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sun.horizon.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 44, height: 44)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                Text("幫我準備明天")
                    .font(.headline)
                Text("先產生草稿；你批准前不會保存計畫或設定提醒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button {
                Task { await store.prepareTomorrow() }
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(
                store.snapshot.pendingPlan != nil
                    || store.snapshot.approvedPlan != nil
                    || store.activity == .working
            )
            .accessibilityLabel("建立明日草稿")
            .accessibilityIdentifier("plan.prepare")
        }
        .padding(16)
        .cardStyle()
    }
}

private struct DraftPlanCard: View {
    @EnvironmentObject private var store: AppStore

    private var plan: TomorrowPlan? { store.snapshot.pendingPlan }

    var body: some View {
        if let plan {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("執行前預覽", systemImage: "hand.raised.fill")
                        .font(.headline)
                        .accessibilityIdentifier("plan.preview")
                    Spacer()
                    Text("v\(plan.version)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("plan.version")
                }

                TextField(
                    "計畫標題",
                    text: Binding(
                        get: { plan.title },
                        set: store.updateDraftTitle
                    )
                )
                .textFieldStyle(.roundedBorder)

                ForEach(plan.items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { item.isEnabled },
                                set: { store.setDraftItemEnabled(id: item.id, enabled: $0) }
                            )
                        )
                        .labelsHidden()
                        .accessibilityLabel("明日計畫步驟：\(item.text)")

                        TextField(
                            "步驟",
                            text: Binding(
                                get: { item.text },
                                set: { store.updateDraftItem(id: item.id, text: $0) }
                            ),
                            axis: .vertical
                        )
                        .lineLimit(1...3)
                    }
                }

                Toggle(
                    "明早 8:00 本機提醒",
                    isOn: Binding(
                        get: { plan.reminderEnabled },
                        set: store.setDraftReminderEnabled
                    )
                )
                .accessibilityIdentifier("plan.reminder")

                Text("批准會綁定這一版內容。任何編輯都會產生新版本。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await store.approvePendingPlan() }
                } label: {
                    Text("批准並執行")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("plan.approve")

                Button("不要了", role: .cancel) {
                    store.discardDraft()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
            .cardStyle(border: .orange.opacity(0.45))
        }
    }
}

private struct ApprovedPlanCard: View {
    let plan: TomorrowPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("已批准的明日計畫", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(plan.title)
                .font(.subheadline.weight(.semibold))
            ForEach(plan.items.filter(\.isEnabled)) { item in
                Label(item.text, systemImage: "checkmark.circle")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardStyle()
    }
}

private struct ReceiptCard: View {
    @EnvironmentObject private var store: AppStore
    let receipt: TaskReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(receipt.status.label, systemImage: receipt.status.icon)
                    .font(.headline)
                    .foregroundStyle(receipt.status.color)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(receipt.status.label)
                    .accessibilityIdentifier("receipt.status")
                Spacer()
                Text(receipt.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(receipt.summary)
                .font(.subheadline)
                .accessibilityIdentifier("receipt.summary")
            ForEach(Array(receipt.observedEffects.enumerated()), id: \.offset) { entry in
                Label(entry.element, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("計畫 v\(receipt.planVersion) · \(receipt.planDigest.prefix(10))")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            if receipt.canUndo {
                Button(role: .destructive) {
                    Task { await store.undoLatestExecution() }
                } label: {
                    Label("復原這次執行", systemImage: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("receipt.undo")

                if receipt.notificationIdentifier == nil {
                    Button {
                        store.finishLatestExecution()
                    } label: {
                        Label("封存並開始下一次", systemImage: "archivebox")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("receipt.finish")

                    Text("封存會保留已驗證收據與成長，但清除目前計畫內容，之後不能再復原這次執行。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardStyle(border: receipt.status.color.opacity(0.35))
    }
}

private struct ConversationCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("對話", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.headline)

            ForEach(Array(store.snapshot.messages.suffix(8))) { message in
                HStack {
                    if message.role == .user { Spacer(minLength: 44) }
                    Text(message.text)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            message.role == .user ? Color.indigo : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .foregroundStyle(message.role == .user ? .white : .primary)
                    if message.role == .pet { Spacer(minLength: 44) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardStyle()
    }
}

private struct ComposerBar: View {
    @EnvironmentObject private var store: AppStore
    @Binding var text: String
    @ObservedObject var speech: SpeechInput

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    if speech.isRecording {
                        speech.stop()
                    } else {
                        Task { await speech.start() }
                    }
                } label: {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(speech.isRecording ? "停止錄音" : "語音輸入")

                TextField("跟\(store.snapshot.petProfile.name)說…", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("composer.input")

                Button {
                    let outgoing = text
                    text = ""
                    Task { await store.send(outgoing) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("送出")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.7), lineWidth: 1)
            }

            if let error = speech.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }
}

private struct PetProfileView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var archetype: PetArchetype

    init(profile: PetProfile) {
        _name = State(initialValue: profile.name)
        _archetype = State(initialValue: profile.archetype)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("你的 Hatch Pet") {
                    TextField("名字", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("pet.name")

                    Picker("個性", selection: $archetype) {
                        ForEach(PetArchetype.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }

                Section("個性表達") {
                    Text(archetype.summary)
                        .foregroundStyle(.secondary)
                }

                Section("可稽核成長") {
                    LabeledContent("目前階段", value: store.stage.title)
                    LabeledContent("已驗證成長", value: "\(store.snapshot.petXP) XP")
                    Text("只有使用者批准、執行完成且讀回驗證的任務才會獲得 20 XP；聊天、草稿、失敗與部分完成都不加分。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("專屬外觀") {
                    Label("私人測試素材只在本機載入", systemImage: "lock.shield.fill")
                        .foregroundStyle(.blue)
                    Text("正式專屬外觀會由安全後端驗證簽章，並由 App 比對下載檔案雜湊後才啟用；素材缺少或驗證失敗時使用內建外觀。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("我的 Hatch Pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if store.updatePetProfile(name: trimmedName, archetype: archetype) {
                            dismiss()
                        }
                    }
                    .disabled(trimmedName.isEmpty || trimmedName.count > 20)
                    .accessibilityIdentifier("pet.save")
                }
            }
        }
    }
}

private struct MemoryBookView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var newMemory = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("例如：明天先完成提案", text: $newMemory)
                        Button("記住") {
                            store.addMemory(newMemory)
                            newMemory = ""
                        }
                        .disabled(newMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } footer: {
                    Text("只有你打開的記憶會進入 Agent 上下文；刪除會遮蔽\(store.snapshot.petProfile.name)產生內容中的相同原文，你自己輸入的對話仍保留。這個 demo 不會上傳網路。")
                }

                Section("\(store.snapshot.petProfile.name)記住的事") {
                    if store.snapshot.memories.isEmpty {
                        ContentUnavailableView(
                            "還沒有記憶",
                            systemImage: "book.closed",
                            description: Text("你可以新增、停用或刪除每一則記憶。")
                        )
                    } else {
                        ForEach(store.snapshot.memories) { memory in
                            Toggle(
                                isOn: Binding(
                                    get: { memory.isEnabledForAgent },
                                    set: { store.setMemoryEnabled(id: memory.id, enabled: $0) }
                                )
                            ) {
                                Text(memory.text)
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { store.snapshot.memories[$0].id }
                            Task {
                                for id in ids {
                                    await store.deleteMemory(id: id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("記憶簿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private extension ReceiptStatus {
    var label: String {
        switch self {
        case .verified: "已驗證"
        case .partial: "部分完成"
        case .failed: "未完成"
        case .reverted: "已復原"
        }
    }

    var icon: String {
        switch self {
        case .verified: "checkmark.seal.fill"
        case .partial: "exclamationmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .reverted: "arrow.uturn.backward.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .verified: .green
        case .partial: .orange
        case .failed: .red
        case .reverted: .blue
        }
    }
}

private extension View {
    func cardStyle(border: Color = .white.opacity(0.65)) -> some View {
        background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppStore())
        .environmentObject(IntentHandoffStore.shared)
}
