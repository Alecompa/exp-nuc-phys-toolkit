import NucPhysKit
import SwiftUI

struct BeamCurrentView: View {
    @Environment(Workbench.self) private var workbench
    @State private var charge = 1.0              // integrated charge, in chargeUnit
    @State private var chargeUnit = ChargeUnit.C
    @State private var spotDiameter = 5.0        // mm
    @State private var editingSetup = false

    enum ChargeUnit: String, CaseIterable, Identifiable {
        case µC, mC, C
        var id: String { rawValue }
        var scale: Double { self == .µC ? 1e-6 : self == .mC ? 1e-3 : 1 }
    }

    var body: some View {
        @Bindable var workbench = workbench
        let pps = workbench.particlesPerSecond
        let unit = workbench.energyUnit
        let energy = workbench.beamEnergy
        let power = Beam.power(particlesPerSecond: pps, energy: energy)
        let area = Double.pi * pow(spotDiameter / 20, 2)                 // cm²
        let q = charge * chargeUnit.scale
        let particles = Beam.particles(charge: q, chargeState: workbench.chargeState)
        let time = q / max(workbench.beamCurrent * 1e-6, 1e-30)

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    if let r = workbench.reaction { ReactionHeader(reaction: r) { editingSetup = true } }
                    HeroNumber(value: Fmt.significant(pps), unit: "particles/s",
                               caption: "\(Fmt.significant(workbench.beamCurrent)) µA of \(ionLabel)\(workbench.chargeState == 1 ? "" : Superscript.digits(workbench.chargeState))⁺")
                    HStack(spacing: 8) {
                        StatusBadge(text: "\(Fmt.significant(power, digits: 3)) W", symbol: "flame.fill", tint: .orange)
                        StatusBadge(text: "\(Fmt.significant(Beam.particles(charge: 1, chargeState: workbench.chargeState), digits: 4)) per C",
                                    symbol: "number", tint: .blue)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                NumberField(title: "Electrical current", value: $workbench.beamCurrent, unit: "µA", range: 1e-9...1e6)
                Stepper(value: $workbench.chargeState, in: 1...92) {
                    LabeledContent("Charge state") { Text("\(workbench.chargeState)+").monospacedDigit() }
                }
                LabeledContent("Particle current") {
                    ScientificTextField(title: "pps", value: Binding(
                        get: { pps },
                        set: { workbench.beamCurrent = Beam.current(particlesPerSecond: $0, chargeState: workbench.chargeState) * 1e6 }))
                    Text("pps").foregroundStyle(.secondary)
                }
                ValueRow(label: "Particle current (pµA)", value: Fmt.significant(workbench.beamCurrent / Double(workbench.chargeState)),
                         unit: "pµA", note: "Electrical current / charge state")
            } header: {
                Text("Beam")
            } footer: {
                Text("Shared with Yield & Beam Time. 1 pµA = 6.2415 × 10¹² particles/s.")
            }

            Section {
                EnergyField(title: "Beam energy", keV: $workbench.beamEnergy, unit: unit)
                ValueRow(label: "Power on target", value: Fmt.significant(power, digits: 4), unit: "W")
                NumberField(title: "Beam spot diameter", value: $spotDiameter, unit: "mm", range: 0.01...1000)
                ValueRow(label: "Power density", value: Fmt.significant(power / area, digits: 3), unit: "W/cm²",
                         note: "Uniform spot")
            } header: {
                Text("Power")
            }

            Section {
                LabeledContent("Integrated charge") {
                    HStack(spacing: 6) {
                        ScientificTextField(title: "Charge", value: $charge)
                        Picker("Unit", selection: $chargeUnit) {
                            ForEach(ChargeUnit.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                ValueRow(label: "Particles", value: Fmt.significant(particles))
                let d = Fmt.duration(time)
                ValueRow(label: "Time at this current", value: d.value, unit: d.unit)
            } header: {
                Text("Accumulated charge")
            }
        }
        .groupedList()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .navigationTitle("Beam Current")
        .inlineTitle()
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
        .notebookSnapshot {
            var s = NotebookSnapshot(tool: .beamCurrent, title: "Beam \(ionLabel)\(workbench.chargeState)+",
                                     subtitle: "\(Fmt.significant(workbench.beamCurrent)) µA")
            s.add("Beam", "Current", Fmt.significant(workbench.beamCurrent), "µA")
            s.add("Beam", "Charge state", "\(workbench.chargeState)+")
            s.add("Beam", "Particle rate", Fmt.significant(pps), "pps")
            s.add("Power", "Energy", Fmt.energy(energy, unit: unit), unit.label)
            s.add("Power", "Power", Fmt.significant(power, digits: 4), "W")
            s.add("Charge", "Integrated charge", Fmt.significant(q), "C")
            s.add("Charge", "Particles", Fmt.significant(particles))
            return s
        }
    }

    private var ionLabel: String { workbench.reaction?.projectile.label ?? "ions" }
}
