import SwiftUI

struct PetPresetPicker: View {
    @Binding var selection: PetPreset

    var body: some View {
        ForEach(PetPreset.allCases) { preset in
            Button {
                selection = preset
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: preset.symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(preset.tint)
                        .frame(width: 46, height: 46)
                        .background(preset.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 15))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.defaultName)
                            .font(.headline)
                        Text(preset.role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: selection == preset ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selection == preset ? preset.tint : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(preset.defaultName)，\(preset.role)")
            .accessibilityValue(selection == preset ? "已選擇" : "未選擇")
            .accessibilityIdentifier("pet.preset.\(preset.rawValue)")
        }
    }
}

struct PetEvolutionPath: View {
    let currentStage: PetStage
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(PetStage.allCases, id: \.rawValue) { stage in
                VStack(spacing: 6) {
                    Image(systemName: symbol(for: stage))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(stage.rawValue <= currentStage.rawValue ? .white : .secondary)
                        .frame(width: 34, height: 34)
                        .background(
                            stage.rawValue <= currentStage.rawValue ? tint : Color.secondary.opacity(0.14),
                            in: Circle()
                        )

                    Text(stage.shortTitle)
                        .font(.caption.weight(stage == currentStage ? .semibold : .regular))
                    Text(stage.xpLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(stage.title)，\(stage.xpLabel)")
                .accessibilityValue(stage == currentStage ? "目前階段" : "")
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("pet.evolutionPath")
    }

    private func symbol(for stage: PetStage) -> String {
        if stage == currentStage { return "pawprint.fill" }
        return stage.rawValue < currentStage.rawValue ? "checkmark" : "lock.fill"
    }
}

extension PetPreset {
    var symbolName: String {
        switch self {
        case .sprout: "leaf.fill"
        case .spark: "sparkles"
        case .cloud: "cloud.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sprout: Color(red: 0.22, green: 0.62, blue: 0.38)
        case .spark: Color(red: 0.93, green: 0.43, blue: 0.16)
        case .cloud: Color(red: 0.31, green: 0.52, blue: 0.83)
        }
    }
}

private extension PetStage {
    var shortTitle: String {
        switch self {
        case .hatchling: "初生"
        case .companion: "默契"
        case .guardian: "守護"
        }
    }

    var xpLabel: String {
        switch self {
        case .hatchling: "0–19 XP"
        case .companion: "20–59 XP"
        case .guardian: "60+ XP"
        }
    }
}
