import SwiftUI
import NotchCompressorCore

struct NotchWidgetsView: View {
    @ObservedObject var widgets: NotchWidgetsController
    let cameraWidth: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            Group {
                if widgets.showClock {
                    TimelineView(.everyMinute) { context in
                        Text(context.date.formatted(.dateTime.hour().minute().locale(L10n.locale)))
                            .font(.system(.callout, design: .rounded).weight(.medium)).monospacedDigit()
                            .accessibilityLabel(context.date.formatted(.dateTime.hour().minute().locale(L10n.locale)))
                    }
                } else if let track = widgets.track, widgets.showMusic {
                    Image(systemName: track.playing ? "music.note" : "pause.fill")
                }
            }.frame(maxWidth: .infinity)
            Color.clear.frame(width: cameraWidth)
            Group {
                if widgets.showMusic, let track = widgets.track {
                    HStack(spacing: 5) {
                        Image(systemName: track.playing ? "music.note" : "pause.fill").font(.caption2)
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
    @ObservedObject var widgets: NotchWidgetsController
    var body: some View {
        HStack(spacing: 20) {
            if widgets.showClock {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.date.formatted(.dateTime.hour().minute().locale(L10n.locale)))
                            .font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
                        Text(context.date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(L10n.locale)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if widgets.showMusic {
                VStack(alignment: .leading, spacing: 6) {
                    if let track = widgets.track {
                        Label(track.title, systemImage: track.playing ? "music.note" : "pause.fill")
                            .font(.headline).lineLimit(2)
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
    }
}
