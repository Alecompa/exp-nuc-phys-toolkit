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

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    SetupCard { editingSetup = true }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                ForEach(ToolCatalog.sections.filter { $0.tools.contains(where: shows) }) { section in
                    Section(section.title) {
                        ForEach(section.tools.filter(shows)) { tool in
                            NavigationLink(value: Route.tool(tool)) {
                                ToolRow(tool: tool)
                            }
                            .zoomSource(id: tool, in: zoom)
                        }
                        // Roadmap placeholders appear only in debug builds.
                        ForEach(Self.showsPlanned ? section.planned : []) { planned in
                            PlannedRow(tool: planned)
                        }
                    }
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
    /// Tools that make no sense for the current setup are left out of the list; a search still finds them.
    private func shows(_ tool: Tool) -> Bool {
        toolQuery.isEmpty ? isRelevant(tool) : matches(tool)
    }
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

private struct ToolRow: View {
    let tool: Tool

    var body: some View {
        HStack(spacing: 14) {
            ToolIcon(symbol: tool.symbol, tint: tool.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title).font(.body.weight(.medium))
                Text(tool.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
