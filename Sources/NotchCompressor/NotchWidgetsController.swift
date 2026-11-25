import AppKit
import Combine
import CoreServices
import NotchCompressorCore

@MainActor
final class NotchWidgetsController: ObservableObject {
    static let shared = NotchWidgetsController()
    @Published var showIdleBackground: Bool {
        didSet { UserDefaults.standard.set(showIdleBackground, forKey: "notch.showIdleBackground") }
    }
    @Published var clockDisplay: NotchWidgetDisplay {
        didSet { UserDefaults.standard.set(clockDisplay.rawValue, forKey: "notch.clockDisplay") }
    }
    @Published var musicDisplay: NotchWidgetDisplay {
        didSet {
            UserDefaults.standard.set(musicDisplay.rawValue, forKey: "notch.musicDisplay")
            if musicDisplay == .off { track = nil; statusKey = nil }
        }
    }
    var showClock: Bool { clockDisplay != .off }
    var showMusic: Bool { musicDisplay != .off }
    var persistentClock: Bool { clockDisplay == .always }
    var persistentMusic: Bool { musicDisplay == .always && track != nil }
    var hasPersistentContent: Bool { persistentClock || persistentMusic }
    @Published private(set) var playbackIssue: String?
    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var statusKey: String?
    @Published private(set) var connecting = false
    @Published private(set) var lastConnectionCheck: Date?
    @Published private(set) var controlling = false
    @Published private(set) var reading = false
    private var playbackRevision = 0
    private var timer: AnyCancellable?
    private var sleeping = false
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    var hasVisibleContent: Bool { showClock || (showMusic && track != nil) }

    private init() {
        showIdleBackground = UserDefaults.standard.bool(forKey: "notch.showIdleBackground")
        let defaults = UserDefaults.standard
        let legacyAlways = defaults.bool(forKey: "notch.alwaysVisible")
        clockDisplay = NotchWidgetDisplay(
            savedValue: defaults.string(forKey: "notch.clockDisplay"),
            legacyEnabled: (defaults.object(forKey: "notch.showClock") as? Bool) ?? true, legacyAlways: legacyAlways)
        musicDisplay = NotchWidgetDisplay(
            savedValue: defaults.string(forKey: "notch.musicDisplay"),
            legacyEnabled: defaults.bool(forKey: "notch.showMusic"), legacyAlways: legacyAlways)
        timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refresh() }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sleeping = true }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sleeping = false; self?.refresh()
            }
        }
    }

    var connection: MusicConnectionState {
        MusicConnectionState(checking: connecting, playing: track?.playing, statusKey: statusKey)
    }

    func connect() {
        guard showMusic, !connecting else { return }
        connecting = true
        Task {
            // Explicit clicks wait for a poll rather than disappearing during it.
            while reading || controlling {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { connecting = false; return }
            }
            guard showMusic, !sleeping else { connecting = false; return }
            refresh(askPermission: true)
        }
    }

    func openMusic() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
            statusKey = "widgets.musicUnavailable"; return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
    }

    func openMusicPermissionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func togglePlayback() {
        guard !controlling, !sleeping, showMusic, track != nil || connection == .ready,
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first?
                .processIdentifier
        else { return }
        let startingPlayback = track == nil
        playbackIssue = nil
        playbackRevision += 1
        controlling = true
        statusKey = nil
        Task {
            // Read back only playback state; artwork/metadata must not delay feedback.
            let playing = await Task.detached(priority: .userInitiated) {
                MusicTrackReader.toggle(pid: pid, start: startingPlayback)
            }.value
            controlling = false
            guard showMusic, !sleeping else { return }
            if let playing {
                if let current = track {
                    track = NowPlayingTrack(
                        title: current.title, artist: current.artist, playing: playing,
                        identity: current.identity, artwork: current.artwork)
                }
                if startingPlayback && !playing {
                    playbackIssue = "music.startUnavailable"
                    openMusic()
                }
                refresh()
            } else {
                playbackIssue = "widgets.controlFailed"
                statusKey = "widgets.controlFailed"
            }
        }
    }

    private func refresh(askPermission: Bool = false) {
        guard showMusic, !sleeping, !reading, !controlling, !connecting || askPermission else { return }
        guard
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first?
                .processIdentifier
        else {
            track = nil; statusKey = "widgets.openMusic"
            if askPermission { connecting = false; lastConnectionCheck = .now }
            return
        }
        reading = true
        connecting = askPermission
        let previous = track
        let revision = playbackRevision
        Task {
            let result = await Task.detached(priority: .utility) {
                MusicTrackReader.read(pid: pid, askPermission: askPermission, previous: previous)
            }.value
            reading = false
            if askPermission { connecting = false; lastConnectionCheck = .now }
            guard showMusic, !sleeping else { return }
            guard revision == playbackRevision else {
                // A poll started before the click must not restore the old icon.
                if !controlling { refresh() }
                return
            }
            track = result.track
            if result.track != nil { playbackIssue = nil }
            statusKey = result.statusKey
        }
    }
}

/// Uses Music's documented scripting properties, addressed to an existing PID.
/// This cannot launch Music, and polling never asks for new permission.
private enum MusicTrackReader {
    struct Result: Sendable { let track: NowPlayingTrack?; let statusKey: String? }
    static func code(_ text: String) -> OSType { text.utf8.reduce(0) { ($0 << 8) | OSType($1) } }

    static func read(pid: pid_t, askPermission: Bool, previous: NowPlayingTrack?) -> Result {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        guard let descriptor = target.aeDesc else { return .init(track: nil, statusKey: "widgets.musicUnavailable") }
        let permission = AEDeterminePermissionToAutomateTarget(
            descriptor, AEEventClass(typeWildCard), AEEventID(typeWildCard), askPermission)
        guard permission == noErr else {
            let key =
                permission == errAEEventWouldRequireUserConsent
                ? "widgets.permissionNeeded"
                : permission == errAEEventNotPermitted ? "widgets.musicPermission" : "widgets.musicUnavailable"
            return .init(track: nil, statusKey: key)
        }
        do {
            let state = try get(property: code("pPlS"), target: target).enumCodeValue
            guard [code("kPSP"), code("kPSp")].contains(state) else {
                return .init(track: nil, statusKey: "widgets.noTrack")
            }
            let currentTrack = try property(code("pTrk"))
            let title = try get(property: code("pnam"), container: currentTrack, target: target).stringValue ?? ""
            let artist = try get(property: code("pArt"), container: currentTrack, target: target).stringValue ?? ""
            guard !title.isEmpty else { return .init(track: nil, statusKey: "widgets.noTrack") }
            let identity = (try? get(property: code("pPIS"), container: currentTrack, target: target).stringValue) ?? ""
            let artwork: Data?
            if !identity.isEmpty, previous?.identity == identity {
                artwork = previous?.artwork
            } else {
                artwork = try? readArtwork(container: currentTrack, target: target)
            }
            return .init(
                track: .init(
                    title: title, artist: artist, playing: state == code("kPSP"), identity: identity, artwork: artwork),
                statusKey: nil)
        } catch { return .init(track: nil, statusKey: "widgets.musicUnavailable") }
    }

    static func toggle(pid: pid_t, start: Bool) -> Bool? {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        guard let descriptor = target.aeDesc,
            AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, false) == noErr
        else { return nil }
        let event = NSAppleEventDescriptor(
            eventClass: code("hook"), eventID: code(start ? "Play" : "PlPs"),
            targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 2)
            if (reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value ?? 0) != 0 && !start {
                return nil
            }
            var state = try get(property: code("pPlS"), target: target).enumCodeValue
            if start && state != code("kPSP") {
                // No resumable selection: ask Music to play its first library track.
                // An empty/unavailable library simply leaves playback stopped.
                if let library = try? firstObject(code("cLiP")),
                    let firstTrack = try? firstObject(code("cTrk"), container: library)
                {
                    event.setParam(firstTrack, forKeyword: AEKeyword(keyDirectObject))
                    _ = try? event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 2)
                    state = (try? get(property: code("pPlS"), target: target).enumCodeValue) ?? state
                }
            }
            guard [code("kPSP"), code("kPSp"), code("kPSS")].contains(state) else { return nil }
            return state == code("kPSP")
        } catch { return nil }
    }

    private static func firstObject(_ kind: OSType, container: NSAppleEventDescriptor = .null()) throws
        -> NSAppleEventDescriptor
    {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: kind), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        record.setDescriptor(
            NSAppleEventDescriptor(enumCode: OSType(formAbsolutePosition)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(NSAppleEventDescriptor(int32: 1), forKeyword: AEKeyword(keyAEKeyData))
        guard let result = record.coerce(toDescriptorType: typeObjectSpecifier) else {
            throw CocoaError(.coderInvalidValue)
        }
        return result
    }

    private static func readArtwork(container: NSAppleEventDescriptor, target: NSAppleEventDescriptor) throws -> Data? {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code("cArt")), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        record.setDescriptor(
            NSAppleEventDescriptor(enumCode: OSType(formAbsolutePosition)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(NSAppleEventDescriptor(int32: 1), forKeyword: AEKeyword(keyAEKeyData))
        guard let artwork = record.coerce(toDescriptorType: typeObjectSpecifier) else { return nil }
        let data = try get(property: code("pRaw"), container: artwork, target: target).data
        return !data.isEmpty && data.count <= 10 * 1024 * 1024 ? data : nil
    }

    private static func property(_ key: OSType, container: NSAppleEventDescriptor = .null()) throws
        -> NSAppleEventDescriptor
    {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: typeProperty), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        record.setDescriptor(
            NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: key), forKeyword: AEKeyword(keyAEKeyData))
        guard let object = record.coerce(toDescriptorType: typeObjectSpecifier) else {
            throw CocoaError(.coderInvalidValue)
        }
        return object
    }

    private static func get(
        property key: OSType, container: NSAppleEventDescriptor = .null(), target: NSAppleEventDescriptor
    ) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEGetData),
            targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(try property(key, container: container), forKeyword: AEKeyword(keyDirectObject))
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 2)
        if let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)), error.int32Value != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(error.int32Value))
        }
        guard let result = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else {
            throw CocoaError(.coderInvalidValue)
        }
        return result
    }
}
