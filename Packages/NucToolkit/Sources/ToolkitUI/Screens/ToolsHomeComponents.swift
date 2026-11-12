import SwiftUI

extension ToolSection {
    var symbol: String {
        switch title {
        case "Reactions": "atom"
        case "Stopping & Targets": "square.stack.3d.down.right.fill"
        case "Nuclear Astrophysics": "sun.max.fill"
        case "Run Planning": "calendar.badge.clock"
        case "Detectors & Sources": "dot.radiowaves.left.and.right"
        default: "books.vertical.fill"
        }
    }
    var tint: Color {
        switch title {
        case "Reactions": .indigo
        case "Stopping & Targets": .orange
        case "Nuclear Astrophysics": .yellow
        case "Run Planning": .green
        case "Detectors & Sources": .purple
        default: .gray
        }
    }
}

extension Tool {
    /// Caption under a pinned tile.
    var shortTitle: String {
        switch self {
        case .rutherford: "Rutherford"
        case .stopping: "Stopping"
        case .penetrability: "Penetrability"
        case .sFactor: "S-Factor"
        case .resonanceStrength: "Resonance ωγ"
        case .gammaDoppler: "γ Doppler"
        case .yieldEstimate: "Yield & Time"
        case .spectrum: "Spectrum"
        case .detector: "Detector"
        case .sources: "Sources"
        case .decay: "Decay"
        case .units: "Units"
        case .formulas: "Formulas"
        case .exfor: "EXFOR"
        case .gamowWindow: "Gamow"
        case .reactionRate: "Rate"
        case .energyLoss: "Energy Loss"
        case .beamCurrent: "Current"
        default: title
        }
    }
}

/// Collapsible category header: icon, title, tool count and a disclosure chevron.
struct CategoryHeader: View {
    let section: ToolSection
    let expanded: Bool
    /// Larger title with a tinted icon tile, for the card layout (no list section header styling there).
    var prominent = false
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: prominent ? 10 : 8) {
                if prominent {
                    Image(systemName: section.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(section.tint)
                        .frame(width: 30, height: 30)
                        .background(section.tint.opacity(0.15), in: .rect(cornerRadius: 8, style: .continuous))
                    Text(section.title).font(.title3.weight(.semibold))
                } else {
                    Image(systemName: section.symbol).foregroundStyle(section.tint)
                    Text(section.title)
                }
                Text("\(section.tools.count)").foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(section.title), \(section.tools.count) tools")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityHint(expanded ? "Collapses the category" : "Expands the category")
        .accessibilityAddTraits([.isHeader, .isButton])
    }
}

/// Pinned tools in a horizontal strip, or wrapped in a grid; touch and hold a tile to reorder or unpin it.
struct PinnedToolsStrip: View {
    let tools: [Tool]
    /// Wrap into rows instead of scrolling horizontally.
    var wraps = false
    let open: (Tool) -> Void
    let unpin: (Tool) -> Void
    let move: (Tool, Int) -> Void

    var body: some View {
        if wraps {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 4, alignment: .top)], spacing: 14) {
                ForEach(tools) { tile($0) }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(tools) { tile($0) }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func tile(_ tool: Tool) -> some View {
        // A menu with a primary action: tap opens the tool, touch and hold shows its own options
        // (a context menu would attach to the whole list row).
        Menu {
            if tool != tools.first {
                Button { move(tool, -1) } label: { Label("Move Left", systemImage: "arrow.left") }
            }
            if tool != tools.last {
                Button { move(tool, 1) } label: { Label("Move Right", systemImage: "arrow.right") }
            }
            Button(role: .destructive) { unpin(tool) } label: { Label("Unpin", systemImage: "pin.slash") }
        } label: {
            VStack(spacing: 6) {
                ToolIcon(symbol: tool.symbol, tint: tool.tint, size: 52)
                Text(tool.shortTitle)
                    .font(.caption).foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: 80)
            .contentShape(.rect)
        } primaryAction: {
            open(tool)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .cardHoverEffect()
        .accessibilityLabel(tool.title)
    }
}
