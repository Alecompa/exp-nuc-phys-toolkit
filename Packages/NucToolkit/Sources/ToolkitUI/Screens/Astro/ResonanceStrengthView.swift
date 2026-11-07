import NucPhysKit
import SwiftUI

struct ResonanceStrengthView: View {
    @Environment(Workbench.self) private var workbench
    @State private var editingSetup = false
    @State private var editingTarget = false

    private enum Mode: String, CaseIterable, Identifiable {
        case toYield = "ωγ → Yield", toStrength = "Yield → ωγ"
        var id: String { rawValue }
    }

    @State private var mode = Mode.toYield
    @State private var resonanceLab = 0.0          // keV, lab
    @State private var strength = 0.01             // eV
    @State private var yield = 1e-12               // reactions per projectile
    // Widths
    @State private var spinJ = 1.5
    @State private var spin1 = 0.5
    @State private var spin2 = 0.0
    @State private var gammaA = 1.0                // eV
    @State private var gammaB = 1.0                // eV
    @State private var totalIsSum = true
    @State private var gammaTotal = 2.0            // eV
    @State private var added = false

    var body: some View {
        Group {
            if let r = workbench.reaction, let c = workbench.entranceChannel {
                content(r, c)
            } else {
                NoChargedChannelView(symbol: "waveform.path.ecg", editingSetup: $editingSetup)
            }
        }
        .navigationTitle("Resonance Strength")
        .inlineTitle()
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
        .sheet(isPresented: $editingTarget) {
            if let t = workbench.stoppingTarget { TargetSheet(initial: t) }
        }
        .onAppear { if resonanceLab == 0 { resonanceLab = workbench.beamEnergy } }
    }

    @ViewBuilder
    private func content(_ r: Reaction, _ c: ChargedChannel) -> some View {
        @Bindable var workbench = workbench
        let eLab = max(resonanceLab, 1e-3)
        let eCM = c.cmEnergy(lab: eLab)
        let stopping = (try? workbench.stoppingCalculator?.stopping(at: eLab))?.map(\.total)
        let fraction = workbench.activeAtomFraction
        // eV cm² per active nucleus.
        let eps: Double? = stopping.flatMap { s in fraction.map { s * 1e-15 / $0 } }
        let wg = mode == .toYield ? strength : eps.map { c.resonanceStrength(resonanceEnergy: eCM, yield: yield, effectiveStopping: $0) }
        let y = mode == .toYield ? eps.map { c.thickTargetYield(resonanceEnergy: eCM, strength: strength, effectiveStopping: $0) } : yield

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    ReactionHeader(reaction: r) { editingSetup = true }
                    if mode == .toYield {
                        HeroNumber(value: y.map { Fmt.significant($0) } ?? "—", unit: "per ion",
                                   caption: "Maximum thick-target yield")
                    } else {
                        HeroNumber(value: wg.map { Fmt.significant($0) } ?? "—", unit: "eV",
                                   caption: "Resonance strength ωγ")
                    }
                    if let t = workbench.stoppingTarget {
                        HStack(spacing: 8) {
                            StatusBadge(text: t.name, symbol: "square.stack.3d.up.fill", tint: .brown)
                            if let fraction {
                                StatusBadge(text: "Active \(Fmt.significant(100 * fraction, digits: 3)) %",
                                            symbol: "atom", tint: .pink)
                            } else {
                                StatusBadge(text: "No \(r.target.label) in target", symbol: "exclamationmark.triangle.fill", tint: .orange)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                Picker("Mode", selection: $mode.animation(.smooth)) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                NumberField(title: "E_R (lab)", value: $resonanceLab, unit: "keV", range: 1e-3...1e6)
                ValueRow(label: "E_R (c.m.)", value: Fmt.keV(eCM, digits: 6), unit: "keV")
                if mode == .toYield {
                    ScientificField(title: "ωγ", value: $strength, unit: "eV")
                } else {
                    ScientificField(title: "Yield plateau", value: $yield, unit: "per ion", note: "Reactions per projectile")
                }
            } header: {
                Text("Resonance")
            }

            Section {
                Button {
                    editingTarget = true
                } label: {
                    LabeledContent("Target material", value: workbench.stoppingTarget?.name ?? "None")
                }
                .foregroundStyle(.primary)
                NumberField(title: "\(r.target.label) abundance", value: $workbench.isotopicAbundance, unit: "%", range: 1e-6...100)
                if let stopping {
                    ValueRow(label: "Stopping per atom", value: Fmt.significant(stopping),
                             note: "eV/(10¹⁵ at/cm²), compound mean at E_R")
                }
                if let eps {
                    ValueRow(label: "ε_eff", value: Fmt.significant(eps / 1e-15),
                             note: "eV/(10¹⁵ at/cm²) per \(r.target.label) nucleus")
                } else if fraction == nil {
                    Label("The target material contains no \(r.target.elementName.lowercased()).", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                ValueRow(label: "λ²/2 (c.m.)", value: Fmt.significant(c.deBroglieHalfSquared(energy: eCM)), unit: "cm²")
                ValueRow(label: "(m₁ + m₂)/m₂", value: Fmt.significant((c.m1 + c.m2) / c.m2, digits: 6))
            } header: {
                Text("Target")
            } footer: {
                Text("Y_max = (λ²/2) · (m₁+m₂)/m₂ · ωγ/ε_eff, for an infinitely thick target. ε_eff is the laboratory stopping per active nucleus: the compound's mean stopping divided by the active atom fraction (element fraction × abundance). SRIM-2013 stopping, from the Energy Loss target.")
            }

            Section {
                StepperRow(title: "J (resonance)", value: $spinJ)
                StepperRow(title: "j₁ (\(r.projectile.label))", value: $spin1)
                StepperRow(title: "j₂ (\(r.target.label))", value: $spin2)
                ScientificField(title: "Γ_a (entrance)", value: $gammaA, unit: "eV")
                ScientificField(title: "Γ_b (exit)", value: $gammaB, unit: "eV")
                Toggle("Γ = Γ_a + Γ_b", isOn: $totalIsSum.animation(.smooth))
                if !totalIsSum {
                    ScientificField(title: "Γ (total)", value: $gammaTotal, unit: "eV")
                }
                let omega = NarrowResonance.spinFactor(j: spinJ, j1: spin1, j2: spin2)
                let total = totalIsSum ? gammaA + gammaB : gammaTotal
                let s = NarrowResonance.strength(omega: omega, gammaA: gammaA, gammaB: gammaB, total: total)
                ValueRow(label: "ω", value: Fmt.significant(omega))
                ValueRow(label: "ωγ", value: Fmt.significant(s), unit: "eV")
                Button("Use this ωγ") {
                    withAnimation(.smooth) { mode = .toYield; strength = s }
                }
            } header: {
                Text("Strength from widths")
            } footer: {
                Text("ωγ = (2J+1)/((2j₁+1)(2j₂+1)) · Γ_aΓ_b/Γ. Multiply by 2 for identical particles in the entrance channel.")
            }

            if let wg {
                let res = NarrowResonance(energy: eCM, strength: wg)
                Section {
                    TemperatureControl()
                    ValueRow(label: "Nₐ⟨σv⟩", value: Fmt.significant(c.narrowResonanceRate(res, t9: workbench.temperatureT9)),
                             note: "cm³ mol⁻¹ s⁻¹")
                    Button {
                        workbench.resonances.append(res)
                        workbench.resonances.sort { $0.energy < $1.energy }
                        added.toggle()
                    } label: {
                        Label("Add to Reaction Rate", systemImage: "plus.circle.fill")
                    }
                    .sensoryFeedback(.success, trigger: added)
                } header: {
                    Text("Rate contribution")
                } footer: {
                    Text("Narrow-resonance rate Nₐ(2π/μkT)^3/2 ħ² ωγ exp(−E_R/kT), E_R in the centre of mass. \(workbench.resonances.count) resonance\(workbench.resonances.count == 1 ? "" : "s") in the rate model.")
                }
            }
        }
        .groupedList()
        .notebookSnapshot {
            var s = NotebookSnapshot(tool: .resonanceStrength, title: "\(r.label) resonance at \(Fmt.keV(eLab)) keV",
                                     subtitle: workbench.stoppingTarget?.name ?? "")
            s.add("Resonance", "E_R (lab)", Fmt.keV(eLab, digits: 6), "keV")
            s.add("Resonance", "E_R (c.m.)", Fmt.keV(eCM, digits: 6), "keV")
            s.add("Resonance", "ωγ", wg.map { Fmt.significant($0) } ?? "—", "eV")
            s.add("Yield", "Thick-target yield", y.map { Fmt.significant($0) } ?? "—", "per ion")
            if let eps { s.add("Yield", "ε_eff", Fmt.significant(eps / 1e-15), "10⁻¹⁵ eV cm²") }
            return s
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
    }
}

/// Half-integer spin stepper.
struct StepperRow: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        Stepper(value: $value, in: 0...20, step: 0.5) {
            LabeledContent(title) {
                Text(Self.spin(value)).monospacedDigit()
            }
        }
    }

    static func spin(_ j: Double) -> String {
        let twice = Int((2 * j).rounded())
        return twice % 2 == 0 ? "\(twice / 2)" : "\(twice)/2"
    }
}
