import Foundation

/// A current observation, never a saved permission or preferred destination.
public struct LowSpaceDisk: Identifiable, Equatable, Sendable {
    public var id: String { uuid }
    public let root: URL
    public let name: String
    public let uuid: String
    public let storageGroup: String
    public let availableBytes: Int64

    public static func requiredBytes(for source: URL, estimatedOutput: Int64?) throws -> Int64 {
        let size = Int64(clamping: try Fingerprint(source).size)
        let output = max(size, estimatedOutput ?? size)
        return Int64(min(Double(size) + Double(output) + 64 * 1024 * 1024, Double(Int64.max - 1024)))
    }

    public static func candidates(for source: URL, requiredBytes: Int64) -> [LowSpaceDisk] {
        let roots =
            FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes])
            ?? []
        return roots.compactMap { try? inspect($0, source: source, requiredBytes: requiredBytes) }
            .sorted { $0.availableBytes > $1.availableBytes }
    }

    public static func inspect(_ folder: URL, source: URL, requiredBytes: Int64) throws -> LowSpaceDisk {
        let values = try folder.resourceValues(forKeys: [
            .volumeURLKey, .volumeNameKey, .volumeUUIDStringKey, .volumeIsInternalKey,
            .volumeIsLocalKey, .volumeIsReadOnlyKey,
        ])
        guard values.volumeIsInternal == false, values.volumeIsLocal == true,
            values.volumeIsReadOnly == false, let root = values.volume,
            let uuid = values.volumeUUIDString,
            let available = try DiskSpaceIssue.availableCapacity(in: root)
        else { throw CompressionError.localized(.init("lowSpace.unsuitable")) }
        guard let sourceRoot = try source.deletingLastPathComponent().resourceValues(forKeys: [.volumeURLKey]).volume
        else {
            throw CompressionError.localized(.init("lowSpace.unverifiedDisk"))
        }
        let sourceGroup = try storageGroup(for: sourceRoot)
        let destinationGroup = try storageGroup(for: root, requirePhysical: true)
        guard sourceGroup != destinationGroup else { throw CompressionError.localized(.init("lowSpace.sameDisk")) }
        guard available >= requiredBytes else {
            throw DiskSpaceIssue(availableBytes: available, requiredBytes: requiredBytes)
        }
        return LowSpaceDisk(
            root: root, name: values.volumeName ?? root.lastPathComponent, uuid: uuid,
            storageGroup: destinationGroup, availableBytes: available)
    }

    /// APFS sibling volumes share capacity; different mount paths are not sufficient.
    private static func storageGroup(for url: URL, requirePhysical: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", url.path]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        defer { timeout.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
            let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let group = (info["APFSContainerReference"] ?? info["ParentWholeDisk"]) as? String
        else { throw CompressionError.localized(.init("lowSpace.unverifiedDisk")) }
        if requirePhysical {
            guard let bus = info["BusProtocol"] as? String,
                !bus.lowercased().replacingOccurrences(of: " ", with: "").contains("diskimage")
            else {
                throw CompressionError.localized(.init("lowSpace.unsuitable"))
            }
        }
        return group
    }
}

public struct LowSpaceWorkspace: Sendable {
    public let folder: URL
    public let volumeUUID: String
    public let recoveryDirectory: URL
    public init(folder: URL, volumeUUID: String, recoveryDirectory: URL) {
        self.folder = folder; self.volumeUUID = volumeUUID; self.recoveryDirectory = recoveryDirectory
    }
    @TaskLocal static var current: LowSpaceWorkspace?
}
