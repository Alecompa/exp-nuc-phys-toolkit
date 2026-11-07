import NucPhysKit
import SwiftUI

struct QValueView: View {
    @Environment(Workbench.self) private var workbench
    @State private var editingSetup = false

    var body: some View {
        @Bindable var workbench = workbench
        let unit = workbench.energyUnit

        List {
            if let r = workbench.reaction {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        ReactionHeader(reaction: r) { editingSetup = true }
                        HeroNumber(
                            value: signed(Fmt.energy(r.qValue, unit: unit, uncertainty: r.qValueUncertainty), r.qValue),
                            uncertainty: Fmt.uncertainty(r.qValueUncertainty, unit: unit),
                            unit: unit.label,
                            caption: "Ground-state Q value"
                        )
                        HStack(spacing: 8) {
                            if r.qValue >= 0 {
                                StatusBadge(text: "Exothermic", symbol: "arrow.down.forward.circle.fill", tint: .green)
                            } else {
                                StatusBadge(text: "Endothermic", symbol: "arrow.up.forward.circle.fill", tint: .orange)
                            }
                            if r.usesEstimatedMasses {
                                StatusBadge(text: "Estimated masses", symbol: "number", tint: .yellow)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    EnergyField(title: "Residual Eₓ", keV: $workbench.residualExcitation, unit: unit)
                    let q = r.qValue(residualExcitation: workbench.residualExcitation)
                    ValueRow(label: "Q to this state",
                             value: signed(Fmt.energy(q, unit: unit, uncertainty: r.qValueUncertainty), q),
                             uncertainty: Fmt.uncertainty(r.qValueUncertainty, unit: unit), unit: unit.label)
                    let th = r.threshold(residualExcitation: workbench.residualExcitation)
                    ValueRow(label: "Threshold",
                             value: th > 0 ? Fmt.energy(th, unit: unit, uncertainty: r.qValueUncertainty) : "none",
                             unit: th > 0 ? unit.label : nil,
                             note: "Lab projectile energy")
                } header: {
                    Text("Final state")
                }

                Section {
                    ValueRow(label: "Beam energy", value: Fmt.energy(workbench.beamEnergy, unit: unit), unit: unit.label)
                    TargetEnergyToggle()
                    let k = TwoBodyKinematics(reaction: r, beamEnergy: workbench.reactionEnergy,
                                              residualExcitation: workbench.residualExcitation)
                    ValueRow(label: "Centre-of-mass energy", value: Fmt.energy(k.centerOfMassEnergy, unit: unit), unit: unit.label)
                    if let cn = r.compoundNucleus(), let ex = r.compoundExcitation(beamEnergy: workbench.reactionEnergy) {
                        ValueRow(label: "Compound \(cn.label) excitation", value: Fmt.energy(ex, unit: unit), unit: unit.label,
                                 note: "Eₓ = E(c.m.) + S")
                    }
                    ValueRow(label: "Channel", value: k.isOpen ? "Open" : "Closed")
                } header: {
                    Text(workbench.isUsingTargetMeanEnergy ? "At the mean energy in the target" : "At the beam energy")
                }

                Section {
                    massRow(r.target, role: "Target")
                    massRow(r.projectile, role: "Projectile")
                    if let ej = r.ejectile.nuclide {
                        massRow(ej, role: "Ejectile")
                    } else {
                        ValueRow(label: "γ", value: "0", unit: unit.label, note: "Ejectile")
                    }
                    massRow(r.residual, role: "Residual")
                } header: {
                    Text("Mass excesses · AME2020")
                } footer: {
                    Text("Q = Δ(target) + Δ(projectile) − Δ(ejectile) − Δ(residual). Uncertainties add in quadrature; AME correlations are neglected. # marks values from systematics.")
                }
            } else {
                ContentUnavailableView {
                    Label("No valid reaction", systemImage: "atom")
                } description: {
                    Text(workbench.reactionError?.localizedDescription ?? "Enter a reaction to compute its Q value.")
                } actions: {
                    Button("Edit Setup") { editingSetup = true }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .groupedList()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .navigationTitle("Q-Value")
        .inlineTitle()
        .notebookSnapshot {
            guard let r = workbench.reaction else { return nil }
            var s = NotebookSnapshot(tool: .qValue, title: r.label, subtitle: "Eₓ = \(Fmt.energy(workbench.residualExcitation, unit: unit)) \(unit.label)")
            s.add("Q value", "Ground state", Fmt.energy(r.qValue, unit: unit, uncertainty: r.qValueUncertainty), unit.label)
            s.add("Q value", "Uncertainty", Fmt.uncertainty(r.qValueUncertainty, unit: unit), unit.label)
            s.add("Q value", "To this state", Fmt.energy(r.qValue(residualExcitation: workbench.residualExcitation), unit: unit), unit.label)
            s.add("Q value", "Threshold", Fmt.energy(r.threshold(residualExcitation: workbench.residualExcitation), unit: unit), unit.label)
            let k = TwoBodyKinematics(reaction: r, beamEnergy: workbench.reactionEnergy, residualExcitation: workbench.residualExcitation)
            s.add("At the beam energy", "Beam energy", Fmt.energy(workbench.reactionEnergy, unit: unit), unit.label)
            s.add("At the beam energy", "E (c.m.)", Fmt.energy(k.centerOfMassEnergy, unit: unit), unit.label)
            if let cn = r.compoundNucleus(), let ex = r.compoundExcitation(beamEnergy: workbench.reactionEnergy) {
                s.add("At the beam energy", "\(cn.label) Eₓ", Fmt.energy(ex, unit: unit), unit.label)
            }
            return s
        }
        .animation(.smooth, value: workbench.reactionText)
        .animation(.smooth, value: workbench.residualExcitation)
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
    }

    private func massRow(_ n: Nuclide, role: String) -> some View {
        let unit = workbench.energyUnit
        return ValueRow(
            label: n.label + (n.isEstimated ? " #" : ""),
            value: Fmt.energy(n.massExcess, unit: unit, uncertainty: n.massExcessUncertainty),
            uncertainty: Fmt.uncertainty(n.massExcessUncertainty, unit: unit),
            unit: unit.label,
            note: role
        )
    }

    private func signed(_ s: String, _ x: Double) -> String { x > 0 ? "+" + s : s }
}

/// Compact reaction line used at the top of each tool; tapping edits the shared setup.
struct ReactionHeader: View {
    let reaction: Reaction
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            HStack(spacing: 10) {
                ReactionTitle(reaction: reaction)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit the reaction")
    }
}
