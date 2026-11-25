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
    private var reading = false
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

    private func refresh(askPermission: Bool = false) {
        guard showMusic, !sleeping, !reading else { return }
        guard
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first?
                .processIdentifier
        else {
            track = nil; statusKey = "widgets.openMusic"; return
        }
        reading = true
        connecting = askPermission
        Task {
            let result = await Task.detached(priority: .utility) {
                MusicTrackReader.read(pid: pid, askPermission: askPermission)
            }.value
            reading = false; connecting = false
            guard showMusic, !sleeping else { return }
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

    static func read(pid: pid_t, askPermission: Bool) -> Result {
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
            return .init(track: .init(title: title, artist: artist, playing: state == code("kPSP")), statusKey: nil)
        } catch { return .init(track: nil, statusKey: "widgets.musicUnavailable") }
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
