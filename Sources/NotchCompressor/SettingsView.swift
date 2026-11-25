import KeyboardShortcuts
import AppKit
import SwiftUI
import ServiceManagement
import NotchCompressorCore

struct SettingsView: View {
    @ObservedObject var queue: JobQueue
    @ObservedObject private var updates = UpdateController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var loginStatus = SMAppService.mainApp.status
    @ObservedObject private var notifications = TaskNotifications.shared
    @State private var message: String?
    @State private var loginDetails: String?
    @State private var showingDiagnostics = false
    @State private var category: SettingsCategory = .compression

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(L10n.text("ui.settings"), systemImage: "slider.horizontal.3").font(.title2.weight(.semibold))
                Spacer()
                IconControl(title: L10n.text("settings.close"), symbol: "checkmark", prominent: true) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }.padding(24)
            Picker(L10n.text("settings.category"), selection: $category) {
                ForEach(SettingsCategory.allCases) { category in
                    Text(L10n.text(category.rawValue)).tag(category)
                }
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 24).padding(.bottom, 12)
            Form {
                if category == .compression {
                    Section {
                        Picker(L10n.text("settings.quality"), selection: $queue.settings.quality) {
                            ForEach(CompressionQuality.allCases) { quality in Text(quality.title).tag(quality) }
                        }.pickerStyle(.segmented)
                        Text(queue.settings.quality.explanation)
                            .font(.callout)
                        Text(L10n.text("settings.modeScope"))
                            .font(.caption).foregroundStyle(.secondary)
                        if queue.settings.quality != .custom {
                            LabeledContent {
                                Text(queue.settings.quality.videoBudgetDescription)
                            } label: {
                                Label(L10n.text("settings.video"), systemImage: "video")
                            }
                            LabeledContent {
                                Text(
                                    L10n.text(
                                        "settings.audioTarget", L10n.integer(queue.settings.quality.audioBitrate / 1000)
                                    ))
                            } label: {
                                Label(L10n.text("settings.audio"), systemImage: "waveform")
                            }

                        }
                        if queue.settings.quality == .custom {
                            VStack(alignment: .leading, spacing: 8) {
                                LabeledContent(
                                    L10n.text("settings.videoBitrate"),
                                    value: L10n.text(
                                        "settings.originalPercent", L10n.integer(queue.settings.effectiveVideoPercent))
                                )
                                .monospacedDigit()
                                Slider(
                                    value: Binding(
                                        get: { Double(queue.settings.effectiveVideoPercent) },
                                        set: { queue.settings.videoPercent = Int($0) }), in: 10...100, step: 1
                                )
                                .accessibilityLabel(L10n.text("settings.videoPercent"))
                                .accessibilityValue(
                                    L10n.text(
                                        "settings.originalPercent", L10n.integer(queue.settings.effectiveVideoPercent)))
                                Text(L10n.text("settings.videoHint"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                LabeledContent(
                                    L10n.text("settings.audioBitrate"),
                                    value: L10n.text("settings.kbps", L10n.integer(queue.settings.effectiveAudioKbps))
                                )
                                .monospacedDigit()
                                Slider(
                                    value: Binding(
                                        get: { Double(queue.settings.effectiveAudioKbps) },
                                        set: { queue.settings.audioKbps = Int($0) }), in: 32...256, step: 8
                                )
                                .accessibilityLabel(L10n.text("settings.audioBitrate"))
                                .accessibilityValue(
                                    L10n.text("settings.kbps", L10n.integer(queue.settings.effectiveAudioKbps)))
                                Text(L10n.text("settings.audioHint"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text(L10n.text("settings.percentHint"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(L10n.text("settings.nextOnly"))
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup(L10n.text("settings.autoDetails")) {
                            VStack(alignment: .leading, spacing: 8) {
                                if queue.settings.quality != .custom {
                                    Text(L10n.text("settings.autoHint"))
                                    Text(L10n.text("settings.formula"))
                                }
                                Text(L10n.text("settings.bitrateExplanation"))
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        Label(L10n.text("settings.compression"), systemImage: "slider.horizontal.3")
                    }
                    Section {
                        Picker(
                            L10n.text("settings.fps"),
                            selection: Binding(
                                get: { queue.settings.effectiveVideoFrameRate },
                                set: { queue.settings.videoFrameRate = $0 })
                        ) {
                            ForEach(VideoFrameRate.allCases) { rate in Text(rate.title).tag(rate) }
                        }.pickerStyle(.segmented)
                        Text(
                            L10n.text("settings.fpsHint")
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Picker(
                            L10n.text("settings.videoSpeed"),
                            selection: Binding(
                                get: { queue.settings.effectiveVideoEncodingSpeed },
                                set: { queue.settings.videoEncodingSpeed = $0 })
                        ) {
                            ForEach(VideoEncodingSpeed.allCases) { speed in Text(speed.title).tag(speed) }
                        }.pickerStyle(.segmented)
                        Text(L10n.text("settings.speedHint"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(L10n.text("settings.speedScope"))
                            .font(.caption).foregroundStyle(.secondary)
                    } header: {
                        Label(L10n.text("settings.speed"), systemImage: "speedometer")
                    }
                    Section {
                        LabeledContent(
                            L10n.text("image.jpegQualityLabel"),
                            value: L10n.integer(Int(queue.settings.effectiveImageQuality)))
                        Slider(
                            value: Binding(
                                get: { queue.settings.effectiveImageQuality }, set: { queue.settings.imageQuality = $0 }
                            ), in: 10...100, step: 1
                        )
                        .accessibilityLabel(L10n.text("image.jpegQualityLabel"))
                        Text(L10n.text("image.qualityHint")).font(.caption).foregroundStyle(.secondary)
                        Text(L10n.text("image.pngLossless")).font(.caption).foregroundStyle(.secondary)
                    } header: {
                        Label(L10n.text("media.image"), systemImage: "photo")
                    }
                    Section {
                        Picker(
                            L10n.text("audio.bitrate"),
                            selection: Binding(
                                get: { queue.settings.effectiveStandaloneAudioKbps },
                                set: { queue.settings.standaloneAudioKbps = $0 })
                        ) {
                            ForEach([64, 96, 128, 160, 192, 256], id: \.self) { rate in Text("\(rate) kbps").tag(rate) }
                        }
                        Text(L10n.text("audio.bitrateHint")).font(.caption).foregroundStyle(.secondary)
                    } header: {
                        Label(L10n.text("audio.files"), systemImage: "waveform")
                    }
                    Section {
                        LabeledContent(L10n.text("settings.left"), value: L10n.text("settings.videoCopyAudio"))
                        LabeledContent(L10n.text("settings.center"), value: L10n.text("settings.compressBoth"))
                        LabeledContent(L10n.text("settings.right"), value: L10n.text("settings.audioCopyVideo"))
                        Text(L10n.text("settings.targetHint"))
                            .font(.caption).foregroundStyle(.secondary)
                    } header: {
                        Label(L10n.text("settings.target"), systemImage: "square.split.2x1")
                    }
                    Section {
                        LabeledContent(L10n.text("settings.video"), value: L10n.text("settings.hevc"))
                        Text(L10n.text("settings.resolution"))
                            .font(.caption).foregroundStyle(.secondary)
                        LabeledContent(L10n.text("settings.audio"), value: L10n.text("settings.aac"))
                        Text(
                            L10n.text("settings.lossy")
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Text(L10n.text("settings.preserve"))
                            .font(.caption).foregroundStyle(.secondary)
                    } header: {
                        Label(L10n.text("settings.codecs"), systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                if category == .general {
                    Section {
                        KeyboardShortcuts.Recorder(L10n.text("app.openQueue"), name: .showCompressionQueue)
                        Text(L10n.text("settings.shortcutHint"))
                            .font(.caption).foregroundStyle(.secondary)
                    } header: {
                        Label(L10n.text("settings.shortcut"), systemImage: "keyboard")
                    }
                    Section {
                        Toggle(
                            L10n.text("settings.login"),
                            isOn: Binding(
                                get: { loginStatus == .enabled || loginStatus == .requiresApproval }, set: updateLogin)
                        )
                        .toggleStyle(.switch)
                        Text(L10n.text("settings.loginHint"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(
                            loginStatus == .enabled
                                ? L10n.text("settings.enabled")
                                : loginStatus == .requiresApproval
                                    ? L10n.text("settings.approval") : L10n.text("settings.disabled")
                        )
                        .font(.caption)
                        if loginStatus == .requiresApproval {
                            Button {
                                SMAppService.openSystemSettingsLoginItems()
                            } label: {
                                Label(L10n.text("settings.loginItems"), systemImage: "arrow.up.forward.app")
                            }.capsuleControl()
                        }
                        if let message { Text(message).font(.callout).foregroundStyle(.orange) }
                        if let loginDetails {
                            DisclosureGroup(L10n.text("details.technical")) {
                                Text(loginDetails).font(.caption).textSelection(.enabled)
                            }
                        }
                    } header: {
                        Label(L10n.text("settings.startup"), systemImage: "power")
                    }
                    Section {
                        Toggle(
                            L10n.text("settings.notify"),
                            isOn: Binding(
                                get: { notifications.enabled },
                                set: { value in Task { await notifications.setEnabled(value) } })
                        )
                        .toggleStyle(.switch).disabled(notifications.changing)
                        Text(notifications.status).font(.caption).foregroundStyle(.secondary)
                    } header: {
                        Label(L10n.text("settings.notifications"), systemImage: "bell")
                    }
                }
                if category == .compression {
                    Section {
                        Label(L10n.text("app.replace"), systemImage: "checkmark.shield")
                        Text(L10n.text("settings.saveHint"))
                            .font(.callout).foregroundStyle(.secondary)
                    } header: {
                        Text(L10n.text("settings.save"))
                    }
                }
                if category == .updates {
                    Section {
                        Toggle(
                            L10n.text("settings.autoUpdate"),
                            isOn: Binding(
                                get: { updates.automaticallyChecks }, set: { updates.automaticallyChecks = $0 })
                        )
                        .toggleStyle(.switch)
                        Button(L10n.text("app.checkUpdates")) { updates.check() }
                            .capsuleControl()
                            .disabled(!updates.canCheck || queue.isBusy)
                        Text(L10n.text("settings.updateHint"))
                            .font(.caption).foregroundStyle(.secondary)
                        if let status = updates.status { Text(status).font(.caption).foregroundStyle(.secondary) }
                        if let details = updates.technicalDetails {
                            DisclosureGroup(L10n.text("details.technical")) {
                                Text(details).font(.caption).textSelection(.enabled)
                            }
                        }
                    } header: {
                        Label(L10n.text("settings.updates"), systemImage: "arrow.down.circle")
                    }
                    Section {
                        Button {
                            showingDiagnostics = true
                        } label: {
                            Label(L10n.text("settings.diagnostics"), systemImage: "stethoscope")
                        }.capsuleControl()
                        Text(L10n.text("settings.supportHint"))
                            .font(.caption).foregroundStyle(.secondary)
                    } header: {
                        Text(L10n.text("settings.support"))
                    }
                    Section {
                        LabeledContent(
                            L10n.text("settings.version"),
                            value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                                ?? L10n.text("app.development"))
                        Text("NotchCompressor · Apache 2.0\nFFmpeg 9.0.1 · LGPL 2.1 or later\nSparkle 2.10.1 · MIT")
                            .font(.caption).foregroundStyle(.secondary)
                        Button {
                            if let url = Bundle.main.resourceURL?.appendingPathComponent("Licenses") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label(L10n.text("settings.licenses"), systemImage: "doc.text")
                        }.capsuleControl()
                    } header: {
                        Text(L10n.text("settings.about"))
                    }
                }
            }.formStyle(.grouped)
                .id(category)
        }.frame(width: 560, height: 620)
            .task {
                loginStatus = SMAppService.mainApp.status; await notifications.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                loginStatus = SMAppService.mainApp.status
                Task { await notifications.refresh() }
            }
            .sheet(isPresented: $showingDiagnostics) { DiagnosticsView(queue: queue) }
    }

    private func updateLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginStatus = SMAppService.mainApp.status
            message = nil
            loginDetails = nil
        } catch {
            loginStatus = SMAppService.mainApp.status
            message = L10n.text("settings.loginError")
            loginDetails = error.localizedDescription
        }
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case compression = "settings.compression"
    case general = "settings.general"
    case updates = "settings.updatesSupport"
    var id: Self { self }
}
