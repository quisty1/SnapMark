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
    private var pendingDeletions: [HistoryEntry] = []
    public var pendingDeletionCount: Int { pendingDeletions.count }
    private struct Index: Codable { let version: Int; let entries: [HistoryEntry]; let pendingDeletions: [HistoryEntry]? }
    public init(directory: URL) throws {
        self.directory = directory; try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("index.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let index = try JSONDecoder().decode(Index.self,from: Data(contentsOf: url))
            guard index.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            entries = index.entries.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.file).path) }
            pendingDeletions = index.pendingDeletions ?? []
            try? retryPendingDeletions()
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
            let removed = entries.filter { old in !next.contains(where: { $0.id == old.id }) }
            let pending = pendingDeletions+removed
            try writeIndex(next,pending: pending)
            entries = next; pendingDeletions = pending
        } catch {
            try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: thumb); throw error
        }
        // Cleanup failure never invalidates a successfully recorded screenshot.
        try? retryPendingDeletions()
    }
    public func delete(_ entry: HistoryEntry) throws {
        try updateRemoving(entries.filter { $0.id != entry.id },removed: [entry])
    }
    public func trim(limit: Int) throws {
        let next = Array(entries.prefix(max(1,limit)))
        try updateRemoving(next,removed: Array(entries.dropFirst(next.count)))
    }
    public func clear() throws { try updateRemoving([],removed: entries) }
    private func updateRemoving(_ next: [HistoryEntry],removed: [HistoryEntry]) throws {
        let pending = pendingDeletions+removed
        try writeIndex(next,pending: pending); entries = next; pendingDeletions = pending
        try retryPendingDeletions()
    }
    public func retryPendingDeletions() throws {
        guard !pendingDeletions.isEmpty else { return }
        var remaining: [HistoryEntry] = [], firstError: (any Error)?
        for entry in pendingDeletions {
            do {
                for url in [imageURL(entry),thumbnailURL(entry)] where FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } catch { remaining.append(entry); if firstError == nil { firstError = error } }
        }
        try writeIndex(entries,pending: remaining); pendingDeletions = remaining
        if let firstError { throw firstError }
    }
    private func writeIndex(_ values: [HistoryEntry],pending: [HistoryEntry]) throws {
        try JSONEncoder().encode(Index(version: 1,entries: values,pendingDeletions: pending)).write(to: directory.appendingPathComponent("index.json"),options: .atomic)
    }
}
