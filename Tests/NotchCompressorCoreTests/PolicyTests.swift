import XCTest
@testable import NotchCompressorCore

func fixture(audio: Bool = true, pixel: String = "yuv420p", transfer: String = "bt709", extra: String = "") -> Data {
    Data("""
    {"streams":[{"index":0,"codec_type":"video","codec_name":"h264","width":1920,"height":1080,"pix_fmt":"\(pixel)","color_transfer":"\(transfer)","avg_frame_rate":"60/1","bit_rate":"8000000"}\(audio ? ",{\"index\":1,\"codec_type\":\"audio\",\"codec_name\":\"aac\",\"channels\":2,\"bit_rate\":\"192000\"}" : "")\(extra)],"format":{"duration":"10.0","format_name":"mov,mp4,m4a,3gp,3g2,mj2"}}
    """.utf8)
}

final class PolicyTests: XCTestCase {
    func testEveryModePreservesUnselectedCodec() throws {
        let media = try MediaInfo.decode(fixture(), fileSize: 10_000_000)
        for mode in CompressionMode.allCases {
            let plan = try CompressionPlan(media: media, mode: mode, quality: .balanced)
            let args = plan.arguments(input: URL(fileURLWithPath: "/tmp/a ; $(touch hacked).mov"), output: URL(fileURLWithPath: "/tmp/out.mov"))
            XCTAssertEqual(args[args.firstIndex(of: "-c:v")! + 1], mode == .audio ? "copy" : "hevc_videotoolbox")
            XCTAssertEqual(args[args.firstIndex(of: "-c:a")! + 1], mode == .video ? "copy" : "aac")
            XCTAssertTrue(args.contains("/tmp/a ; $(touch hacked).mov"))
            XCTAssertTrue(args.contains("-n"))
            XCTAssertEqual(args.contains("fps=30"), mode.changesVideo)
        }
    }

    func testSilentVideoContract() throws {
        let media = try MediaInfo.decode(fixture(audio: false), fileSize: 1000)
        XCTAssertThrowsError(try CompressionPlan(media: media, mode: .audio, quality: .balanced))
        XCTAssertNotNil(try CompressionPlan(media: media, mode: .both, quality: .balanced).note)
        XCTAssertNoThrow(try CompressionPlan(media: media, mode: .video, quality: .balanced))
    }

    func testHDRMayOnlyCopyVideo() throws {
        let media = try MediaInfo.decode(fixture(pixel: "yuv420p10le", transfer: "smpte2084"), fileSize: 1000)
        XCTAssertThrowsError(try CompressionPlan(media: media, mode: .video, quality: .balanced))
        XCTAssertNoThrow(try CompressionPlan(media: media, mode: .audio, quality: .balanced))
    }

    func testRejectsSubtitleRatherThanDroppingIt() {
        XCTAssertThrowsError(try MediaInfo.decode(fixture(extra: ",{\"index\":2,\"codec_type\":\"subtitle\"}"), fileSize: 1000))
    }

    func testRejectsInvalidDurationAndMalformedJSON() {
        let invalid = String(data: fixture(), encoding: .utf8)!.replacingOccurrences(of: "10.0", with: "nan")
        XCTAssertThrowsError(try MediaInfo.decode(Data(invalid.utf8), fileSize: 1000))
        XCTAssertThrowsError(try MediaInfo.decode(Data("not JSON".utf8), fileSize: 1000))
    }

    func testQualityOrdersVideoAndAudioBudgets() throws {
        let media = try MediaInfo.decode(fixture(), fileSize: 1000)
        let budgets = try CompressionQuality.allCases.map { try CompressionPlan(media: media, mode: .both, quality: $0).videoBitrate }
        XCTAssertGreaterThan(budgets[0], budgets[1])
        XCTAssertGreaterThan(budgets[1], budgets[2])
    }

    func testMissingExplicitToolsDoesNotSilentlyFallback() {
        XCTAssertThrowsError(try Toolchain.discover(directory: "/nonexistent/NotchCompressor"))
    }

    func testRejectsDirectoryAndRemoteURL() throws {
        XCTAssertThrowsError(try InputFile.validate(URL(string: "https://example.com/movie.mov")!))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertThrowsError(try InputFile.validate(folder))
    }
}
