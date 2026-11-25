import Foundation

struct ImageCompressionEngine {
    func compress(
        input: URL, mode: CompressionMode, settings: CompressionSettings,
        update: @escaping @Sendable (JobPhase, Double, String?) -> Void
    ) async throws -> CompressionResult {
        guard MediaKind.image.accepts(mode) else {
            throw CompressionError.localized(.init("error.mediaMode", MediaKind.image.title))
        }
        let size = try InputFile.validate(input, extensions: ["jpg", "jpeg", "png"])
        let worker = try Self.workerURL()
        let transaction = try OutputTransaction(source: input, estimatedBytes: Double(size) * 2 + 64 * 1024 * 1024)
        defer { transaction.cleanUp() }
        try await CompressionControl.current?.checkpoint()
        update(.encoding, 0, nil)
        let data = try await ProcessRunner().run(
            executable: worker,
            arguments: [input.path, transaction.output.path, String(settings.effectiveImageQuality / 100.0)],
            timeout: 600)
        let response = try JSONDecoder().decode(ImageWorkerResponse.self, from: data)
        if let error = response.error { throw CompressionError.localized(error) }
        try Task.checkCancellation()
        try await CompressionControl.current?.checkpoint()
        update(.validating, 1, nil)
        // The helper returns success only after decoding and validating the output.
        return try await transaction.commit()
    }

    static func workerURL() throws -> URL {
        let path: URL
        if Bundle.main.bundleURL.pathExtension == "app" {
            path = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/NotchImageWorker")
        } else if let override = ProcessInfo.processInfo.environment["NOTCH_IMAGE_WORKER"] {
            path = URL(fileURLWithPath: override)
        } else {
            path = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent(
                "NotchImageWorker")
        }
        guard FileManager.default.isExecutableFile(atPath: path.path) else {
            throw CompressionError.localized(.init("error.imageHelper"))
        }
        return path
    }
}
