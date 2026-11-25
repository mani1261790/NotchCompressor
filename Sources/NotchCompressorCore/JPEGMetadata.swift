import Foundation

/// Preserve APP/COM segments byte-for-byte rather than relying on an encoder to
/// interpret and rewrite EXIF, maker notes, ICC, IPTC or XMP tags.
enum JPEGMetadata {
    private struct Parts {
        var metadata = Data()
        var codestream = Data([0xff, 0xd8])
    }
    static func preserving(from original: Data, in encoded: Data) throws -> Data {
        let before = try split(original)
        let after = try split(encoded)
        return Data([0xff, 0xd8]) + before.metadata + after.codestream.dropFirst(2)
    }
    static func validate(_ original: Data, _ output: Data) throws {
        guard try split(original).metadata == split(output).metadata else {
            throw CompressionError.localized(.init("error.imagePreservation"))
        }
    }
    private static func split(_ data: Data) throws -> Parts {
        func fail() -> CompressionError { .localized(.init("error.imageStructure")) }
        guard data.count > 4, data[0] == 0xff, data[1] == 0xd8 else { throw fail() }
        var result = Parts(), index = 2, scans = 0
        while index < data.count {
            let start = index
            guard data[index] == 0xff else { throw fail() }
            while index < data.count && data[index] == 0xff { index += 1 }
            guard index < data.count else { throw fail() }
            let marker = data[index]
            index += 1
            if marker == 0xd9 {
                guard index == data.count, scans > 0 else { throw fail() }
                result.codestream.append(contentsOf: data[start..<index])
                return result
            }
            guard marker != 0xd8, marker != 0x00, !(0xd0...0xd7).contains(marker), index + 2 <= data.count else {
                throw fail()
            }
            let length = Int(data[index]) * 256 + Int(data[index + 1])
            guard length >= 2, length <= data.count - index else { throw fail() }
            let end = index + length
            let metadata = (0xe0...0xef).contains(marker) || marker == 0xfe
            if metadata {
                let payload = Data(data[index + 2..<end])
                // Unknown application blocks may contain offsets into encoded data.
                // Do not claim to preserve such a format by copying stale offsets.
                let known: Bool
                switch marker {
                case 0xe0:
                    known = payload.starts(with: Data("JFIF\0".utf8)) || payload.starts(with: Data("JFXX\0".utf8))
                case 0xe1:
                    known =
                        payload.starts(with: Data("Exif\0\0".utf8))
                        || payload.starts(with: Data("http://ns.adobe.com/".utf8))
                case 0xe2: known = payload.starts(with: Data("ICC_PROFILE\0".utf8))
                case 0xed: known = payload.starts(with: Data("Photoshop 3.0\0".utf8))
                case 0xfe: known = true
                default: known = false
                }
                guard known else { throw fail() }
                result.metadata.append(contentsOf: data[start..<end])
            } else {
                result.codestream.append(contentsOf: data[start..<end])
            }
            index = end
            if marker == 0xda {
                scans += 1
                let entropyStart = index
                while index + 1 < data.count {
                    if data[index] != 0xff { index += 1; continue }
                    let next = data[index + 1]
                    if next == 0 || (0xd0...0xd7).contains(next) { index += 2; continue }
                    break
                }
                result.codestream.append(contentsOf: data[entropyStart..<index])
            }
        }
        throw fail()
    }
}
