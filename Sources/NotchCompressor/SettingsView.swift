import KeyboardShortcuts
import AppKit
import SwiftUI
import ServiceManagement
import NotchCompressorCore

struct SettingsView: View {
    @ObservedObject var queue: JobQueue
    @ObservedObject private var updates = UpdateController.shared
    let close: () -> Void
    @State private var loginStatus = SMAppService.mainApp.status
    @ObservedObject private var notifications = TaskNotifications.shared
    @State private var message: String?
    @State private var loginDetails: String?
    @State private var showingDiagnostics = false
    @ObservedObject private var widgets = NotchWidgetsController.shared
    @State private var category: SettingsCategory = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $category) {
                Section(L10n.text("settings.application")) {
                    navigationRow(.general)
                    navigationRow(.notch)
                }
                Section(L10n.text("settings.compression")) {
                    navigationRow(.compression)
                    navigationRow(.images)
                    navigationRow(.audio)
                    navigationRow(.saving)
                }
                Section {
                    navigationRow(.updates)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 250)
            .navigationTitle(L10n.text("ui.settings"))
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: category.symbol)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 48, height: 48)
                        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text(category.rawValue)).font(.title2.weight(.semibold))
                        Text(category.summary).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    IconControl(title: L10n.text("settings.close"), symbol: "xmark") { close() }
                        .keyboardShortcut(.cancelAction)
                }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
                settingsForm
            }
            .navigationTitle(L10n.text(category.rawValue))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, idealWidth: 820, minHeight: 580, idealHeight: 650)
        .task {
            loginStatus = SMAppService.mainApp.status; await notifications.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
            Task { await notifications.refresh() }
        }
        .sheet(isPresented: $showingDiagnostics) { DiagnosticsView(queue: queue) }
    }

    private func navigationRow(_ item: SettingsCategory) -> some View {
        Label(L10n.text(item.rawValue), systemImage: item.symbol)
            .padding(.vertical, 5)
            .tag(item)
    }

    private var settingsForm: some View {
        Form {
            if category == .compression {
                Section {
                    Picker(L10n.text("settings.quality"), selection: $queue.settings.quality) {
                        ForEach(CompressionQuality.allCases) { quality in Text(quality.title).tag(quality) }
                    }.pickerStyle(.segmented)
                    Text(queue.settings.quality.explanation)
                        .font(.callout)

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
                    DisclosureGroup(L10n.text("settings.explainMotion")) {
                        Text(L10n.text("settings.fpsHint")).font(.callout).foregroundStyle(.secondary)
                    }
                    Picker(
                        L10n.text("settings.videoSpeed"),
                        selection: Binding(
                            get: { queue.settings.effectiveVideoEncodingSpeed },
                            set: { queue.settings.videoEncodingSpeed = $0 })
                    ) {
                        ForEach(VideoEncodingSpeed.allCases) { speed in Text(speed.title).tag(speed) }
                    }.pickerStyle(.segmented)
                    DisclosureGroup(L10n.text("settings.explainSpeed")) {
                        Text(L10n.text("settings.speedHint")).font(.callout).foregroundStyle(.secondary)
                        Text(L10n.text("settings.speedScope")).font(.callout).foregroundStyle(.secondary)
                    }
                } header: {
                    Label(L10n.text("settings.speed"), systemImage: "speedometer")
                }
            }
            if category == .images {
                Section {
                    HStack {
                        Button(L10n.text("quality.compact")) { queue.settings.imageQuality = 70 }.capsuleControl()
                        Button(L10n.text("quality.balanced")) { queue.settings.imageQuality = 85 }.capsuleControl()
                        Button(L10n.text("quality.gentle")) { queue.settings.imageQuality = 95 }.capsuleControl()
                    }
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
                } header: {
                    Text("JPEG")
                }
                Section {
                    Text(L10n.text("image.pngLossless")).font(.callout)
                    Text(L10n.text("image.pngExplanation")).font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("PNG")
                }
                Section {
                    Label(L10n.text("image.preserveSummary"), systemImage: "checkmark.shield")
                        .font(.callout)

                } header: {
                    Label(L10n.text("media.image"), systemImage: "photo")
                }
            }
            if category == .audio {
                Section {
                    HStack {
                        Button(L10n.text("audio.voicePreset")) { queue.settings.standaloneAudioKbps = 96 }
                            .capsuleControl()
                        Button(L10n.text("quality.balanced")) { queue.settings.standaloneAudioKbps = 160 }
                            .capsuleControl()
                        Button(L10n.text("audio.musicPreset")) { queue.settings.standaloneAudioKbps = 256 }
                            .capsuleControl()
                    }
                    Picker(
                        L10n.text("audio.bitrate"),
                        selection: Binding(
                            get: { queue.settings.effectiveStandaloneAudioKbps },
                            set: { queue.settings.standaloneAudioKbps = $0 })
                    ) {
                        ForEach([64, 96, 128, 160, 192, 256], id: \.self) { rate in Text("\(rate) kbps").tag(rate) }
                    }
                    Text(L10n.text("audio.bitrateHint")).font(.caption).foregroundStyle(.secondary)
                    LabeledContent(
                        L10n.text("audio.minuteEstimate"),
                        value: String(
                            format: "%.2f MB", locale: L10n.locale,
                            Double(queue.settings.effectiveStandaloneAudioKbps) * 60 / 8000))
                    Text(L10n.text("audio.estimateHint")).font(.caption).foregroundStyle(.secondary)
                } header: {
                    Label(L10n.text("audio.bitrate"), systemImage: "waveform")
                }
                Section {
                    Text(L10n.text("audio.preserveSummary")).font(.callout)
                } header: {
                    Label(L10n.text("audio.files"), systemImage: "waveform")
                }
            }
            if category == .saving {
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
            if category == .notch {
                Section {
                    Toggle(L10n.text("widgets.clock"), isOn: $widgets.showClock).toggleStyle(.switch)
                    Toggle(L10n.text("widgets.music"), isOn: $widgets.showMusic).toggleStyle(.switch)
                    Toggle(L10n.text("widgets.alwaysVisible"), isOn: $widgets.alwaysVisible).toggleStyle(.switch)
                        .disabled(!widgets.showClock && !widgets.showMusic)
                    Toggle(L10n.text("widgets.idleBackground"), isOn: $widgets.showIdleBackground).toggleStyle(.switch)
                        .disabled(widgets.alwaysVisible || (!widgets.showClock && !widgets.showMusic))
                    Text(L10n.text("widgets.idleHint")).font(.caption).foregroundStyle(.secondary)
                    Text(L10n.text("widgets.hint")).font(.caption).foregroundStyle(.secondary)
                    if widgets.showMusic {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(
                                widgets.connection.title,
                                systemImage: widgets.connection.connected
                                    ? "checkmark.circle.fill"
                                    : widgets.connection == .checking ? "arrow.triangle.2.circlepath" : "music.note"
                            )
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(widgets.connection.connected ? Color.green : Color.primary)
                            if widgets.connection.connected {
                                Text(L10n.text("music.connectedHint")).font(.caption).foregroundStyle(.secondary)
                                if let track = widgets.track {
                                    Text([track.title, track.artist].filter { !$0.isEmpty }.joined(separator: " — "))
                                        .font(.callout).lineLimit(2)
                                }
                            }
                            if widgets.connection == .denied {
                                Text(
                                    L10n.text(
                                        "music.permissionSteps",
                                        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                                            ?? "NotchCompressor")
                                )
                                .font(.caption).foregroundStyle(.secondary)
                                Button {
                                    widgets.openMusicPermissionSettings()
                                } label: {
                                    Label(L10n.text("music.openPermissions"), systemImage: "arrow.up.forward.app")
                                }.capsuleControl()
                            } else if widgets.connection == .closed || widgets.connection == .ready {
                                Button {
                                    widgets.openMusic()
                                } label: {
                                    Label(L10n.text("music.openApp"), systemImage: "arrow.up.forward.app")
                                }.capsuleControl()
                            }
                            if widgets.connecting {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text(L10n.text("music.checking")).font(.caption)
                                }
                            } else {
                                Button {
                                    widgets.connect()
                                } label: {
                                    Label(
                                        L10n.text(
                                            widgets.connection == .permissionNeeded ? "music.allow" : "music.recheck"),
                                        systemImage: widgets.connection == .permissionNeeded
                                            ? "hand.raised" : "arrow.clockwise")
                                }.capsuleControl()
                            }
                            if let date = widgets.lastConnectionCheck, !widgets.connecting {
                                Text(
                                    L10n.text(
                                        "music.checked",
                                        date.formatted(.dateTime.hour().minute().second().locale(L10n.locale)))
                                )
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }.padding(.vertical, 4)
                    }
                } header: {
                    Label(L10n.text("widgets.title"), systemImage: "menubar.rectangle")
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
                    Label(
                        notifications.status,
                        systemImage: notifications.authorization == .denied ? "bell.slash" : "bell.badge"
                    )
                    .font(.callout)
                    if notifications.authorization == .notDetermined {
                        Button {
                            Task { await notifications.setEnabled(true) }
                        } label: {
                            Label(L10n.text("notify.request"), systemImage: "bell.badge")
                        }.capsuleControl(prominent: true).disabled(notifications.changing)
                    } else if notifications.authorization == .denied {
                        Text(
                            L10n.text(
                                "notify.settingsSteps",
                                Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NotchCompressor"
                            )
                        )
                        .font(.callout).textSelection(.enabled)
                        Button {
                            notifications.openSettings()
                        } label: {
                            Label(L10n.text("notify.openSettings"), systemImage: "arrow.up.forward.app")
                        }.capsuleControl(prominent: true)
                    }
                } header: {
                    Label(L10n.text("settings.notifications"), systemImage: "bell")
                }
            }
            if category == .saving {
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
    case general = "settings.general"
    case notch = "widgets.title"
    case compression = "settings.video"
    case images = "media.image"
    case audio = "media.audio"
    case saving = "settings.savingBehavior"
    case updates = "settings.updates"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .notch: "menubar.rectangle"
        case .compression: "video"
        case .images: "photo"
        case .audio: "waveform"
        case .saving: "checkmark.shield"
        case .updates: "arrow.down.circle"
        }
    }
    var summary: String {
        switch self {
        case .general: L10n.text("settings.summary.general")
        case .notch: L10n.text("settings.summary.notch")
        case .compression: L10n.text("settings.summary.video")
        case .images: L10n.text("settings.summary.images")
        case .audio: L10n.text("settings.summary.audio")
        case .saving: L10n.text("settings.summary.saving")
        case .updates: L10n.text("settings.summary.updates")
        }
    }
}
