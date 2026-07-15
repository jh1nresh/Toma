import SwiftUI
import UIKit

struct PetSpriteView: View {
    let name: String
    let preset: PetPreset
    let activity: PetActivity
    let stage: PetStage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: SpriteAnimation {
        switch activity {
        case .idle: .init(row: 0, frameCount: 7, secondsPerFrame: 0.42)
        case .listening: .init(row: 3, frameCount: 4, secondsPerFrame: 0.24)
        case .working: .init(row: 7, frameCount: 6, secondsPerFrame: 0.16)
        case .waitingForApproval: .init(row: 6, frameCount: 6, secondsPerFrame: 0.34)
        case .celebrating: .init(row: 4, frameCount: 5, secondsPerFrame: 0.18)
        case .failed: .init(row: 5, frameCount: 8, secondsPerFrame: 0.3)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: animation.secondsPerFrame, paused: reduceMotion)) { timeline in
            let frame = reduceMotion ? 0 : animation.frame(at: timeline.date)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [preset.tint.opacity(0.22), preset.tint.opacity(0.03)],
                            center: .center,
                            startRadius: 12,
                            endRadius: 104
                        )
                    )
                    .frame(width: 202, height: 202)
                    .scaleEffect(stage.scale)

                Ellipse()
                    .fill(.black.opacity(0.1))
                    .frame(width: 132, height: 22)
                    .blur(radius: 5)
                    .offset(y: 84)

                if let image = SpriteAtlas.frame(row: animation.row, column: frame) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 190, height: 206)
                        .scaleEffect(stage.scale)
                } else {
                    Image(systemName: "bird.fill")
                        .font(.system(size: 92))
                        .foregroundStyle(preset.tint)
                }

                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: preset.symbolName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(preset.tint)
                            .frame(width: 38, height: 38)
                            .background(.regularMaterial, in: Circle())
                    }
                    Spacer()
                }
                .frame(width: 208, height: 208)
                .padding(.top, 8)
            }
            .frame(height: 220)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)，\(preset.defaultName)，\(stage.title)，\(activity.label)")
    }
}

private struct SpriteAnimation {
    let row: Int
    let frameCount: Int
    let secondsPerFrame: TimeInterval

    func frame(at date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate / secondsPerFrame) % frameCount
    }
}

private enum SpriteAtlas {
    private static let cellWidth = 192
    private static let cellHeight = 208

    private static let rows: [[CGImage]] = {
        guard let source = UIImage(named: "pet-sprites")?.cgImage else { return [] }
        return (0..<11).map { row in
            (0..<8).compactMap { column in
                source.cropping(
                    to: CGRect(
                        x: column * cellWidth,
                        y: row * cellHeight,
                        width: cellWidth,
                        height: cellHeight
                    )
                )
            }
        }
    }()

    static func frame(row: Int, column: Int) -> CGImage? {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return nil }
        return rows[row][column]
    }
}
