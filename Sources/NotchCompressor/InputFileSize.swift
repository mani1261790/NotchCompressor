import Foundation
import SwiftUI
import NotchCompressorCore

/// Read filesystem metadata only. Never open media or request cloud hydration
/// merely to show a queue row. Missing metadata is distinct from a zero-byte file.
struct InputFileSize: View {
    let url: URL
    @State private var size: Int64?

    var body: some View {
        Text(size.map(L10n.bytes) ?? L10n.text("queue.sizeUnknown"))
            .monospacedDigit()
            .accessibilityLabel(
                size.map { L10n.text("queue.inputSize", L10n.bytes($0)) }
                    ?? L10n.text("queue.sizeUnknown")
            )
            .task(id: url) {
                size = nil
                let input = url
                let value = await Task.detached(priority: .utility) {
                    guard
                        let values = try? input.resourceValues(forKeys: [
                            .isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey,
                            .ubiquitousItemDownloadingStatusKey,
                        ]), values.isRegularFile == true
                    else { return Int64?.none }
                    if values.isUbiquitousItem == true,
                        values.ubiquitousItemDownloadingStatus != .current,
                        values.ubiquitousItemDownloadingStatus != .downloaded
                    {
                        return nil
                    }
                    return values.fileSize.map(Int64.init)
                }.value
                guard !Task.isCancelled else { return }
                size = value
            }
    }
}
