import Foundation

protocol SnapshotPersisting {
    func load() throws -> AppSnapshot?
    func save(_ snapshot: AppSnapshot) throws
}

struct JSONSnapshotStore: SnapshotPersisting {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = support
                .appendingPathComponent("Toma", isDirectory: true)
                .appendingPathComponent("snapshot.json")
        }

        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func load() throws -> AppSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try decoder.decode(AppSnapshot.self, from: Data(contentsOf: fileURL))
    }

    func save(_ snapshot: AppSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(snapshot).write(
            to: fileURL,
            options: [.atomic, .completeFileProtection]
        )
    }
}
