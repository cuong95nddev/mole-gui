import AppKit
import SwiftUI

/// Puts the pane title/subtitle into the window toolbar and its actions on the trailing side.
struct PaneHeader<Actions: View>: ViewModifier {
    let title: String
    let subtitle: String?
    @ViewBuilder var actions: () -> Actions

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationSubtitle(subtitle ?? "")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) { actions().labelStyle(.titleAndIcon) }
            }
    }
}

extension View {
    func paneHeader<A: View>(_ title: String, subtitle: String? = nil,
                             @ViewBuilder actions: @escaping () -> A = { EmptyView() }) -> some View {
        modifier(PaneHeader(title: title, subtitle: subtitle, actions: actions))
    }
}

struct Card<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
    }
}

struct Meter: View {
    /// 0...1
    let value: Double
    var height: CGFloat = 8

    var tint: Color {
        switch value {
        case ..<0.6: .green
        case ..<0.85: .orange
        default: .red
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint.gradient)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

/// Horizontal size bar relative to the largest sibling.
struct SizeBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary.opacity(0.5))
                RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.75))
                    .frame(width: max(2, min(1, fraction) * geo.size.width))
            }
        }
        .frame(height: 6)
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
            .padding(.top, 10)
    }
}

enum Finder {
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func icon(_ path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}
