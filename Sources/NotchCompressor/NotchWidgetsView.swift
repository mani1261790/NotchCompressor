import SwiftUI
import NotchCompressorCore

struct NotchWidgetsView: View {
    @ObservedObject var widgets: NotchWidgetsController
    let cameraWidth: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            Group {
                if widgets.showClock {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
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
                    TimelineView(.periodic(from: .now, by: 60)) { context in
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
