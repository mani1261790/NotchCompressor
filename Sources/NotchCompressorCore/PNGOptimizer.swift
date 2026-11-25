import Foundation
import zlib

/// Recompress only IDAT. All ancillary chunks (color, text, EXIF, transparency)
/// and the exact filtered pixel stream are preserved, including 16-bit samples.
enum PNGOptimizer {
    private struct Chunk {
        let type: String
        let data: Data
        let encoded: Data
    }
    private static let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
    private static let maximumDecodedBytes = 256 * 1024 * 1024
    private static func fail() -> CompressionError { .localized(.init("error.imageStructure")) }
    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        data[offset..<offset + 4].reduce(0) { ($0 << 8) | UInt32($1) }
    }
    private static func bytes(_ value: UInt32) -> Data {
        Data([UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)])
    }
    private static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))) }
    }
    private static func parse(_ input: Data) throws -> [Chunk] {
        guard input.count >= 33, input.prefix(8) == signature else { throw fail() }
        var chunks: [Chunk] = [], offset = 8
        var sawIDAT = false, endedIDAT = false
        while offset + 12 <= input.count {
            let count = Int(uint32(input, offset))
            guard count <= input.count - offset - 12,
                let type = String(data: input[offset + 4..<offset + 8], encoding: .ascii)
            else { throw fail() }
            let end = offset + 12 + count
            let payload = Data(input[offset + 8..<end - 4])
            guard checksum(Data(input[offset + 4..<end - 4])) == uint32(input, end - 4) else { throw fail() }
            if ["acTL", "fcTL", "fdAT"].contains(type) {
                throw CompressionError.localized(.init("error.imageAnimation"))
            }
            if type == "IDAT" {
                guard !endedIDAT else { throw fail() }
                sawIDAT = true
            } else if sawIDAT {
                endedIDAT = true
            }
            if let first = type.utf8.first, first & 32 == 0, !["IHDR", "PLTE", "IDAT", "IEND"].contains(type) {
                throw fail()
            }
            chunks.append(.init(type: type, data: payload, encoded: Data(input[offset..<end])))
            offset = end
            if type == "IEND" { break }
        }
        guard offset == input.count, chunks.first?.type == "IHDR", chunks.first?.data.count == 13,
            chunks.filter({ $0.type == "IHDR" }).count == 1,
            chunks.last?.type == "IEND", chunks.last?.data.isEmpty == true, sawIDAT
        else { throw fail() }
        return chunks
    }

    static func optimize(_ input: Data) throws -> Data {
        let chunks = try parse(input)
        let header = chunks[0].data
        let width = Int(uint32(header, 0)), height = Int(uint32(header, 4))
        let depth = Int(header[8]), color = header[9]
        let channels: Int
        switch color {
        case 0: channels = 1
        case 2: channels = 3
        case 3: channels = 1
        case 4: channels = 2
        case 6: channels = 4
        default: throw fail()
        }
        guard width > 0, height > 0, width <= 32_768, height <= 32_768,
            [1, 2, 4, 8, 16].contains(depth), header[10] == 0, header[11] == 0, header[12] <= 1
        else { throw fail() }
        // Adam7 has at most seven per-row filter bytes; a conservative upper bound
        // avoids trusting an attacker-supplied uncompressed size.
        let limit = (width * channels * depth / 8 + 16) * height + 1024
        guard limit <= maximumDecodedBytes else { throw CompressionError.localized(.init("error.imageTooLarge")) }
        let compressed = chunks.filter { $0.type == "IDAT" }.reduce(into: Data()) { $0.append($1.data) }
        var decoded = Data(count: limit), decodedCount = uLongf(limit)
        let result = decoded.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { source in
                uncompress(
                    destination.bindMemory(to: Bytef.self).baseAddress, &decodedCount,
                    source.bindMemory(to: Bytef.self).baseAddress, uLong(compressed.count))
            }
        }
        guard result == Z_OK, decodedCount > 0 else { throw fail() }
        decoded.count = Int(decodedCount)
        var packedCount = compressBound(uLong(decoded.count))
        var packed = Data(count: Int(packedCount))
        let packedResult = packed.withUnsafeMutableBytes { destination in
            decoded.withUnsafeBytes { source in
                compress2(
                    destination.bindMemory(to: Bytef.self).baseAddress, &packedCount,
                    source.bindMemory(to: Bytef.self).baseAddress, uLong(decoded.count), Z_BEST_COMPRESSION)
            }
        }
        guard packedResult == Z_OK else { throw fail() }
        packed.count = Int(packedCount)
        // Verify the compressed stream, not a color-converted pixel comparison.
        var verified = Data(count: decoded.count), verifiedCount = uLongf(decoded.count)
        let verifiedResult = verified.withUnsafeMutableBytes { destination in
            packed.withUnsafeBytes { source in
                uncompress(
                    destination.bindMemory(to: Bytef.self).baseAddress, &verifiedCount,
                    source.bindMemory(to: Bytef.self).baseAddress, uLong(packed.count))
            }
        }
        guard verifiedResult == Z_OK, verifiedCount == decoded.count, verified == decoded else { throw fail() }
        var output = signature, inserted = false
        for chunk in chunks {
            if chunk.type != "IDAT" { output.append(chunk.encoded); continue }
            guard !inserted else { continue }
            inserted = true
            let body = Data("IDAT".utf8) + packed
            output.append(bytes(UInt32(packed.count)))
            output.append(body)
            output.append(bytes(checksum(body)))
        }
        return output
    }
}
