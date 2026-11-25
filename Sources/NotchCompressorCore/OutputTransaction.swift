import Foundation

/// Same-folder staging and guarded replacement shared by all media engines.
struct OutputTransaction {
    let source: URL
    let fingerprint: Fingerprint
    let staging: URL
    let output: URL

    init(source: URL, estimatedBytes: Double, expected: Fingerprint? = nil) throws {
        self.source = source
        fingerprint = try Fingerprint(source)
        if let expected, expected != fingerprint { throw CompressionError.localized(.init("error.changedRetry")) }
        let folder = source.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            throw CompressionError.localized(.init("error.folder"))
        }
        if let capacity = try DiskSpaceIssue.availableCapacity(in: folder), Double(capacity) < estimatedBytes {
            throw DiskSpaceIssue(
                availableBytes: max(0, capacity),
                requiredBytes: Int64(min(estimatedBytes.rounded(.up), Double(Int64.max - 1024))))
        }
        staging = folder.appendingPathComponent(".notchcompressor-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        output = staging.appendingPathComponent("output." + source.pathExtension.lowercased())
    }

    func cleanUp() { try? FileManager.default.removeItem(at: staging) }

    func commit(note: String? = nil, noteMessage: LocalizedMessage? = nil) async throws -> CompressionResult {
        if let control = CompressionControl.current {
            while true {
                try await control.checkpoint()
                if let result = try control.commit({
                    try CompressionEngine.finalizeVerifiedOutput(
                        output, original: source, expected: fingerprint, note: note, noteMessage: noteMessage)
                }) {
                    return result
                }
            }
        }
        return try CompressionEngine.finalizeVerifiedOutput(
            output, original: source, expected: fingerprint, note: note, noteMessage: noteMessage)
    }
}
