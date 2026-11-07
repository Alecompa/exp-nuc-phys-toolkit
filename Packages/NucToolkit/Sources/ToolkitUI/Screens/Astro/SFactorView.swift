import Charts
import NucPhysKit
import SwiftUI

enum CrossSectionUnit: String, CaseIterable, Identifiable {
    case b, mb, µb, nb, pb, fb
    var id: String { rawValue }
    /// barn per unit
    var scale: Double {
        switch self {
        case .b: 1
        case .mb: 1e-3
        case .µb: 1e-6
        case .nb: 1e-9
        case .pb: 1e-12
        case .fb: 1e-15
        }
    }
}

struct SFactorView: View {
    @Environment(Workbench.self) private var workbench
    @State private var editingSetup = false

    private enum Direction: String, CaseIterable, Identifiable {
        case toSigma = "S → σ", toS = "σ → S"
        var id: String { rawValue }
    }

    @State private var direction = Direction.toSigma
    @State private var energy = 0.0                // keV, c.m.
    @State private var sValue = 1.0                // keV b
    @State private var sigmaValue = 1.0            // in sigmaUnit
    @State private var sigmaUnit = CrossSectionUnit.nb
    @State private var screened = false            // σ input is the measured (screened) value

    var body: some View {
        Group {
            if let r = workbench.reaction, let c = workbench.entranceChannel {
                content(r, c)
            } else {
                NoChargedChannelView(symbol: "function", editingSetup: $editingSetup)
            }
        }
        .navigationTitle("S-Factor ↔ σ")
        .inlineTitle()
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
        .onAppear {
            if energy == 0 { energy = (workbench.reactionEnergyCM ?? 100).rounded(toPlaces: 3) }
            if sValue == 1 { sValue = workbench.sFactorModel.s(at: energy) }
        }
    }

    @ViewBuilder
    private func content(_ r: Reaction, _ c: ChargedChannel) -> some View {
        @Bindable var workbench = workbench
        let e = max(energy, 1e-3)
        let ue = workbench.screeningPotential
        let f = c.screeningFactor(energy: e, potential: ue)
        // Bare quantities.
        let sBare: Double = direction == .toSigma ? sValue
            : c.sFactor(crossSection: sigmaValue * sigmaUnit.scale / (screened ? f : 1), energy: e)
        let sigmaBare = c.crossSection(sFactor: sBare, energy: e)
        let hero = direction == .toSigma ? Fmt.crossSection(sigmaBare) : (Fmt.significant(sBare), "keV b")

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    ReactionHeader(reaction: r) { editingSetup = true }
                    HeroNumber(value: hero.0, unit: hero.1,
                               caption: direction == .toSigma ? "Bare cross section" : "Bare S factor")
                    HStack(spacing: 8) {
                        StatusBadge(text: "η = \(Fmt.significant(c.sommerfeld(e)))", symbol: "wave.3.right", tint: .purple)
                        if ue > 0 {
                            StatusBadge(text: "Screening ×\(Fmt.significant(f, digits: 4))",
                                        symbol: "circle.dotted.circle", tint: .indigo)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                Picker("Direction", selection: $direction.animation(.smooth)) {
                    ForEach(Direction.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                NumberField(title: "Energy (c.m.)", value: $energy, unit: "keV", range: 1e-3...1e6)
                if let ecm = workbench.reactionEnergyCM, abs(ecm.rounded(toPlaces: 3) - energy) > 1e-6 {
                    Button("Use the reaction energy, \(Fmt.keV(ecm, digits: 6)) keV") {
                        withAnimation(.smooth) { energy = ecm.rounded(toPlaces: 3) }
                    }
                    .font(.callout)
                }
                if direction == .toSigma {
                    NumberField(title: "S factor", value: $sValue, unit: "keV b")
                    Button("Take S(E) from the rate model") {
                        withAnimation(.smooth) { sValue = workbench.sFactorModel.s(at: e) }
                    }
                    .font(.callout)
                } else {
                    LabeledContent("Cross section") {
                        HStack(spacing: 6) {
                            TextField("σ", value: $sigmaValue, format: .number.precision(.significantDigits(1...7)).grouping(.never))
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .decimalKeyboard()
                            Picker("Unit", selection: $sigmaUnit) {
                                ForEach(CrossSectionUnit.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                    Toggle("Measured (screened) σ", isOn: $screened.animation(.smooth))
                }
            } header: {
                Text("Input")
            }

            Section {
                NumberField(title: "Screening U_e", value: $workbench.screeningPotential, unit: "eV", range: 0...1e5)
                ValueRow(label: "Enhancement f", value: Fmt.significant(f, digits: 5), note: "exp(πη U_e/E)")
            } header: {
                Text("Electron screening")
            } footer: {
                Text("A laboratory cross section is the bare one × f (Assenbaum, Langanke & Rolfs 1987). U_e is typically 0.1–1 keV for light targets; the adiabatic limit is the difference in electron binding energies of the atoms.")
            }

            Section {
                ValueRow(label: "S factor (bare)", value: Fmt.significant(sBare), unit: "keV b")
                let sb = Fmt.crossSection(sigmaBare)
                ValueRow(label: "σ bare", value: sb.value, unit: sb.unit)
                let ss = Fmt.crossSection(sigmaBare * f)
                ValueRow(label: "σ screened", value: ss.value, unit: ss.unit, note: "In the laboratory")
                ValueRow(label: "Sommerfeld η", value: Fmt.significant(c.sommerfeld(e)))
                ValueRow(label: "exp(−2πη)", value: Fmt.significant(c.gamowFactor(e), digits: 4))
                ValueRow(label: "Lab energy", value: Fmt.keV(c.labEnergy(cm: e), digits: 6), unit: "keV")
            } header: {
                Text("At \(Fmt.keV(e, digits: 5)) keV (c.m.)")
            } footer: {
                Text("σ(E) = S(E)/E · exp(−2πη), with 2πη = √(E_G/E) and E_G = \(Fmt.significant(c.gamowEnergy / 1000, digits: 5)) MeV.")
            }

            Section {
                SigmaChart(channel: c, model: workbench.sFactorModel, energy: e, screening: ue)
                    .frame(height: 240)
                    .padding(.vertical, 8)
            } header: {
                Text("σ(E) from the rate model")
            } footer: {
                Text("Bare (solid) and screened (dashed) cross sections from the S factor set in Reaction Rate.")
            }
        }
        .groupedList()
        .notebookSnapshot {
            var s = NotebookSnapshot(tool: .sFactor, title: "\(r.label) at \(Fmt.keV(e)) keV",
                                     subtitle: "U_e = \(Fmt.significant(ue, digits: 3)) eV")
            s.add("Input", "E (c.m.)", Fmt.keV(e, digits: 6), "keV")
            s.add("Input", "U_e", Fmt.significant(ue, digits: 3), "eV")
            s.add("Result", "S factor (bare)", Fmt.significant(sBare), "keV b")
            let sb = Fmt.crossSection(sigmaBare), ss = Fmt.crossSection(sigmaBare * f)
            s.add("Result", "σ bare", sb.value, sb.unit)
            s.add("Result", "σ screened", ss.value, ss.unit)
            s.add("Result", "Enhancement f", Fmt.significant(f, digits: 5))
            s.add("Result", "Sommerfeld η", Fmt.significant(c.sommerfeld(e)))
            return s
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
    }
}

private struct SigmaChart: View {
    let channel: ChargedChannel
    let model: SFactorModel
    let energy: Double
    let screening: Double

    private struct Point: Identifiable {
        let id: Int
        let e: Double, bare: Double, screened: Double
    }

    var body: some View {
        let lo = max(1, energy / 10), hi = max(energy * 5, lo * 20)
        let pts: [Point] = (0...100).compactMap { i in
            let e = lo * pow(hi / lo, Double(i) / 100)
            let s = channel.crossSection(sFactor: model.s(at: e), energy: e)
            guard s > 0, s.isFinite else { return nil }
            return Point(id: i, e: e, bare: s, screened: s * channel.screeningFactor(energy: e, potential: screening))
        }
        let yMin = max(pts.map(\.bare).min() ?? 1e-30, 1e-60)
        let yMax = (pts.map(\.screened).max() ?? 1) * 3

        Chart {
            ForEach(pts) { p in
                LineMark(x: .value("E", p.e), y: .value("σ", p.bare), series: .value("S", "Bare"))
                    .foregroundStyle(.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                if screening > 0 {
                    LineMark(x: .value("E", p.e), y: .value("σ", p.screened), series: .value("S", "Screened"))
                        .foregroundStyle(.indigo.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
            }
            RuleMark(x: .value("E", energy))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
        }
        .chartXScale(domain: lo...hi, type: .log)
        .chartYScale(domain: yMin...yMax, type: .log)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                AxisGridLine(); AxisTick()
                AxisValueLabel { if let x = v.as(Double.self) { Text(Fmt.significant(x, digits: 2)) } }
            }
        }
        .chartYAxis {
            AxisMarks(values: sparseDecades(yMin...yMax)) { v in
                AxisGridLine()
                AxisValueLabel { if let y = v.as(Double.self) { Text(Fmt.crossSection(y, digits: 1).value + " " + Fmt.crossSection(y, digits: 1).unit) } }
            }
        }
        .chartXAxisLabel("E (c.m.), keV", alignment: .leading)
        .accessibilityLabel("Cross section versus energy")
    }
}

/// About five decade ticks across a wide log range, at a round step (1, 2, 5, 10, 20… decades).
func sparseDecades(_ r: ClosedRange<Double>) -> [Double] {
    let a = Int(ceil(log10(r.lowerBound) - 1e-9)), b = Int(floor(log10(r.upperBound) + 1e-9))
    guard a <= b else { return [] }
    let step = [1, 2, 5, 10, 20, 50].first { (b - a) / $0 <= 5 } ?? 100
    return (a...b).filter { $0 % step == 0 }.map { pow(10, Double($0)) }
}

extension Double {
    func rounded(toPlaces n: Int) -> Double {
        let p = pow(10, Double(n))
        return (self * p).rounded() / p
    }
}
