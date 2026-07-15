import SwiftUI

struct CustomHatchStatusSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var isConfirmingDeletion = false

    private var requestIsCurrent: Bool {
        store.snapshot.petProfile.localHatchRequestIsCurrent
    }

    private var statusText: String {
        requestIsCurrent
            ? "已儲存在本機・等待 Gateway"
            : "成長狀態已改變・請重新確認"
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
                .accessibilityIdentifier("hatch.create")

                Text("先用文字與風格描述牠。這一版只保存到本機，不會送出或生成圖片。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    init(request: LocalHatchRequest? = nil) {
        self.request = request
        _appearance = State(initialValue: request?.appearance ?? "")
        _avoid = State(initialValue: request?.avoid ?? "")
        _stylePreset = State(initialValue: request?.stylePreset ?? .auto)
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
        Form {
            Section {
                HatchStyleDirectionCard(style: stylePreset)
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
                        .accessibilityIdentifier("hatch.appearance")
                }

                CharacterCount(value: trimmedAppearance.count, limit: 280, minimum: 4)
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
                        .accessibilityIdentifier("hatch.avoid")
                }

                CharacterCount(value: trimmedAvoid.count, limit: 160)
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
        .navigationTitle(request == nil ? "自訂 Pet Hatch" : "編輯外觀願望")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(request == nil ? "儲存願望" : "儲存修改") {
                    let saved: Bool
                    if request == nil {
                        saved = store.saveLocalHatchRequest(
                            appearance: trimmedAppearance,
                            avoid: trimmedAvoid,
                            stylePreset: stylePreset
                        )
                    } else {
                        saved = store.updateLocalHatchRequest(
                            appearance: trimmedAppearance,
                            avoid: trimmedAvoid,
                            stylePreset: stylePreset
                        )
                    }
                    if saved { dismiss() }
                }
                .disabled(!canSave)
                .accessibilityIdentifier("hatch.save")
            }
        }
    }
}

private struct HatchStyleDirectionCard: View {
    let style: HatchStylePreset

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(style.tint)
                .frame(width: 72, height: 72)
                .background(style.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 22))

            VStack(alignment: .leading, spacing: 4) {
                Text("風格方向示意")
                    .font(.headline)
                Text(style.displayName)
                    .foregroundStyle(style.tint)
                Text("這不是生成後的 Pet 圖片")
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
