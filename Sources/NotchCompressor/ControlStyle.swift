import SwiftUI

/// Native Liquid Glass on Tahoe, with the same rounded controls on older macOS.
struct CapsuleControlStyle: ViewModifier {
    var prominent = false
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glass).buttonBorderShape(.capsule).tint(.accentColor)
            } else {
                content.buttonStyle(.glass).buttonBorderShape(.capsule)
            }
        } else {
            if prominent {
                content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            } else {
                content.buttonStyle(.bordered).buttonBorderShape(.capsule)
            }
        }
    }
}

extension View {
    func capsuleControl(prominent: Bool = false) -> some View {
        modifier(CapsuleControlStyle(prominent: prominent))
    }
}

struct IconControl: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 36, height: 36)
        }
        .modifier(CircularControlStyle(prominent: prominent))
        .help(title)
        .accessibilityLabel(title)
    }
}

struct GlassCircleSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(.regularMaterial, in: Circle())
        }
    }
}

struct CircularControlStyle: ViewModifier {
    var prominent = false
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass).buttonBorderShape(.circle)
                .tint(prominent ? Color.accentColor : nil)
                .controlSize(.regular)
        } else {
            content.buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
    }
}
