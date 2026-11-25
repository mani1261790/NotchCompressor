import SwiftUI
import NotchCompressorCore

struct NotchWidgetsView: View {
    @ObservedObject var widgets: NotchWidgetsController
    let cameraWidth: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            Group {
                if widgets.showClock {
                    NotchClockView(compact: true)
                } else if let track = widgets.track, widgets.showMusic {
                    PlaybackActivityView(playing: track.playing)
                }
            }.frame(maxWidth: .infinity)
            Color.clear.frame(width: cameraWidth)
            Group {
                if widgets.showMusic, let track = widgets.track {
                    HStack(spacing: 5) {
                        PlaybackActivityView(playing: track.playing).font(.caption2)
                        Text(track.title).font(.caption).lineLimit(1).truncationMode(.tail)
                    }
                    .help([track.title, track.artist].filter { !$0.isEmpty }.joined(separator: " — "))
                    .accessibilityLabel([track.title, track.artist].filter { !$0.isEmpty }.joined(separator: ", "))
                } else if widgets.showClock {
                    TimelineView(.everyMinute) { context in
                        Text(context.date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(L10n.locale)))
                            .font(.caption).lineLimit(1)
                    }
                }
            }.padding(.horizontal, 10).frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            .black,
            in: UnevenRoundedRectangle(
                topLeadingRadius: cameraWidth > 0 ? 0 : 12,
                bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: cameraWidth > 0 ? 0 : 12))
    }
}

struct NotchDashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var widgets: NotchWidgetsController
    var body: some View {
        HStack(spacing: 20) {
            if widgets.showClock {
                NotchClockView(compact: false)
            }
            if widgets.showMusic {
                VStack(alignment: .leading, spacing: 6) {
                    if let track = widgets.track {
                        HStack(spacing: 8) {
                            PlaybackActivityView(playing: track.playing)
                            Text(track.title).font(.headline).lineLimit(2)
                                .contentTransition(.opacity)
                        }
                        Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Label(L10n.text(widgets.statusKey ?? "widgets.noTrack"), systemImage: "music.note")
                            .font(.callout).foregroundStyle(.secondary).lineLimit(3)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !widgets.showClock && !widgets.showMusic {
                Text(L10n.text("widgets.chooseContent")).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
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
                if !playing { Image(systemName: "pause.fill").font(.system(size: 11, weight: .semibold)) }
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
            VStack(alignment: .leading, spacing: 6) {
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
