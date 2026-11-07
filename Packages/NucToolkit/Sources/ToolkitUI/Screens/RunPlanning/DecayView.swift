import Charts
import NucPhysKit
import SwiftUI

struct DecayView: View {
    @AppStorage("decay.nuclide") private var nuclideText = "60Co"
    @AppStorage("decay.customHalfLife") private var useCustom = false
    @AppStorage("decay.halfLifeValue") private var customValue = 1.0
    @AppStorage("decay.halfLifeUnit") private var customUnit = TimeUnit.h
    @AppStorage("decay.activity") private var activityValue = 10.0
    @AppStorage("decay.activityUnit") private var activityUnit = ActivityUnit.kBq
    @AppStorage("decay.time") private var timeValue = 1.0
    @AppStorage("decay.timeUnit") private var timeUnit = TimeUnit.y
    @AppStorage("decay.fraction") private var fractionPercent = 1.0

    var body: some View {
        let state = Nubase.nubase2020.state(named: nuclideText)
        let halfLife: Double? = useCustom ? customValue * customUnit.scale : state?.halfLife
        let a0 = activityValue * activityUnit.scale
        let t = timeValue * timeUnit.scale
        let molar: Double? = state.flatMap { s in
            MassTable.ame2020.nuclide(z: s.z, a: s.a).map { $0.atomicMass / PhysicalConstants.atomicMassUnit }
        } ?? state.map { Double($0.a) }

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    if let h = halfLife, h.isFinite, h > 0 {
                        let at = Fmt.activity(RadioactiveDecay.activity(initial: a0, elapsed: t, halfLife: h))
                        HeroNumber(value: at.value, unit: at.unit,
                                   caption: "After \(Fmt.significant(timeValue)) \(timeUnit.rawValue)")
                        HStack(spacing: 8) {
                            StatusBadge(text: "T½ \(Fmt.halfLife(h, digits: 4))", symbol: "hourglass", tint: .cyan)
                            StatusBadge(text: "\(Fmt.significant(100 * pow(0.5, t / h), digits: 3)) % left", symbol: "chart.line.downtrend.xyaxis", tint: .purple)
                        }
                    } else if halfLife == .infinity {
                        Label("\(state?.label ?? nuclideText) is stable.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Unknown nuclide. Type e.g. 60Co, 26mAl or 241Am.", systemImage: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                LabeledContent("Nuclide") {
                    TextField("e.g. 137Cs", text: $nuclideText)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .disabled(useCustom)
                }
                Toggle("Custom half-life", isOn: $useCustom.animation(.smooth))
                if useCustom {
                    LabeledContent("Half-life") {
                        HStack(spacing: 6) {
                            ScientificTextField(title: "Half-life", value: $customValue)
                            Picker("Unit", selection: $customUnit) {
                                ForEach(TimeUnit.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                } else if let s = state {
                    ValueRow(label: "Half-life", value: s.halfLifeText.isEmpty ? Fmt.halfLife(s.halfLife) : s.halfLifeText)
                    if !s.spinParity.isEmpty { ValueRow(label: "Jπ", value: s.spinParity) }
                    if !s.decayModes.isEmpty {
                        ValueRow(label: "Decay", value: s.decayModes.prefix(3).map(\.text).joined(separator: ", "))
                    }
                }
            } header: {
                Text("Nuclide")
            } footer: {
                if !useCustom { Text("Half-lives from NUBASE2020. Isomers are written with m, e.g. 26mAl, 178m2Hf.") }
            }

            if let h = halfLife, h.isFinite, h > 0 {
                let lambda = RadioactiveDecay.decayConstant(halfLife: h)
                Section {
                    LabeledContent("Initial activity") {
                        HStack(spacing: 6) {
                            ScientificTextField(title: "Activity", value: $activityValue)
                            Picker("Unit", selection: $activityUnit) {
                                ForEach(ActivityUnit.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                    let n = RadioactiveDecay.atoms(activity: a0, halfLife: h)
                    ValueRow(label: "Atoms", value: Fmt.significant(n))
                    if let molar {
                        ValueRow(label: "Mass", value: Fmt.significant(RadioactiveDecay.mass(atoms: n, molarMass: molar), digits: 3), unit: "g")
                        ValueRow(label: "Specific activity", value: Fmt.significant(RadioactiveDecay.activity(atoms: RadioactiveDecay.atoms(mass: 1, molarMass: molar), halfLife: h), digits: 4),
                                 unit: "Bq/g")
                    }
                    ValueRow(label: "Decay constant λ", value: Fmt.significant(lambda), unit: "s⁻¹")
                    let tau = Fmt.duration(1 / lambda)
                    ValueRow(label: "Mean life τ", value: tau.value, unit: tau.unit)
                } header: {
                    Text("Amount")
                }

                Section {
                    LabeledContent("Elapsed time") {
                        HStack(spacing: 6) {
                            ScientificTextField(title: "Time", value: $timeValue)
                            Picker("Unit", selection: $timeUnit) {
                                ForEach(TimeUnit.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                    let at = Fmt.activity(RadioactiveDecay.activity(initial: a0, elapsed: t, halfLife: h))
                    ValueRow(label: "Activity", value: at.value, unit: at.unit)
                    ValueRow(label: "Remaining fraction", value: Fmt.significant(pow(0.5, t / h), digits: 5))
                    ValueRow(label: "Decays in the interval", value: Fmt.significant(RadioactiveDecay.decays(initial: a0, from: 0, to: t, halfLife: h)))
                    DecayChart(a0: a0, halfLife: h, t: t, unit: timeUnit)
                        .frame(height: 200)
                        .padding(.vertical, 6)
                } header: {
                    Text("Decay")
                }

                Section {
                    NumberField(title: "Fraction left", value: $fractionPercent, unit: "%", range: 1e-12...99.999)
                    let d = Fmt.duration(RadioactiveDecay.time(toFraction: fractionPercent / 100, halfLife: h))
                    ValueRow(label: "Time needed", value: d.value, unit: d.unit)
                } header: {
                    Text("Time to decay")
                }
            }
        }
        .groupedList()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .navigationTitle("Decay Calculator")
        .inlineTitle()
        .notebookSnapshot {
            var s = NotebookSnapshot(tool: .decay, title: "Decay of \(useCustom ? "custom nuclide" : (state?.label ?? nuclideText))",
                                     subtitle: "\(Fmt.significant(timeValue)) \(timeUnit.rawValue)")
            s.add("Input", "Half-life", Fmt.halfLife(halfLife))
            s.add("Input", "Initial activity", Fmt.significant(activityValue), activityUnit.rawValue)
            if let h = halfLife, h.isFinite, h > 0 {
                let at = Fmt.activity(RadioactiveDecay.activity(initial: a0, elapsed: t, halfLife: h))
                s.add("Result", "Activity after \(Fmt.significant(timeValue)) \(timeUnit.rawValue)", at.value, at.unit)
                s.add("Result", "Atoms", Fmt.significant(RadioactiveDecay.atoms(activity: a0, halfLife: h)))
            }
            return s
        }
    }
}

private struct DecayChart: View {
    let a0: Double, halfLife: Double, t: Double
    let unit: TimeUnit

    var body: some View {
        let span = max(t * 1.25, halfLife * 3)
        let pts = (0...80).map { i -> (Double, Double) in
            let x = span * Double(i) / 80
            return (x / unit.scale, RadioactiveDecay.activity(initial: a0, elapsed: x, halfLife: halfLife) / a0 * 100)
        }
        Chart {
            ForEach(pts, id: \.0) { p in
                AreaMark(x: .value("t", p.0), y: .value("A", p.1))
                    .foregroundStyle(.purple.opacity(0.12))
                LineMark(x: .value("t", p.0), y: .value("A", p.1))
                    .foregroundStyle(.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            PointMark(x: .value("t", t / unit.scale), y: .value("A", pow(0.5, t / halfLife) * 100))
                .foregroundStyle(.purple)
                .symbolSize(60)
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: 0...(span / unit.scale))
        .chartXAxisLabel("t (\(unit.rawValue))", alignment: .leading)
        .chartYAxisLabel("A/A₀ (%)")
        .accessibilityLabel("Activity versus time")
    }
}
