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
                .frame(width: 24, height: 24)
        }
        .capsuleControl(prominent: prominent)
        .controlSize(.large)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct GlassCapsuleSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}
