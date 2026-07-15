import SwiftUI

struct CustomHatchStatusSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var isConfirmingDeletion = false
    let presetSelectionIsSaved: Bool

    private var requestIsCurrent: Bool {
        store.snapshot.petProfile.localHatchRequestIsCurrent
    }

    private var statusText: String {
        requestIsCurrent
            ? "只儲存在本機・尚未送出"
            : "Pet 或外觀狀態已改變・請重新確認"
    }

    var body: some View {
        Section("自訂 Pet Hatch") {
            if let request = store.snapshot.petProfile.pendingHatchRequest {
                Label(
                    statusText,
                    systemImage: requestIsCurrent ? "iphone" : "exclamationmark.triangle.fill"
                )
                    .foregroundStyle(requestIsCurrent ? .blue : .orange)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(statusText)
                    .accessibilityIdentifier("hatch.status")

                LabeledContent("風格", value: request.stylePreset.displayName)
                LabeledContent("基礎 Pet", value: request.petPreset.defaultName)
                LabeledContent("目標階段", value: request.targetStage.title)

                VStack(alignment: .leading, spacing: 5) {
                    Text("外觀願望")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(request.appearance)
                }

                if let avoid = request.avoid {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("不要出現")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(avoid)
                    }
                }

                if !requestIsCurrent {
                    Text("這份願望綁定「\(request.petPreset.defaultName)・\(request.targetStage.title)」與外觀 v\(request.baseVersion)。請編輯並重新儲存，建立符合目前狀態的新 request；目前願望不會送出。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                NavigationLink {
                    CustomHatchView(request: request)
                } label: {
                    Label("編輯本機外觀願望", systemImage: "pencil")
                }
                .disabled(!presetSelectionIsSaved)
                .accessibilityIdentifier("hatch.edit")

                Button("刪除本機外觀願望", role: .destructive) {
                    isConfirmingDeletion = true
                }
                .accessibilityIdentifier("hatch.delete")
            } else {
                NavigationLink {
                    CustomHatchView()
                } label: {
                    Label("建立自訂外觀願望", systemImage: "sparkles")
                }
                .disabled(!presetSelectionIsSaved)
                .accessibilityIdentifier("hatch.create")

                Text("先用文字與風格描述牠。這一版只保存到本機，不會送出或生成圖片。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !presetSelectionIsSaved {
                Label("先保存 Pet 身份，再設計牠的外觀。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("hatch.identityWarning")
            }

            Text("正式外觀必須由 Gateway 產生完整 8×11 v2 動畫、驗證簽章與下載檔案雜湊，再由你明確啟用；任何失敗都保留目前外觀。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(
            "刪除這份本機外觀願望？",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("刪除", role: .destructive) {
                _ = store.deleteLocalHatchRequest()
            }
            Button("保留", role: .cancel) {}
        } message: {
            Text("這只會刪除尚未送出的文字與風格，不會改變目前外觀。")
        }
    }
}

struct CustomHatchView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private let request: LocalHatchRequest?
    @State private var appearance: String
    @State private var avoid: String
    @State private var stylePreset: HatchStylePreset
    @State private var review: LocalHatchReview?

    init(request: LocalHatchRequest? = nil) {
        self.request = request
        _appearance = State(initialValue: request?.appearance ?? "")
        _avoid = State(initialValue: request?.avoid ?? "")
        _stylePreset = State(initialValue: request?.stylePreset ?? .auto)
        _review = State(initialValue: nil)
    }

    private var trimmedAppearance: String {
        appearance.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAvoid: String {
        avoid.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        (4...280).contains(trimmedAppearance.count) && trimmedAvoid.count <= 160
    }

    var body: some View {
        Group {
            if let review {
                HatchReviewForm(review: review)
            } else {
                HatchDescriptionForm(
                    appearance: $appearance,
                    avoid: $avoid,
                    stylePreset: $stylePreset,
                    petPreset: store.snapshot.petProfile.resolvedPreset,
                    stage: store.stage
                )
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(review != nil)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if review != nil {
                    Button("返回修改") {
                        review = nil
                    }
                    .accessibilityIdentifier("hatch.review.back")
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                if let review {
                    Button("儲存在本機") {
                        confirm(review)
                    }
                    .accessibilityIdentifier("hatch.confirmSave")
                } else {
                    Button("檢查設計單") {
                        makeReview()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("hatch.review")
                }
            }
        }
    }

    private var navigationTitle: String {
        if review != nil { return "Hatch 設計單" }
        return request == nil ? "自訂 Pet Hatch" : "編輯外觀願望"
    }

    private func makeReview() {
        review = store.reviewLocalHatchRequest(
            appearance: trimmedAppearance,
            avoid: trimmedAvoid,
            stylePreset: stylePreset,
            replacing: request?.clientRequestID
        )
    }

    private func confirm(_ review: LocalHatchReview) {
        let saved = store.saveLocalHatchReview(
            review,
            replacing: request?.clientRequestID
        )
        if saved {
            dismiss()
        } else {
            self.review = nil
        }
    }
}

private struct HatchDescriptionForm: View {
    @Binding var appearance: String
    @Binding var avoid: String
    @Binding var stylePreset: HatchStylePreset
    let petPreset: PetPreset
    let stage: PetStage

    private var trimmedAppearanceCount: Int {
        appearance.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private var trimmedAvoidCount: Int {
        avoid.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    var body: some View {
        Form {
            Section {
                HatchStyleDirectionCard(
                    petPreset: petPreset,
                    stage: stage,
                    style: stylePreset
                )
            }

            Section {
                ZStack(alignment: .topLeading) {
                    if appearance.isEmpty {
                        Text("例如：圓滾滾、薄荷綠，耳朵像兩片嫩芽")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $appearance)
                        .frame(minHeight: 112)
                        .accessibilityLabel("外觀願望")
                        .accessibilityIdentifier("hatch.appearance")
                }

                CharacterCount(value: trimmedAppearanceCount, limit: 280, minimum: 4)
            } header: {
                Text("你想讓牠長什麼樣子？")
            } footer: {
                Text("寫外型、顏色、材質與最重要的辨識特徵。請不要填入秘密或個人資料。")
            }

            Section("不要出現（選填）") {
                ZStack(alignment: .topLeading) {
                    if avoid.isEmpty {
                        Text("例如：文字、品牌標誌、尖銳牙齒")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $avoid)
                        .frame(minHeight: 76)
                        .accessibilityLabel("不要出現")
                        .accessibilityIdentifier("hatch.avoid")
                }

                CharacterCount(value: trimmedAvoidCount, limit: 160)
            }

            Section("視覺風格") {
                Picker("風格", selection: $stylePreset) {
                    ForEach(HatchStylePreset.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .accessibilityIdentifier("hatch.style")

                Text(stylePreset.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("這一版會做什麼") {
                Label("只儲存在這台 iPhone", systemImage: "lock.shield.fill")
                    .foregroundStyle(.blue)
                Text("尚未送出、未排隊、未生成圖片，也不會改變目前外觀。Toma Gateway 上線後，送出前會再次詢問你。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct HatchReviewForm: View {
    let review: LocalHatchReview

    var body: some View {
        Form {
            Section {
                HatchReviewCard(review: review)
            }

            Section("這份設計單綁定") {
                LabeledContent("基礎 Pet", value: review.petPreset.defaultName)
                LabeledContent("目標階段", value: review.targetStage.title)
                LabeledContent("視覺風格", value: review.stylePreset.displayName)
                LabeledContent(
                    "外觀版本",
                    value: "v\(review.baseVersion) → v\(review.expectedNextVersion)"
                )
            }

            Section("外觀願望") {
                Text(review.appearance)
            }

            if let avoid = review.avoid {
                Section("不要出現") {
                    Text(avoid)
                }
            }

            Section("確認後") {
                Label("只儲存在這台 iPhone", systemImage: "lock.shield.fill")
                    .foregroundStyle(.blue)
                Text("未上傳、未排隊、未生成圖片，也不會切換目前外觀。Gateway 上線後，送出與啟用都會再請你確認。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct HatchStyleDirectionCard: View {
    let petPreset: PetPreset
    let stage: PetStage
    let style: HatchStylePreset

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: petPreset.symbolName)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(petPreset.tint)
                .frame(width: 72, height: 72)
                .background(petPreset.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 22))

            VStack(alignment: .leading, spacing: 4) {
                Text("\(petPreset.defaultName) 的外觀方向")
                    .font(.headline)
                Text(style.displayName)
                    .foregroundStyle(style.tint)
                Text("\(stage.title)・這不是生成後的 Pet 圖片")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hatch.styleDirection")
    }
}

private struct HatchReviewCard: View {
    let review: LocalHatchReview

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: review.petPreset.symbolName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(review.petPreset.tint)
                .frame(width: 76, height: 76)
                .background(
                    review.stylePreset.tint.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 24)
                )

            VStack(alignment: .leading, spacing: 5) {
                Label("Hatch 設計單", systemImage: "checklist.checked")
                    .font(.headline)
                Text("\(review.petPreset.defaultName) × \(review.stylePreset.displayName)")
                    .foregroundStyle(review.petPreset.tint)
                Text("這是文字方向，不是生成後的 Pet 圖片。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("hatch.review.summary")
    }
}

private struct CharacterCount: View {
    let value: Int
    let limit: Int
    var minimum: Int = 0

    private var isValid: Bool {
        value <= limit && value >= minimum
    }

    var body: some View {
        HStack {
            if minimum > 0, value < minimum {
                Text("至少 \(minimum) 個字")
            }
            Spacer()
            Text("\(value)/\(limit)")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(isValid ? Color.secondary : Color.red)
        .accessibilityElement(children: .combine)
    }
}

private extension HatchStylePreset {
    var tint: Color {
        switch self {
        case .auto: .indigo
        case .pixel: .purple
        case .plush: .pink
        case .clay: .orange
        case .sticker: .blue
        }
    }
}
