import AppKit
import SwiftUI
import NotchCompressorCore

struct LowSpaceWorkspaceView: View {
    let job: CompressionJob
    @ObservedObject var queue: JobQueue
    @Environment(\.dismiss) private var dismiss
    @State private var disks: [LowSpaceDisk] = []
    @State private var selection: LowSpaceDisk?
    @State private var folder: URL?
    @State private var required: Int64 = 0
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("lowSpace.title"), systemImage: "externaldrive").font(.title2.bold())
            Text(job.input.lastPathComponent).font(.headline)
            Text(L10n.text("lowSpace.explanation")).foregroundStyle(.secondary)
            if loading { ProgressView() } else if disks.isEmpty { Text(L10n.text("lowSpace.noDisk")) }
            ForEach(disks) { disk in
                Button {
                    selection = disk; folder = disk.root; error = nil
                } label: {
                    HStack {
                        Image(systemName: selection?.id == disk.id ? "checkmark.circle.fill" : "circle")
                        VStack(alignment: .leading) {
                            Text(disk.name).font(.headline)
                            Text(L10n.text("lowSpace.capacity", L10n.bytes(disk.availableBytes), L10n.bytes(required)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.padding(12)
                }.buttonStyle(.plain)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Button(L10n.text("lowSpace.choose")) { chooseFolder() }.capsuleControl()
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L10n.text("lowSpace.refresh"))
                Spacer()
                Button(L10n.text("lowSpace.later")) { dismiss() }.capsuleControl()
                Button(L10n.text("lowSpace.use")) {
                    guard let selection, let folder else { return }
                    do { try queue.retryUsingExternalDisk(job.id, folder: folder, disk: selection); dismiss() } catch {
                        self.error = error.localizedDescription
                    }
                }.capsuleControl().disabled(selection == nil || loading)
            }
        }.padding(24).frame(width: 560).task { await refresh() }
    }
    private func refresh() async {
        loading = true; selection = nil; folder = nil; error = nil
        do {
            let source = job.input, estimate = job.diskSpaceIssue?.requiredBytes
            let result = try await Task.detached {
                let required = try LowSpaceDisk.requiredBytes(for: source, estimatedOutput: estimate)
                return (required, LowSpaceDisk.candidates(for: source, requiredBytes: required))
            }.value
            required = result.0; disks = result.1
            selection = disks.first; folder = selection?.root
        } catch { self.error = error.localizedDescription }
        loading = false
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = L10n.text("lowSpace.chooseExplanation")
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            Task { @MainActor in
                do {
                    let source = job.input, required = required
                    let disk = try await Task.detached {
                        try LowSpaceDisk.inspect(folder, source: source, requiredBytes: required)
                    }.value
                    disks.removeAll { $0.id == disk.id }; disks.insert(disk, at: 0)
                    selection = disk; self.folder = folder; error = nil
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}
