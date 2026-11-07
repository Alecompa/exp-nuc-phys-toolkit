import Charts
import NucPhysKit
import SwiftUI

struct PenetrabilityView: View {
    @Environment(Workbench.self) private var workbench
    @State private var editingSetup = false

    private enum Side: String, CaseIterable, Identifiable {
        case entrance = "Entrance", exit = "Exit"
        var id: String { rawValue }
    }

    @State private var side = Side.entrance
    @State private var energy = 0.0           // keV, c.m. of the chosen channel
    @State private var l = 0
    @State private var fixedRadius = false
    @State private var radius = 5.0           // fm, when fixed
    @State private var width = 1.0            // Γ, eV
    @State private var curves: [PenetrabilityCurve.Point] = []

    var body: some View {
        Group {
            if let r = workbench.reaction, let c = channel(r) {
                content(r, c)
            } else {
                NoChargedChannelView(symbol: "wave.3.right", editingSetup: $editingSetup)
            }
        }
        .navigationTitle("Penetrability")
        .inlineTitle()
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
        .onAppear { if energy == 0 { resetEnergy() } }
        .onChange(of: side) { resetEnergy() }
    }

    private func channel(_ r: Reaction) -> ChargedChannel? {
        switch side {
        case .entrance: workbench.entranceChannel
        case .exit: ChargedChannel.exit(r).flatMap { $0.isCharged ? $0 : nil }
        }
    }

    /// The entrance c.m. energy at the reaction energy, or the exit-channel energy E + Q − Eₓ.
    private func resetEnergy() {
        guard let r = workbench.reaction, let e = workbench.reactionEnergyCM else { return }
        let value = side == .entrance ? e : e + r.qValue(residualExcitation: workbench.residualExcitation)
        energy = max(value, 1).rounded(toPlaces: 2)
    }

    @ViewBuilder
    private func content(_ r: Reaction, _ c: ChargedChannel) -> some View {
        @Bindable var workbench = workbench
        let rc = fixedRadius ? radius : c.radius(r0: workbench.channelRadiusR0)
        let e = max(energy, 1e-3)
        let p = c.penetrability(l: l, energy: e, radius: rc)
        let wigner = c.wignerLimit(radius: rc)                        // keV
        let reduced = p.penetrability > 0 ? width / (2 * p.penetrability) : .infinity   // eV
        let theta2 = reduced / (wigner * 1000)
        let exitAvailable = ChargedChannel.exit(r)?.isCharged == true

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    ReactionHeader(reaction: r) { editingSetup = true }
                    HeroNumber(value: Fmt.significant(p.penetrability), unit: "",
                               caption: "P\(Fmt.subscript(l)) for \(c.label) at \(Fmt.keV(e, digits: 4)) keV")
                    HStack(spacing: 8) {
                        StatusBadge(text: "ρ = \(Fmt.significant(p.rho, digits: 3))", symbol: "circle.dashed", tint: .cyan)
                        StatusBadge(text: "η = \(Fmt.significant(p.eta, digits: 3))", symbol: "wave.3.right", tint: .purple)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                if exitAvailable {
                    Picker("Channel", selection: $side.animation(.smooth)) {
                        ForEach(Side.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                NumberField(title: "Energy (c.m.)", value: $energy, unit: "keV", range: 1e-3...1e6)
                Stepper(value: $l.animation(.smooth), in: 0...10) {
                    LabeledContent("Orbital ℓ") { Text("\(l)").monospacedDigit() }
                }
                Toggle("Fixed channel radius", isOn: $fixedRadius.animation(.smooth))
                if fixedRadius {
                    NumberField(title: "Radius a", value: $radius, unit: "fm", range: 0.1...100)
                } else {
                    NumberField(title: "r₀", value: $workbench.channelRadiusR0, unit: "fm", range: 0.1...5)
                    ValueRow(label: "Radius a", value: Fmt.significant(rc, digits: 4), unit: "fm", note: "r₀(A₁¹ᐟ³ + A₂¹ᐟ³)")
                }
            } header: {
                Text("Channel · \(c.label)")
            }

            Section {
                ValueRow(label: "Penetrability P\(Fmt.subscript(l))", value: Fmt.significant(p.penetrability))
                ValueRow(label: "ln P\(Fmt.subscript(l))", value: Fmt.significant(p.lnP, digits: 6))
                ValueRow(label: "Shift factor S\(Fmt.subscript(l))", value: Fmt.significant(p.shift, digits: 5))
                ValueRow(label: "Coulomb barrier", value: Fmt.keV(c.coulombBarrier(radius: rc), digits: 4), unit: "keV")
                ValueRow(label: "Wigner limit γ²_W", value: Fmt.keV(wigner, digits: 4), unit: "keV", note: "3ħ²/(2μa²)")
                let sp = 2 * p.penetrability * wigner
                ValueRow(label: "Γ_W = 2Pγ²_W", value: Fmt.significant(sp * 1000), unit: "eV", note: "Single-particle limit")
            } header: {
                Text("Coulomb functions at a")
            } footer: {
                Text("P = ρ/(F² + G²) and S = ρ(FF′ + GG′)/(F² + G²) at ρ = ka, from F and G integrated numerically (accurate deep under the barrier).")
            }

            Section {
                ScientificField(title: "Partial width Γ", value: $width, unit: "eV")
                ValueRow(label: "Reduced width γ²", value: Fmt.significant(reduced), unit: "eV", note: "Γ/(2P)")
                ValueRow(label: "θ² = γ²/γ²_W", value: Fmt.significant(theta2),
                         note: theta2 > 1 ? "Above the Wigner limit" : nil)
            } header: {
                Text("Width ↔ reduced width")
            } footer: {
                Text("Observed (formal) widths; the R-matrix boundary-condition correction 1 + γ²dS/dE is not applied.")
            }

            Section {
                PenetrabilityCurve(points: curves, energy: e, l: l)
                    .frame(height: 250)
                    .padding(.vertical, 8)
            } header: {
                Text("Penetrability vs energy")
            }
            .task(id: CurveKey(channel: c, radius: rc, energy: e)) {
                let barrier = c.coulombBarrier(radius: rc)
                let lo = max(e / 20, 1), hi = max(barrier * 1.5, e * 4)
                curves = await Task.detached(priority: .userInitiated) {
                    PenetrabilityCurve.compute(channel: c, radius: rc, range: lo...hi)
                }.value
            }
        }
        .groupedList()
        .notebookSnapshot {
            var s = NotebookSnapshot(tool: .penetrability, title: "\(c.label) ℓ = \(l) at \(Fmt.keV(e)) keV")
            s.add("Input", "E (c.m.)", Fmt.keV(e, digits: 6), "keV")
            s.add("Input", "ℓ", "\(l)")
            s.add("Input", "Radius a", Fmt.significant(rc, digits: 4), "fm")
            s.add("Result", "Penetrability P", Fmt.significant(p.penetrability))
            s.add("Result", "Shift factor S", Fmt.significant(p.shift, digits: 5))
            s.add("Result", "Wigner limit γ²_W", Fmt.keV(wigner, digits: 4), "keV")
            s.add("Width", "Γ", Fmt.significant(width), "eV")
            s.add("Width", "γ²", Fmt.significant(reduced), "eV")
            s.add("Width", "θ²", Fmt.significant(theta2))
            return s
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
    }

    private struct CurveKey: Hashable {
        let channel: ChargedChannel
        let radius: Double
        /// Decade of the energy, so the range moves only on large changes.
        let decade: Int
        init(channel: ChargedChannel, radius: Double, energy: Double) {
            self.channel = channel; self.radius = radius; decade = Int(floor(log10(energy) * 2))
        }
    }
}

private struct PenetrabilityCurve: View {
    struct Point: Identifiable, Sendable {
        let id: Int
        let l: Int
        let e: Double
        let p: Double
    }

    let points: [Point]
    let energy: Double
    let l: Int

    nonisolated static let ls = [0, 1, 2, 3]

    nonisolated static func compute(channel c: ChargedChannel, radius: Double, range: ClosedRange<Double>) -> [Point] {
        var out: [Point] = []
        let n = 48
        for l in ls {
            for i in 0...n {
                let e = range.lowerBound * pow(range.upperBound / range.lowerBound, Double(i) / Double(n))
                let p = c.penetrability(l: l, energy: e, radius: radius).penetrability
                if p > 0 { out.append(Point(id: l * 1000 + i, l: l, e: e, p: p)) }
            }
        }
        return out
    }

    var body: some View {
        if points.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let xr = (points.map(\.e).min() ?? 1)...(points.map(\.e).max() ?? 10)
            let yMax = (points.map(\.p).max() ?? 1) * 3
            let yMin = max(points.map(\.p).min() ?? 1e-30, yMax * 1e-80)
            Chart {
                ForEach(points) { p in
                    LineMark(x: .value("E", p.e), y: .value("P", p.p), series: .value("ℓ", "ℓ = \(p.l)"))
                        .foregroundStyle(by: .value("ℓ", "ℓ = \(p.l)"))
                        .lineStyle(StrokeStyle(lineWidth: p.l == l ? 3 : 1.3, lineCap: .round))
                        .opacity(p.l == l ? 1 : 0.55)
                        .interpolationMethod(.catmullRom)
                }
                if xr.contains(energy) {
                    RuleMark(x: .value("E", energy))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartForegroundStyleScale(domain: Self.ls.map { "ℓ = \($0)" }, range: [.cyan, .blue, .indigo, .purple])
            .chartLegend(position: .top, alignment: .leading)
            .chartXScale(domain: xr, type: .log)
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
                    AxisValueLabel { if let y = v.as(Double.self) { PowerOfTenLabel(value: y) } }
                }
            }
            .chartXAxisLabel("E (c.m.), keV", alignment: .leading)
            .accessibilityLabel("Penetrability versus energy for ℓ from 0 to 3")
        }
    }
}

extension Fmt {
    static func `subscript`(_ n: Int) -> String {
        let map: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅",
                                           "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
        return String(String(n).map { map[$0] ?? $0 })
    }
}
