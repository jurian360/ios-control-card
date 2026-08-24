import SwiftUI

// MARK: - Glass look

/// The measurements the glass surfaces share, so a card, a cell and the tab bar
/// round off and breathe the same way.
enum Glass {
    static let cornerRadius: CGFloat = 22
    static let innerCornerRadius: CGFloat = 12
    static let padding: CGFloat = 16
}

/// The tinted backdrop the glass sits on. Material only reads as glass when
/// there is something behind it to blur, which is the whole job of this view.
struct GlassBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.45),
                    Color.blue.opacity(0.28),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.teal.opacity(0.35))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -120, y: -220)

            Circle()
                .fill(Color.purple.opacity(0.30))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: 140, y: 260)
        }
        .ignoresSafeArea()
    }
}

/// A pane of glass: a blurred, translucent fill with a lit edge.
struct GlassSurface: View {
    var cornerRadius: CGFloat = Glass.cornerRadius
    var material: Material = .ultraThin
    var shadow: Bool = true

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(material)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.6), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(shadow ? 0.15 : 0), radius: 18, x: 0, y: 10)
    }
}

extension View {
    /// Floats the content on a pane of glass.
    func glassCard(cornerRadius: CGFloat = Glass.cornerRadius,
                   padding: CGFloat = Glass.padding) -> some View {
        self
            .padding(padding)
            .background(GlassSurface(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass tab bar

/// A floating, glass segmented bar. It drives a selection the same way a tab
/// bar does, but stays on top of the content instead of pushing it aside.
struct GlassTabBar<Selection: Hashable>: View {

    struct Item: Identifiable {
        let selection: Selection
        let title: String
        let systemImage: String

        var id: Selection { selection }
    }

    let items: [Item]
    @Binding var selection: Selection

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selection = item.selection
                    }
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(background(for: item))
                        .foregroundColor(isSelected(item) ? .white : .primary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected(item) ? [.isSelected] : [])
            }
        }
        .padding(5)
        .background(GlassSurface(cornerRadius: 28, material: .regular))
        .padding(.horizontal, Glass.padding)
    }

    private func isSelected(_ item: Item) -> Bool { item.selection == selection }

    @ViewBuilder
    private func background(for item: Item) -> some View {
        if isSelected(item) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .matchedGeometryEffect(id: "glassTabIndicator", in: indicator)
        } else {
            Capsule().fill(Color.clear)
        }
    }
}
