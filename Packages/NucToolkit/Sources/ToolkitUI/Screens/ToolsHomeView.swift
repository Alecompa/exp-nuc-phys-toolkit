import NucPhysKit
import SwiftUI

struct ToolsHomeView: View {
    #if DEBUG
    static let showsPlanned = true
    #else
    static let showsPlanned = false
    #endif

    @Environment(Workbench.self) private var workbench
    @Namespace private var zoom
    @State private var path: [Route] = []
    @State private var toolQuery = ""
    @State private var editingSetup = false
    /// Pinned tools, in order (raw values joined by commas).
    @AppStorage("tools.pinned") private var pinnedStore = "kinematics,stopping,yieldEstimate,spectrum"
    /// Expanded categories (titles joined by "|").
    @AppStorage("tools.expanded") private var expandedStore = "Reactions"

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    SetupCard { editingSetup = true }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if toolQuery.isEmpty {
                    pinnedSection
                    categorySections
                } else {
                    searchResults
                }
            }
            .groupedList()
            .navigationTitle("Tools")
            .searchable(text: $toolQuery, prompt: "Find a calculator")
            .largeTitle()
            .appDestinations(namespace: zoom)
            .sheet(isPresented: $editingSetup) {
                ReactionSetupSheet()
            }
        }
    }

    // MARK: Pins and expanded categories

    private var pinned: [Tool] {
        pinnedStore.split(separator: ",").compactMap { Tool(rawValue: String($0)) }
    }
    private func setPinned(_ tools: [Tool]) {
        pinnedStore = tools.map(\.rawValue).joined(separator: ",")
    }
    private func togglePin(_ tool: Tool) {
        withAnimation(.smooth) {
            var p = pinned
            if let i = p.firstIndex(of: tool) { p.remove(at: i) } else { p.append(tool) }
            setPinned(p)
        }
    }
    private func movePin(_ tool: Tool, by offset: Int) {
        var p = pinned
        guard let i = p.firstIndex(of: tool), p.indices.contains(i + offset) else { return }
        withAnimation(.smooth) { p.swapAt(i, i + offset); setPinned(p) }
    }

    private var expanded: Set<String> { Set(expandedStore.split(separator: "|").map(String.init)) }
    private func toggleExpanded(_ title: String) {
        var e = expanded
        if e.contains(title) { e.remove(title) } else { e.insert(title) }
        withAnimation(.smooth) { expandedStore = e.sorted().joined(separator: "|") }
    }

    // MARK: Sections

    private var visibleSections: [ToolSection] {
        ToolCatalog.sections.compactMap { section in
            let tools = section.tools.filter(isRelevant)
            return tools.isEmpty ? nil : ToolSection(title: section.title, tools: tools, planned: section.planned)
        }
    }

    @ViewBuilder private var pinnedSection: some View {
        Section {
            if pinned.isEmpty {
                Label("Touch and hold a tool, or swipe it right, to pin it here.", systemImage: "pin")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                PinnedToolsStrip(tools: pinned, open: { path.append(.tool($0)) }, unpin: togglePin, move: movePin)
                    .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
            }
        } header: {
            Text("Pinned")
        }
    }

    @ViewBuilder private var categorySections: some View {
        ForEach(visibleSections) { section in
            let open = expanded.contains(section.title)
            Section(isExpanded: Binding(get: { open }, set: { if $0 != open { toggleExpanded(section.title) } })) {
                ForEach(section.tools) { tool in toolLink(tool) }
                // Roadmap placeholders appear only in debug builds.
                ForEach(Self.showsPlanned ? section.planned : []) { planned in PlannedRow(tool: planned) }
            } header: {
                CategoryHeader(section: section, expanded: open) { toggleExpanded(section.title) }
            }
        }
    }

    @ViewBuilder private var searchResults: some View {
        let hits = ToolCatalog.sections.flatMap(\.tools).filter(matches)
        if hits.isEmpty {
            ContentUnavailableView.search(text: toolQuery)
        } else {
            Section { ForEach(hits) { toolLink($0) } }
        }
    }

    private func toolLink(_ tool: Tool) -> some View {
        let isPinned = pinned.contains(tool)
        return NavigationLink(value: Route.tool(tool)) { ToolRow(tool: tool, pinned: isPinned) }
            .zoomSource(id: tool, in: zoom)
            .swipeActions(edge: .leading) {
                Button { togglePin(tool) } label: {
                    Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
                }
                .tint(.accent)
            }
            .contextMenu {
                Button { togglePin(tool) } label: {
                    Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
                }
            }
    }

    /// Tools that make no sense for the current setup are left out of the categories; a search still finds them.
    private func isRelevant(_ tool: Tool) -> Bool {
        switch tool {
        case .gammaDoppler:
            // No γ when a particle ejectile leaves the residual in its ground state.
            guard let r = workbench.reaction else { return true }
            return r.ejectile.isPhoton || workbench.residualExcitation > 0
        default: return true
        }
    }
    private func matches(_ tool: Tool) -> Bool {
        toolQuery.isEmpty || (tool.title + " " + tool.subtitle).localizedCaseInsensitiveContains(toolQuery)
    }
}

struct ToolRow: View {
    let tool: Tool
    var pinned = false

    var body: some View {
        HStack(spacing: 14) {
            ToolIcon(symbol: tool.symbol, tint: tool.tint)
                .overlay(alignment: .topTrailing) {
                    if pinned {
                        Image(systemName: "pin.circle.fill")
                            .font(.system(size: 14))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accent)
                            .offset(x: 6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title).font(.body.weight(.medium))
                Text(tool.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(pinned ? "Pinned" : "")
    }
}

private struct PlannedRow: View {
    let tool: PlannedTool

    var body: some View {
        HStack(spacing: 14) {
            ToolIcon(symbol: tool.symbol, tint: tool.tint, muted: true)
            Text(tool.title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("Planned")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Not available yet")
    }
}

/// The current experiment setup, in the content layer with a warm stellar gradient.
/// Its single action (Edit) is the view's one prominent control.
private struct SetupCard: View {
    @Environment(Workbench.self) private var workbench
    @Environment(\.colorScheme) private var scheme
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Current Setup", systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button(action: edit) {
                    Text("Edit").fontWeight(.semibold).foregroundStyle(.white)
                }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityLabel("Edit setup")
            }

            ReactionTitle(reaction: workbench.reaction, fallback: workbench.reactionText,
                          font: .system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 18) {
                fact("Beam", Fmt.energy(workbench.beamEnergy, unit: workbench.energyUnit, decimals: workbench.energyUnit == .keV ? 1 : 4))
                fact("Final state", Fmt.energy(workbench.residualExcitation, unit: workbench.energyUnit, decimals: workbench.energyUnit == .keV ? 1 : 4))
                if let r = workbench.reaction {
                    fact("Q", Fmt.energy(r.qValue, unit: workbench.energyUnit, uncertainty: r.qValueUncertainty))
                }
            }

            if let t = workbench.stoppingTarget {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                    Text(targetLine(t)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(StellarGradient.mesh(dark: scheme == .dark))
        }
        .padding(.vertical, 4)
        .animation(.smooth, value: workbench.reactionText)
    }

    private func targetLine(_ t: StoppingTarget) -> String {
        var parts = [t.name]
        let unit = workbench.thicknessUnit
        parts.append("\(Fmt.significant(unit.fromAngstrom(workbench.layerThickness, target: t), digits: 3)) \(unit.rawValue)")
        if workbench.layerAngle != 0 { parts.append("\(Fmt.number(workbench.layerAngle, decimals: 0))° tilt") }
        return parts.joined(separator: " · ")
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(workbench.energyUnit.label)
                    .font(.caption)
                    .opacity(0.75)
            }
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
    }
}

enum StellarGradient {
    /// A deep-red-to-amber mesh: a stellar interior, kept dark enough for white text (≥ 4.5:1).
    static func mesh(dark: Bool) -> MeshGradient {
        let deep = Color(red: 0.38, green: 0.06, blue: 0.18)
        let ember = Color(red: 0.70, green: 0.16, blue: 0.10)
        let flame = Color(red: 0.80, green: 0.33, blue: 0.08)
        let night = Color(red: 0.16, green: 0.05, blue: 0.22)
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.62, 0.42], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                night, deep, ember,
                deep, ember, flame,
                night, deep, dark ? ember : flame,
            ]
        )
    }
}
