import SwiftUI

/// Native Liquid Glass on Tahoe, with the same rounded controls on older macOS.
struct CapsuleControlStyle: ViewModifier {
    var prominent = false
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent).buttonBorderShape(.capsule).tint(.accentColor)
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

/// NSMenu does not adopt Button's border shape; supply the surface explicitly.
struct GlassCapsuleSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

extension View {
    func capsuleMenu() -> some View {
        menuStyle(.borderlessButton).menuIndicator(.hidden)
            .fixedSize().padding(.horizontal, 12).padding(.vertical, 8)
            .modifier(GlassCapsuleSurface())
    }
}

/// Explicit native glass buttons rather than AppKit's flat segmented picker.
struct GlassChoicePicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let values: [Value]
    let label: (Value) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.callout.weight(.medium))
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 6) { choices }
            } else {
                choices
            }
        }.padding(.vertical, 4)
    }

    private var choices: some View {
        HStack(spacing: 6) {
            ForEach(values, id: \.self) { value in
                Button {
                    selection = value
                } label: {
                    Text(label(value)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                }
                .capsuleControl(prominent: selection == value)
                .accessibilityLabel(title + ": " + label(value))
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
    }
}
