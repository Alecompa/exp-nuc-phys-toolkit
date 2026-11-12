import Charts
import NucPhysKit
import SwiftUI

struct YieldEstimateView: View {
    @Environment(Workbench.self) private var workbench
    @State private var editingSetup = false
    @State private var editingTarget = false

    enum Source: String, CaseIterable, Identifiable {
        case sFactor = "S factor", crossSection = "σ", resonance = "Resonance"
        var id: String { rawValue }
    }

    @AppStorage("yield.source") private var source = Source.sFactor
    @AppStorage("yield.sigma") private var sigma = 1.0                 // in sigmaUnit
    @AppStorage("yield.sigmaUnit") private var sigmaUnitRaw = CrossSectionUnit.nb.rawValue
    @AppStorage("yield.resonanceLab") private var resonanceLab = 0.0   // keV
    @AppStorage("yield.strength") private var strength = 1e-3          // eV
    @AppStorage("yield.gammaEnergy") private var gammaEnergy = 0.0     // keV
    @AppStorage("yield.useCurve") private var useCurve = true
    @AppStorage("yield.efficiency") private var efficiencyPercent = 1.0
    @AppStorage("yield.branching") private var branchingPercent = 100.0
    @AppStorage("yield.background") private var backgroundPerHour = 10.0
    @AppStorage("yield.goal") private var goalPercent = 5.0
    @AppStorage("yield.plannedHours") private var plannedHours = 24.0
    @AppStorage("yield.equalBackground") private var equalBackground = true

    private var sigmaUnit: CrossSectionUnit { CrossSectionUnit(rawValue: sigmaUnitRaw) ?? .nb }

    struct Estimate {
        var yieldPerIon: Double?
        var effectiveEnergy: Double?
        var note: String?
    }

    var body: some View {
        Group {
            if let r = workbench.reaction, let c = workbench.entranceChannel {
                content(r, c)
            } else {
                NoChargedChannelView(symbol: "clock.badge.checkmark.fill", editingSetup: $editingSetup)
            }
        }
        .navigationTitle("Yield & Beam Time")
        .inlineTitle()
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
        .sheet(isPresented: $editingTarget) {
            if let t = workbench.stoppingTarget { TargetSheet(initial: t) }
        }
        .onAppear {
            if resonanceLab == 0 { resonanceLab = workbench.beamEnergy }
            if gammaEnergy == 0, let r = workbench.reaction, let e = workbench.reactionEnergyCM {
                gammaEnergy = max(1, (e + r.qValue(residualExcitation: workbench.residualExcitation)).rounded(toPlaces: 1))
            }
        }
    }

    private func estimate(_ c: ChargedChannel) -> Estimate {
        switch source {
        case .sFactor:
            guard let t = workbench.stackOutcome?.target else {
                return Estimate(note: "The beam does not reach the target layer.")
            }
            guard workbench.activeAtomFraction != nil else {
                return Estimate(note: "The target material contains no \(workbench.reaction?.target.label ?? "target nuclei").")
            }
            let eps: (Double) -> Double = { workbench.effectiveStopping(at: $0) ?? 0 }
            let y = c.targetYield(sFactor: workbench.sFactorModel, entranceEnergy: t.energyIn, exitEnergy: t.energyOut,
                                  screening: workbench.screeningPotential, steps: 120, stopping: eps)
            let eff = c.effectiveEnergy(sFactor: workbench.sFactorModel, entranceEnergy: t.energyIn, exitEnergy: t.energyOut,
                                        screening: workbench.screeningPotential, steps: 120, stopping: eps)
            return Estimate(yieldPerIon: y, effectiveEnergy: eff)
        case .crossSection:
            guard let target = workbench.stackOutcome?.target else {
                return Estimate(note: "The beam does not reach the target layer.")
            }
            guard !target.stopped else {
                return Estimate(note: "The beam stops inside the target. Use the energy-dependent S-factor integration instead of the thin-target approximation.")
            }
            guard let n = workbench.activeArealDensity else {
                return Estimate(note: "The target material contains no \(workbench.reaction?.target.label ?? "target nuclei").")
            }
            return Estimate(yieldPerIon: ChargedChannel.thinTargetYield(crossSection: sigma * sigmaUnit.scale, arealDensity: n),
                            effectiveEnergy: workbench.stackOutcome?.target.map { c.cmEnergy(lab: $0.meanEnergy) })
        case .resonance:
            guard let target = workbench.stackOutcome?.target else {
                return Estimate(note: "The beam does not reach the target layer.")
            }
            guard resonanceLab > target.energyOut, resonanceLab < target.energyIn else {
                return Estimate(note: "The resonance must lie inside the target's traversed energy interval for the thick-target plateau approximation.")
            }
            guard let eps = workbench.effectiveStopping(at: resonanceLab) else {
                return Estimate(note: "No stopping for the target material at E_R.")
            }
            let ecm = c.cmEnergy(lab: resonanceLab)
            return Estimate(yieldPerIon: c.thickTargetYield(resonanceEnergy: ecm, strength: strength, effectiveStopping: eps),
                            effectiveEnergy: ecm)
        }
    }

    private var efficiency: Double {
        useCurve ? (workbench.efficiencyCurve.fit()?.efficiency(at: gammaEnergy) ?? 0) : efficiencyPercent / 100
    }

    @ViewBuilder
    private func content(_ r: Reaction, _ c: ChargedChannel) -> some View {
        @Bindable var workbench = workbench
        let est = estimate(c)
        let pps = workbench.particlesPerSecond
        let reactions = (est.yieldPerIon ?? 0) * pps
        let signal = reactions * efficiency * branchingPercent / 100           // counts/s
        let background = backgroundPerHour / 3600
        let time = CountingStatistics.time(signal: signal, background: background, relativeUncertainty: goalPercent / 100,
                                           backgroundFromEqualTime: equalBackground)
        let after = CountingStatistics.relativeUncertainty(signal: signal, background: background, time: plannedHours * 3600,
                                                           backgroundFromEqualTime: equalBackground)

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    ReactionHeader(reaction: r) { editingSetup = true }
                    let d = Fmt.duration(time)
                    HeroNumber(value: signal > 0 ? d.value : "—", unit: signal > 0 ? d.unit : "",
                               caption: "Beam time for \(Fmt.significant(goalPercent, digits: 3)) % statistics")
                    HStack(spacing: 8) {
                        StatusBadge(text: "\(Fmt.significant(signal * 3600, digits: 3)) counts/h", symbol: "waveform", tint: .green)
                        StatusBadge(text: "S/B \(background > 0 ? Fmt.significant(signal / background, digits: 2) : "∞")",
                                    symbol: "chart.bar.fill", tint: .indigo)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                NumberField(title: "Isotope abundance in untagged material", value: $workbench.isotopicAbundance, unit: "%", range: 0...100)
                Text("Explicit isotope formulas such as [17O] contribute only to that isotope and do not use this abundance factor.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Cross section from", selection: $source.animation(.smooth)) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch source {
                case .sFactor:
                    if let t = workbench.stackOutcome?.target {
                        ValueRow(label: "Target layer", value: "\(Fmt.keV(t.energyIn, digits: 5))→\(Fmt.keV(t.energyOut, digits: 5))",
                                 unit: "keV", note: "Lab energies, from Energy Loss")
                    }
                    ValueRow(label: "S at the effective energy", value: est.effectiveEnergy.map { Fmt.significant(workbench.sFactorModel.s(at: $0)) } ?? "—",
                             unit: "keV b", note: "From the Reaction Rate model")
                case .crossSection:
                    LabeledContent("σ") {
                        HStack(spacing: 6) {
                            ScientificTextField(title: "σ", value: $sigma)
                            Picker("Unit", selection: $sigmaUnitRaw) {
                                ForEach(CrossSectionUnit.allCases) { Text($0.rawValue).tag($0.rawValue) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                    if let n = workbench.activeArealDensity {
                        ValueRow(label: "\(r.target.label) areal density", value: Fmt.significant(n / 1e15), unit: "10¹⁵ at/cm²")
                    }
                case .resonance:
                    NumberField(title: "E_R (lab)", value: $resonanceLab, unit: "keV", range: 1e-3...1e6)
                    ScientificField(title: "ωγ", value: $strength, unit: "eV")
                }
                Button {
                    editingTarget = true
                } label: {
                    LabeledContent("Target material", value: workbench.stoppingTarget?.name ?? "None")
                }
                .foregroundStyle(.primary)
                if let note = est.note {
                    Label(note, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
                }
                if let y = est.yieldPerIon {
                    ValueRow(label: "Yield", value: Fmt.significant(y), unit: "per ion")
                }
                if let e = est.effectiveEnergy {
                    ValueRow(label: "Effective energy (c.m.)", value: Fmt.keV(e, digits: 5), unit: "keV")
                }
            } header: {
                Text("Reaction yield")
            } footer: {
                Text(footer)
            }

            Section {
                NumberField(title: "Current", value: $workbench.beamCurrent, unit: "µA", range: 1e-9...1e6)
                Stepper(value: $workbench.chargeState, in: 1...92) {
                    LabeledContent("Charge state") { Text("\(workbench.chargeState)+").monospacedDigit() }
                }
                ValueRow(label: "Reactions", value: Fmt.significant(reactions), unit: "per s")
            } header: {
                Text("Beam")
            }

            Section {
                NumberField(title: "γ-ray energy", value: $gammaEnergy, unit: "keV", range: 1...1e5)
                if let e = workbench.reactionEnergyCM, r.ejectile.isPhoton {
                    Button("Capture to ground state, \(Fmt.keV(e + r.qValue, digits: 5)) keV") {
                        gammaEnergy = (e + r.qValue).rounded(toPlaces: 1)
                    }
                    .font(.callout)
                }
                Toggle("Efficiency from detector curve", isOn: $useCurve.animation(.smooth))
                if useCurve {
                    ValueRow(label: "Full-energy efficiency", value: Fmt.significant(100 * efficiency, digits: 3), unit: "%",
                             note: "Detector Response fit")
                } else {
                    NumberField(title: "Efficiency", value: $efficiencyPercent, unit: "%", range: 0...100)
                }
                NumberField(title: "Branching / γ intensity", value: $branchingPercent, unit: "%", range: 0...100)
                ValueRow(label: "Signal", value: Fmt.significant(signal * 3600), unit: "counts/h")
                ValueRow(label: "Per charge", value: Fmt.significant(signal / (workbench.beamCurrent * 1e-6) ), unit: "counts/C")
            } header: {
                Text("Detection")
            }

            Section {
                NumberField(title: "Background in peak", value: $backgroundPerHour, unit: "counts/h", range: 0...1e12)
                Toggle("Background from equal-time run", isOn: $equalBackground)
                NumberField(title: "Goal", value: $goalPercent, unit: "%", range: 0.01...100)
                let d = Fmt.duration(time)
                ValueRow(label: "Beam time", value: d.value, unit: d.unit)
                ValueRow(label: "Charge needed", value: Fmt.significant(time * workbench.beamCurrent * 1e-6, digits: 3), unit: "C")
                NumberField(title: "Planned time", value: $plannedHours, unit: "h", range: 1e-3...1e6)
                ValueRow(label: "Statistical uncertainty", value: Fmt.significant(100 * after, digits: 3), unit: "%",
                         note: "After the planned time")
                ValueRow(label: "Detection limit (Currie)", value: Fmt.significant(CountingStatistics.detectionLimit(backgroundCounts: background * plannedHours * 3600), digits: 3),
                         unit: "counts", note: "L_D in the planned time")
                if signal > 0 {
                    UncertaintyChart(signal: signal, background: background, equal: equalBackground, goal: goalPercent / 100)
                        .frame(height: 200)
                        .padding(.vertical, 6)
                }
            } header: {
                Text("Statistics")
            } footer: {
                Text("σ_net/N = √(S + kB)/S, k = 2 when the background comes from a run of equal length, 1 when it is known exactly. Excludes dead time and systematic uncertainties.")
            }
        }
        .groupedList()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .notebookSnapshot {
            var s = NotebookSnapshot(tool: .yieldEstimate, title: r.label, subtitle: "Beam time for \(Fmt.significant(goalPercent, digits: 3)) %")
            s.add("Yield", "Source", source.rawValue)
            if let y = est.yieldPerIon { s.add("Yield", "Yield", Fmt.significant(y), "per ion") }
            if let e = est.effectiveEnergy { s.add("Yield", "Effective energy (c.m.)", Fmt.keV(e), "keV") }
            s.add("Beam", "Current", Fmt.significant(workbench.beamCurrent), "µA")
            s.add("Beam", "Reactions", Fmt.significant(reactions), "per s")
            s.add("Detection", "γ energy", Fmt.keV(gammaEnergy), "keV")
            s.add("Detection", "Efficiency", Fmt.significant(100 * efficiency, digits: 3), "%")
            s.add("Detection", "Signal", Fmt.significant(signal * 3600), "counts/h")
            s.add("Statistics", "Background", Fmt.significant(backgroundPerHour), "counts/h")
            let d = Fmt.duration(time)
            s.add("Statistics", "Beam time", d.value, d.unit)
            return s
        }
    }

    private var footer: String {
        switch source {
        case .sFactor: "Y = ∫ σ(E)/ε_eff(E) dE across the target layer of Energy Loss, σ from the S factor of Reaction Rate including electron screening U_e."
        case .crossSection: "Thin target: Y = σ N_t, with N_t the active nuclei per cm² in the target layer."
        case .resonance: "Infinitely thick target: Y = (λ²/2)(m₁+m₂)/m₂ ωγ/ε_eff (the yield plateau)."
        }
    }
}

private struct UncertaintyChart: View {
    let signal: Double, background: Double, equal: Bool, goal: Double

    var body: some View {
        let t0 = CountingStatistics.time(signal: signal, background: background, relativeUncertainty: goal, backgroundFromEqualTime: equal)
        let lo = max(t0 / 100, 1), hi = max(t0 * 30, lo * 10)
        let pts: [(Double, Double)] = (0...60).map { i in
            let t = lo * pow(hi / lo, Double(i) / 60)
            return (t / 3600, 100 * CountingStatistics.relativeUncertainty(signal: signal, background: background, time: t, backgroundFromEqualTime: equal))
        }
        Chart {
            ForEach(pts, id: \.0) { p in
                LineMark(x: .value("Time", p.0), y: .value("Uncertainty", p.1))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            RuleMark(y: .value("Goal", goal * 100))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
            PointMark(x: .value("Time", t0 / 3600), y: .value("Uncertainty", goal * 100))
                .foregroundStyle(.green)
                .symbolSize(70)
        }
        .chartXScale(type: .log)
        .chartYScale(type: .log)
        .chartXAxisLabel("Beam time (h)", alignment: .leading)
        .chartYAxisLabel("Statistical uncertainty (%)")
        .accessibilityLabel("Statistical uncertainty versus beam time")
    }
}
