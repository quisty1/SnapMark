import AppKit
import Observation

public struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID; public let date: Date; public let width: Int; public let height: Int
    public var file: String { "\(id.uuidString).png" }
    public var thumbnail: String { "\(id.uuidString)-thumb.png" }
}
@MainActor @Observable public final class HistoryStore {
    public let directory: URL
    public private(set) var entries: [HistoryEntry] = []
    private struct Index: Codable { let version: Int; let entries: [HistoryEntry] }
    public init(directory: URL) throws {
        self.directory = directory; try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("index.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let index = try JSONDecoder().decode(Index.self,from: Data(contentsOf: url))
            guard index.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            entries = index.entries.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.file).path) }
        }
    }
    public func imageURL(_ entry: HistoryEntry) -> URL { directory.appendingPathComponent(entry.file) }
    public func thumbnailURL(_ entry: HistoryEntry) -> URL { directory.appendingPathComponent(entry.thumbnail) }
    public func add(image: CGImage, limit: Int) throws {
        let entry = HistoryEntry(id: UUID(),date: Date(),width: image.width,height: image.height)
        let file = imageURL(entry), thumb = thumbnailURL(entry)
        do {
            try ImageRenderer.png(image).write(to: file,options: .atomic)
            try ImageRenderer.png(ImageRenderer.thumbnail(image)).write(to: thumb,options: .atomic)
            let next = Array(([entry]+entries).prefix(max(1,limit)))
            try writeIndex(next)
            let removed = entries.filter { old in !next.contains(where: { $0.id == old.id }) }
            entries = next
            for old in removed { removeFiles(old) }
        } catch {
            try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: thumb); throw error
        }
    }
    public func delete(_ entry: HistoryEntry) throws {
        let next = entries.filter { $0.id != entry.id }; try writeIndex(next); entries = next; removeFiles(entry)
    }
    public func trim(limit: Int) throws {
        let next = Array(entries.prefix(max(1,limit))); let removed = entries.dropFirst(next.count)
        try writeIndex(next); entries = next; for entry in removed { removeFiles(entry) }
    }
    public func clear() throws { try writeIndex([]); let old = entries; entries = []; for entry in old { removeFiles(entry) } }
    private func writeIndex(_ values: [HistoryEntry]) throws {
        try JSONEncoder().encode(Index(version: 1,entries: values)).write(to: directory.appendingPathComponent("index.json"),options: .atomic)
    }
    private func removeFiles(_ entry: HistoryEntry) {
        try? FileManager.default.removeItem(at: imageURL(entry)); try? FileManager.default.removeItem(at: thumbnailURL(entry))
    }
}
