import SwiftUI
import NotchCompressorCore

struct NotchWidgetsView: View {
    @ObservedObject var widgets: NotchWidgetsController
    let cameraWidth: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            Group {
                if widgets.persistentClock {
                    NotchClockView(compact: true)
                } else if let track = widgets.track, widgets.persistentMusic {
                    AlbumArtworkView(data: track.artwork).frame(width: 22, height: 22)
                }
            }.frame(maxWidth: .infinity)
            Color.clear.frame(width: cameraWidth)
            Group {
                if widgets.persistentMusic, let track = widgets.track {
                    HStack(spacing: 5) {
                        PlaybackActivityView(playing: track.playing).font(.caption2)
                        Text(track.title).font(.caption).lineLimit(1).truncationMode(.tail)
                    }
                    .help([track.title, track.artist].filter { !$0.isEmpty }.joined(separator: " — "))
                    .accessibilityLabel([track.title, track.artist].filter { !$0.isEmpty }.joined(separator: ", "))
                } else if widgets.persistentClock {
                    TimelineView(.everyMinute) { context in
                        Text(context.date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(L10n.locale)))
                            .font(.caption).lineLimit(1)
                    }
                }
            }.padding(.horizontal, 10).frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if widgets.showIdleBackground {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0
                ).fill(.black)
            }
        }
        .shadow(color: widgets.showIdleBackground ? .clear : .black.opacity(0.5), radius: 1)
    }
}

struct NotchDashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var widgets: NotchWidgetsController
    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            if widgets.showClock {
                NotchClockView(compact: false)
            }
            if widgets.showMusic {
                VStack(alignment: .leading, spacing: 8) {
                    if let track = widgets.track {
                        HStack(spacing: 8) {
                            AlbumArtworkView(data: track.artwork).frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title).font(.callout.weight(.semibold)).lineLimit(2)
                                    .contentTransition(.opacity)
                                Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        HStack(spacing: 10) {
                            Button {
                                widgets.togglePlayback()
                            } label: {
                                ZStack {
                                    if widgets.controlling {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Image(systemName: track.playing ? "pause.fill" : "play.fill")
                                    }
                                }.frame(width: 34, height: 34)

                            }
                            .modifier(CircularControlStyle())
                            .disabled(widgets.controlling)
                            .accessibilityLabel(L10n.text(track.playing ? "widgets.pause" : "widgets.play"))
                            .help(L10n.text(track.playing ? "widgets.pause" : "widgets.play"))
                            if track.playing && !widgets.controlling {
                                PlaybackActivityView(playing: true).accessibilityHidden(true)
                            }
                            if widgets.statusKey == "widgets.controlFailed" {
                                Image(systemName: "exclamationmark.circle")
                                    .help(L10n.text("widgets.controlFailed"))
                                    .accessibilityLabel(L10n.text("widgets.controlFailed"))
                            }
                        }
                    } else {
                        Label(
                            L10n.text(widgets.playbackIssue ?? widgets.statusKey ?? "widgets.noTrack"),
                            systemImage: "music.note"
                        )
                        .font(.callout).foregroundStyle(.secondary).lineLimit(3)
                        if widgets.connection == .ready || widgets.controlling || widgets.playbackIssue != nil {
                            Button {
                                widgets.togglePlayback()
                            } label: {
                                ZStack {
                                    if widgets.controlling {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Image(systemName: "play.fill")
                                    }
                                }.frame(width: 34, height: 34)
                            }
                            .modifier(CircularControlStyle())
                            .disabled(widgets.controlling || (widgets.track == nil && widgets.connection != .ready))
                            .accessibilityLabel(L10n.text("widgets.play"))
                            .help(L10n.text("music.startHint"))
                        }
                    }
                }.frame(
                    maxWidth: widgets.showClock ? .infinity : 280, alignment: widgets.showClock ? .leading : .center)
            }
            if !widgets.showClock && !widgets.showMusic {
                Text(L10n.text("widgets.chooseContent")).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
        .overlay(alignment: .trailing) {
            Button {
                AppState.shared.presentQueue(settings: true)
            } label: {
                Image(systemName: "gearshape").frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.12), in: Circle())
            .accessibilityLabel(L10n.text("ui.settings"))
            .help(L10n.text("ui.settings"))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: widgets.track)
    }
}

struct AlbumArtworkView: View {
    let data: Data?
    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.12))
                    .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityHidden(true)
    }
}

/// A playback indicator, not an audio-level meter. No audio is captured.
struct PlaybackActivityView: View {
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !playing || reduceMotion)) { context in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { index in
                    Capsule().frame(width: 2.5, height: height(index, at: context.date))
                }
            }
            .frame(width: 18, height: 18)
            .overlay {
                if !playing { Image(systemName: "music.note").font(.system(size: 11, weight: .semibold)) }
            }
        }
        .accessibilityLabel(L10n.text(playing ? "widgets.playing" : "widgets.paused"))
    }
    private func height(_ index: Int, at date: Date) -> CGFloat {
        guard playing else { return 0 }
        guard !reduceMotion else { return [6, 13, 9, 16][index] }
        let phase = date.timeIntervalSinceReferenceDate * (2.8 + Double(index) * 0.37) + Double(index) * 1.4
        return 4 + 12 * CGFloat((sin(phase) + 1) / 2)
    }
}

struct NotchClockView: View {
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .center, spacing: 6) {
                Text(context.date.formatted(.dateTime.hour().minute().second().locale(L10n.locale)))
                    .font(.system(size: compact ? 13 : 26, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: false))
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.24), value: Int(context.date.timeIntervalSince1970)
                    )
                    .fixedSize(horizontal: true, vertical: false)
                if !compact {
                    Text(context.date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(L10n.locale)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
