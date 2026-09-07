import AppKit
import QuickLookThumbnailing
import SwiftUI

/// File content identifies the movie; compression mode is metadata in the row.
struct VideoThumbnail: View {
    let urls: [URL]
    @Environment(\.displayScale) private var scale
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                VStack(spacing: 3) {
                    Image(systemName: "film").font(.title3)
                    Text(urls.first?.pathExtension.uppercased() ?? "VIDEO")
                        .font(.system(size: 9, weight: .semibold))
                }.foregroundStyle(.secondary)
            }
        }
        .frame(width: 88, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
        .task(id: urls) {
            image = nil
            for url in urls {
                guard !Task.isCancelled else { return }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]), values.isRegularFile == true else { continue }
                // Merely viewing history must not initiate an iCloud download.
                if values.isUbiquitousItem == true,
                   values.ubiquitousItemDownloadingStatus != .current,
                   values.ubiquitousItemDownloadingStatus != .downloaded { continue }
                let request = QLThumbnailGenerator.Request(fileAt: url,
                    size: CGSize(width: 88, height: 56), scale: scale,
                    representationTypes: .thumbnail)
                let thumbnail = try? await withTaskCancellationHandler {
                    try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                } onCancel: {
                    QLThumbnailGenerator.shared.cancel(request)
                }
                guard !Task.isCancelled else { return }
                if let thumbnail {
                    image = thumbnail.nsImage
                    return
                }
            }
        }
    }
}
