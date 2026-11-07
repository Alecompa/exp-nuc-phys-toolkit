import NucPhysKit
import SwiftUI

/// Edits the shared setup. Works on a draft; Done commits, Cancel discards.
struct ReactionSetupSheet: View {
    @Environment(Workbench.self) private var workbench
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var beam: Double = 0
    @State private var excitation: Double = 0
    @State private var pickedPreset = 0
    @FocusState private var notationFocused: Bool

    private var parsed: Result<Reaction, ReactionError> { Workbench.parse(text) }
    private var reaction: Reaction? { try? parsed.get() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("12C(p,g)13N", text: $text)
                            .font(.system(.title3, design: .monospaced))
                            .notationInput()
                            .focused($notationFocused)
                            .submitLabel(.done)
                        preview
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Reaction")
                } footer: {
                    Text("Target(projectile,ejectile)Residual. Light ions: p d t h a n, photon g. The residual may be omitted.")
                }

                Section("Common reactions") {
                    ForEach(Presets.groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            FlowLayout(spacing: 8) {
                                ForEach(group.items, id: \.self) { item in
                                    presetChip(item)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    EnergyField(title: "Beam energy", keV: $beam, unit: workbench.energyUnit)
                    EnergyField(title: "Residual Eₓ", keV: $excitation, unit: workbench.energyUnit)
                } header: {
                    Text("Energies")
                } footer: {
                    Text("Laboratory kinetic energy of the projectile; excitation energy of the residual nucleus.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .navigationTitle("Setup")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { commit() }
                        .disabled(reaction == nil)
                }
            }
            .sensoryFeedback(.selection, trigger: pickedPreset)
        }
        .presentationDetents([.large])
        .onAppear {
            text = workbench.reactionText
            beam = workbench.beamEnergy
            excitation = workbench.residualExcitation
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch parsed {
        case .success(let r):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                ReactionTitle(reaction: r, font: .system(.headline, design: .rounded))
                Spacer()
                Text("Q = \(Fmt.energy(r.qValue, unit: workbench.energyUnit, uncertainty: r.qValueUncertainty)) \(workbench.energyUnit.label)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .transition(.opacity)
        case .failure(let e):
            Label(e.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(text.isEmpty ? .secondary : Color.orange)
                .transition(.opacity)
        }
    }

    private func presetChip(_ notation: String) -> some View {
        let r = try? Reaction(notation: notation)
        let selected = r != nil && r == reaction
        return Button {
            withAnimation(.smooth) { text = r?.plainLabel ?? notation }
            pickedPreset += 1
        } label: {
            Text(r?.label ?? notation)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? AnyShapeStyle(Color.accent) : AnyShapeStyle(.fill.tertiary), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func commit() {
        workbench.reactionText = reaction?.plainLabel ?? text
        workbench.beamEnergy = beam
        workbench.residualExcitation = excitation
        dismiss()
    }
}

enum Presets {
    struct Group { let title: String; let items: [String] }

    static let groups: [Group] = [
        Group(title: "Hydrogen burning", items: [
            "d(p,g)", "3He(a,g)", "7Be(p,g)", "12C(p,g)", "14N(p,g)", "15N(p,a)",
            "17O(p,g)", "22Ne(p,g)", "25Mg(p,g)",
        ]),
        Group(title: "Helium burning & s-process", items: [
            "12C(a,g)", "14N(a,g)", "13C(a,n)", "22Ne(a,n)",
        ]),
        Group(title: "Calibration & neutrons", items: [
            "27Al(p,g)", "7Li(p,n)", "d(d,n)", "t(d,n)",
        ]),
    ]
}

/// Wrapping horizontal layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let last = rows.count - 1
            rows[last].width += rows[last].indices.isEmpty ? size.width : size.width + spacing
            rows[last].height = max(rows[last].height, size.height)
            rows[last].indices.append(i)
        }
        return rows
    }
}
