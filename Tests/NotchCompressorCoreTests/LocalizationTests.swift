import XCTest
@testable import NotchCompressorCore

final class LocalizationTests: XCTestCase {
    func testLanguageSelectionAndExplicitMessages() throws {
        XCTAssertEqual(L10n.resolveLanguage(["en-GB", "ja"]), "en")
        XCTAssertEqual(L10n.resolveLanguage(["ja-JP", "en"]), "ja")
        XCTAssertEqual(L10n.resolveLanguage(["de-DE"]), "en")
        let message = LocalizedMessage("summary.audio", "80")
        let data = try JSONEncoder().encode(message)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("音声"))
        let restored = try JSONDecoder().decode(LocalizedMessage.self, from: data)
        L10n.$languageOverride.withValue("en") {
            XCTAssertEqual(CompressionMode.both.title, "Video and audio")
            XCTAssertEqual(restored.text, "Audio 80 kbps")
            XCTAssertEqual(QueueExecution.serial.title, "One at a time")
            XCTAssertEqual(JobPhase.validating.title, "Validating output")
            XCTAssertTrue(FailureNotice(diskSpaceIssue: .init()).body.contains("Check the free space"))
            var notice = CompletionNotice()
            notice.include(
                .init(
                    output: URL(fileURLWithPath: "/tmp/a.mov"), originalBytes: 1000, outputBytes: 1000,
                    note: nil, outcome: .originalKept))
            XCTAssertTrue(notice.text.hasPrefix("Completed: 1"))
            XCTAssertTrue(notice.text.contains("Originals kept without size reduction: 1"))
            XCTAssertFalse(notice.text.contains("件"))
        }
        L10n.$languageOverride.withValue("ja") {
            XCTAssertEqual(CompressionMode.both.title, "画質＋音質")
            XCTAssertEqual(restored.text, "音声80 kbps")
            XCTAssertEqual(JobPhase.validating.title, "出力を検証中")
            XCTAssertTrue(FailureNotice(diskSpaceIssue: .init()).body.contains("空き容量"))
        }
    }

    @MainActor
    func testQueueHistoryRendersInCurrentLanguageWithoutMixingLegacyText() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = folder.appendingPathComponent("queue.json")
        await L10n.$languageOverride.withValue("ja") {
            let queue = JobQueue(
                storage: storage,
                operation: { _, _, _, _ in
                    throw CompressionError.localized(.init("error.process", "7"), details: "original diagnostic")
                })
            queue.enqueue([folder.appendingPathComponent("source.mov")], mode: .both)
            await queue.waitUntilIdle()
            XCTAssertTrue(queue.jobs[0].displayMessage?.contains("変換ツール") == true)
            XCTAssertNil(queue.jobs[0].message)
        }
        L10n.$languageOverride.withValue("en") {
            let job = JobQueue(storage: storage).jobs[0]
            XCTAssertEqual(job.displayMessage, "The compression engine failed (exit code: 7). Check the details.")
            XCTAssertEqual(job.displayDetails, "original diagnostic")
            var old = CompressionJob(input: folder.appendingPathComponent("legacy.mov"), mode: .both, settings: .init())
            old.phase = .failed
            old.message = "以前の日本語エラー"
            XCTAssertEqual(
                old.displayMessage, "This message was recorded by an earlier version. Open the details if needed.")
            XCTAssertEqual(old.displayDetails, "以前の日本語エラー")
            XCTAssertFalse(CompressionError.message("日本語の生エラー").localizedDescription.contains("日本語"))
        }
    }

    func testCatalogsHaveMatchingKeysAndPlaceholders() throws {
        func catalog(_ language: String) throws -> [String: String] {
            let url = try XCTUnwrap(L10n.bundle(language).url(forResource: "Localizable", withExtension: "strings"))
            return try XCTUnwrap(
                PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
        }
        let en = try catalog("en"), ja = try catalog("ja")
        XCTAssertGreaterThan(en.count, 50)
        XCTAssertEqual(Set(en.keys), Set(ja.keys))
        for key in en.keys {
            let english = try XCTUnwrap(en[key]), japanese = try XCTUnwrap(ja[key])
            XCTAssertEqual(
                english.components(separatedBy: "%@").count, japanese.components(separatedBy: "%@").count, key)
            XCTAssertNil(english.range(of: "[ぁ-んァ-ヶ一-龠]", options: .regularExpression), key)
            XCTAssertFalse(english.isEmpty)
            XCTAssertFalse(japanese.isEmpty)
        }
    }
}
