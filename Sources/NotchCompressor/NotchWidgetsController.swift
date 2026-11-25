import AppKit
import Combine
import CoreServices
import NotchCompressorCore

@MainActor
final class NotchWidgetsController: ObservableObject {
    static let shared = NotchWidgetsController()
    @Published var alwaysVisible: Bool {
        didSet { UserDefaults.standard.set(alwaysVisible, forKey: "notch.alwaysVisible") }
    }
    @Published var showClock: Bool { didSet { UserDefaults.standard.set(showClock, forKey: "notch.showClock") } }
    @Published var showMusic: Bool {
        didSet {
            UserDefaults.standard.set(showMusic, forKey: "notch.showMusic")
            if !showMusic { track = nil; statusKey = nil }
        }
    }
    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var statusKey: String?
    @Published private(set) var connecting = false
    @Published private(set) var controlling = false
    @Published private(set) var reading = false
    private var playbackRevision = 0
    private var timer: AnyCancellable?
    private var sleeping = false
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    var hasVisibleContent: Bool { showClock || (showMusic && track != nil) }

    private init() {
        alwaysVisible = UserDefaults.standard.bool(forKey: "notch.alwaysVisible")
        showClock =
            UserDefaults.standard.object(forKey: "notch.showClock") == nil
            ? true : UserDefaults.standard.bool(forKey: "notch.showClock")
        showMusic = UserDefaults.standard.bool(forKey: "notch.showMusic")
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

    func connect() { refresh(askPermission: true) }

    func togglePlayback() {
        guard !controlling, !sleeping, showMusic, track != nil,
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first?
                .processIdentifier
        else { return }
        playbackRevision += 1
        controlling = true
        statusKey = nil
        Task {
            // Read back only playback state; artwork/metadata must not delay feedback.
            let playing = await Task.detached(priority: .userInitiated) { MusicTrackReader.toggle(pid: pid) }.value
            controlling = false
            guard showMusic, !sleeping else { return }
            if let playing, let current = track {
                track = NowPlayingTrack(
                    title: current.title, artist: current.artist, playing: playing,
                    identity: current.identity, artwork: current.artwork)
                refresh()
            } else {
                statusKey = "widgets.controlFailed"
            }
        }
    }

    private func refresh(askPermission: Bool = false) {
        guard showMusic, !sleeping, !reading, !controlling else { return }
        guard
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first?
                .processIdentifier
        else {
            track = nil; statusKey = "widgets.openMusic"; return
        }
        reading = true
        connecting = askPermission
        let previous = track
        let revision = playbackRevision
        Task {
            let result = await Task.detached(priority: .utility) {
                MusicTrackReader.read(pid: pid, askPermission: askPermission, previous: previous)
            }.value
            reading = false; connecting = false
            guard showMusic, !sleeping else { return }
            guard revision == playbackRevision else {
                // A poll started before the click must not restore the old icon.
                if !controlling { refresh() }
                return
            }
            track = result.track
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
        guard permission == noErr else { return .init(track: nil, statusKey: "widgets.musicPermission") }
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

    static func toggle(pid: pid_t) -> Bool? {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        guard let descriptor = target.aeDesc,
            AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, false) == noErr
        else { return nil }
        let event = NSAppleEventDescriptor(
            eventClass: code("hook"), eventID: code("PlPs"),
            targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 2)
            guard (reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value ?? 0) == 0 else {
                return nil
            }
            let state = try get(property: code("pPlS"), target: target).enumCodeValue
            guard [code("kPSP"), code("kPSp"), code("kPSS")].contains(state) else { return nil }
            return state == code("kPSP")
        } catch { return nil }
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
