import Foundation

public struct DiskSpaceIssue: LocalizedError, Codable, Equatable, Sendable {
    public let availableBytes: Int64?
    public let requiredBytes: Int64?

    public init(availableBytes: Int64? = nil, requiredBytes: Int64? = nil) {
        self.availableBytes = availableBytes
        self.requiredBytes = requiredBytes
    }
    public var additionalBytes: Int64? {
        guard let availableBytes, let requiredBytes else { return nil }
        return max(0, requiredBytes - availableBytes)
    }
    public var errorDescription: String? {
        var lines = [availableBytes == nil ? "保存先またはMacの一時領域の空き容量が不足しました。" : "元動画があるディスクの空き容量が不足しています。"]
        if let availableBytes, let requiredBytes, let additionalBytes {
            let format = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            lines.append(
                "空き：\(format(availableBytes)) ／ 必要な空きの目安：\(format(requiredBytes)) ／ あと約\(format(additionalBytes))必要")
        }
        lines.append("安全に置き換えるため、元動画を残したまま圧縮後の一時ファイルを同じディスクに作ります。元動画は置き換えていません。")
        lines.append("① 同じディスクの不要なファイルを別ディスクへ移すか、不要と確認したものを削除し、必要に応じてゴミ箱を空にしてください。その後「再試行」できます。")
        lines.append("② 空きを作れない場合は、空きのある外付けディスクへ動画を移し、このタスクをキューから外して移動先の動画を追加してください。同じディスク内でフォルダを変えても空きは増えません。")
        lines.append("必要量は目安です。ほかのアプリや同時処理でも空き容量が変わります。")
        return lines.joined(separator: "\n\n")
    }

    public static func classify(_ error: Error) -> DiskSpaceIssue? {
        if let issue = error as? DiskSpaceIssue { return issue }
        var current = error as NSError
        for _ in 0..<8 {
            if (current.domain == NSPOSIXErrorDomain && current.code == Int(ENOSPC))
                || (current.domain == NSCocoaErrorDomain && current.code == CocoaError.fileWriteOutOfSpace.rawValue)
            {
                return DiskSpaceIssue()
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = underlying
        }
        return nil
    }
}
