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
