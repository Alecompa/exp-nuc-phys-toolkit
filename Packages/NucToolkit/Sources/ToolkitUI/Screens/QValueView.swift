import NucPhysKit
import SwiftUI

struct QValueView: View {
    @Environment(Workbench.self) private var workbench
    @State private var editingSetup = false

    var body: some View {
        @Bindable var workbench = workbench
        let unit = workbench.energyUnit

        ToolList {
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
                } footer: { Group {
                    Text("Q = Δ(target) + Δ(projectile) − Δ(ejectile) − Δ(residual). Uncertainties add in quadrature; AME correlations are neglected. # marks values from systematics.")
                }.wrappingFooter() }
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
    /// Show the beam-energy stepper (off where the tool has its own energy field).
    var showsBeam = true

    var body: some View {
        HStack(spacing: 10) {
            Button(action: edit) {
                HStack(spacing: 10) {
                    ReactionTitle(reaction: reaction)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit the reaction")
            Spacer(minLength: 0)
            if showsBeam { BeamEnergyStepper() }
        }
    }
}

/// Beam energy of the shared setup with − / + buttons, for quick scans during a shift.
/// The step is chosen from the menu on the value.
struct BeamEnergyStepper: View {
    @Environment(Workbench.self) private var workbench
    @AppStorage("beam.step") private var step = 10.0     // keV
    private static let steps: [Double] = [1, 5, 10, 25, 50, 100, 500]

    var body: some View {
        #if os(macOS)
        macControl
        #else
        touchControl
        #endif
    }

    #if os(macOS)
    /// Mac: an editable field, a stepper and the step size, like a native inspector control.
    private var macControl: some View {
        HStack(spacing: 6) {
            Text("Beam").foregroundStyle(.secondary)
            TextField("Beam energy", value: Binding(
                get: { workbench.beamEnergy / workbench.energyUnit.scale },
                set: { workbench.beamEnergy = max(0, $0) * workbench.energyUnit.scale }
            ), format: .number.precision(.fractionLength(0...4)).grouping(.never))
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .rowField(width: 84)
            Text(workbench.energyUnit.label).foregroundStyle(.secondary)
            Stepper("Beam energy", onIncrement: { change(step) }, onDecrement: { change(-step) })
                .labelsHidden()
                .help("Change the beam energy by \(Fmt.keV(step)) keV (⌘⌥↑ / ⌘⌥↓)")
            Picker("Step", selection: $step) {
                ForEach(Self.steps, id: \.self) { Text("± \(Int($0)) keV").tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .help("Step of the stepper and of ⌘⌥↑ / ⌘⌥↓")
        }
        .controlSize(.small)
    }
    #endif

    private var touchControl: some View {
        HStack(spacing: 2) {
            Button { change(-step) } label: { Image(systemName: "minus") }
                .accessibilityLabel("Lower beam energy by \(Fmt.keV(step)) keV")
                .disabled(workbench.beamEnergy - step < 0)
            Menu {
                Section("Step") {
                    ForEach(Self.steps, id: \.self) { s in
                        Button { step = s } label: {
                            if s == step { Label("\(Fmt.keV(s)) keV", systemImage: "checkmark") } else { Text("\(Fmt.keV(s)) keV") }
                        }
                    }
                }
            } label: {
                VStack(spacing: 0) {
                    Text(Fmt.energy(workbench.beamEnergy, unit: workbench.energyUnit, decimals: workbench.energyUnit == .keV ? 1 : 4))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("\(workbench.energyUnit.label) beam").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(minWidth: 64)
            }
            Button { change(step) } label: { Image(systemName: "plus") }
                .accessibilityLabel("Raise beam energy by \(Fmt.keV(step)) keV")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .sensoryFeedback(.selection, trigger: workbench.beamEnergy)
    }

    private func change(_ d: Double) {
        withAnimation(.smooth) { workbench.beamEnergy = max(0, (workbench.beamEnergy + d) / step).rounded() * step }
    }
}
