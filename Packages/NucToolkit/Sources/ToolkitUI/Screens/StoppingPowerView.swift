import Charts
import NucPhysKit
import SwiftUI
import UniformTypeIdentifiers

struct StoppingPowerView: View {
    @Environment(Workbench.self) private var workbench
    @State private var editingSetup = false
    @State private var editingTarget = false
    @State private var selection: Double?

    var body: some View {
        Group {
            if let calc = workbench.stoppingCalculator, let r = workbench.reaction {
                content(calc, ionLabel: r.projectile.label)
            } else {
                ContentUnavailableView {
                    Label("No beam ion", systemImage: "gauge.with.dots.needle.67percent")
                } description: {
                    Text("The stopping tools use the projectile and beam energy of the current reaction (Z ≤ 92).")
                } actions: {
                    Button("Edit Setup") { editingSetup = true }.buttonStyle(.glassProminent)
                }
            }
        }
        .navigationTitle("Stopping Power")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .trailingBar) { StoppingUnitMenu() }
            if let calc = workbench.stoppingCalculator, let r = workbench.reaction {
                ToolbarItem(placement: .trailingBar) {
                    ShareLink(item: StoppingTableExport(calculator: calc, ionLabel: r.projectile.plainLabel,
                                                        unit: workbench.stoppingUnit),
                              preview: SharePreview("Stopping table, \(r.projectile.plainLabel) in \(calc.target.name)",
                                                    image: Image(systemName: "tablecells"))) {
                        Label("Export Table", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
        .sheet(isPresented: $editingTarget) {
            if let t = workbench.stoppingTarget { TargetSheet(initial: t) }
        }
    }

    @ViewBuilder
    private func content(_ calc: StoppingCalculator, ionLabel: String) -> some View {
        @Bindable var workbench = workbench
        let unit = workbench.stoppingUnit
        let energy = workbench.beamEnergy
        let s = try? calc.stopping(at: energy)
        let range = try? calc.range(at: energy)

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    StoppingHeader(ion: calc.ion, ionLabel: ionLabel, target: calc.target,
                                   isReactionTarget: workbench.customTarget == nil) { editingTarget = true }
                    HeroNumber(value: s.map { Fmt.significant(calc.convert($0.total, to: unit)) } ?? "—",
                               unit: unit.label,
                               caption: "Total stopping at \(Fmt.energy(energy, unit: workbench.energyUnit)) \(workbench.energyUnit.label)")
                    if let s {
                        HStack(spacing: 8) {
                            StatusBadge(text: "Electronic \(Fmt.number(100 * s.electronic / s.total, decimals: 1)) %",
                                        symbol: "bolt.fill", tint: .orange)
                            StatusBadge(text: "Nuclear \(Fmt.number(100 * s.nuclear / s.total, decimals: 1)) %",
                                        symbol: "circle.hexagongrid.fill", tint: .purple)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                StoppingChart(calc: calc, unit: unit, beamEnergy: energy, selection: $selection)
                    .frame(height: 260)
                    .padding(.vertical, 8)
            } header: {
                Text("vs ion energy")
            } footer: {
                Text("Drag across the chart to read values. Log–log axes; nuclear stopping from SRIM's pair coefficients.")
            }

            Section {
                EnergyField(title: "Beam energy", keV: $workbench.beamEnergy, unit: workbench.energyUnit)
                if let s {
                    ValueRow(label: "Electronic", value: Fmt.significant(calc.convert(s.electronic, to: unit)), unit: unit.label)
                    ValueRow(label: "Nuclear", value: Fmt.significant(calc.convert(s.nuclear, to: unit)), unit: unit.label)
                    ValueRow(label: "Total", value: Fmt.significant(calc.convert(s.total, to: unit)), unit: unit.label)
                }
            } header: {
                Text("At the beam energy")
            }

            Section {
                if let range {
                    lengthRow("Projected range", range.projectedRange)
                    lengthRow("Longitudinal straggling", range.longitudinalStraggling)
                    lengthRow("Lateral straggling", range.lateralStraggling)
                    let areal = range.projectedRange * 1e-8 * calc.target.density * 1e3
                    ValueRow(label: "Range (areal)", value: Fmt.significant(areal), unit: "mg/cm²")
                } else {
                    Text("Range unavailable at this energy.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Range")
            } footer: {
                Text("Projected range and stragglings from the SR module's moment integration (Biersack), as SRIM tables them. Use TRIM for the shape of the range distribution.")
            }

            Section {
                Text("SRIM-2013 stopping (J. F. Ziegler, M. D. Ziegler, J. P. Biersack, NIM B 268, 1818 (2010)), ported from LunaSRIM by J. Skowronski. SRIM data are free for non-commercial use.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .groupedList()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .notebookSnapshot {
            var snap = NotebookSnapshot(tool: .stopping, title: "\(ionLabel) in \(calc.target.name)",
                                        subtitle: "\(Fmt.energy(energy, unit: workbench.energyUnit)) \(workbench.energyUnit.label)")
            snap.add("Input", "Energy", Fmt.energy(energy, unit: workbench.energyUnit), workbench.energyUnit.label)
            snap.add("Input", "Density", Fmt.significant(calc.target.density), "g/cm³")
            if let s {
                snap.add("Stopping", "Electronic", Fmt.significant(calc.convert(s.electronic, to: unit)), unit.label)
                snap.add("Stopping", "Nuclear", Fmt.significant(calc.convert(s.nuclear, to: unit)), unit.label)
                snap.add("Stopping", "Total", Fmt.significant(calc.convert(s.total, to: unit)), unit.label)
            }
            if let range {
                let l = Fmt.length(range.projectedRange)
                snap.add("Range", "Projected range", l.value, l.unit)
                let ls = Fmt.length(range.longitudinalStraggling)
                snap.add("Range", "Longitudinal straggling", ls.value, ls.unit)
                snap.add("Range", "Areal range", Fmt.significant(range.projectedRange * 1e-8 * calc.target.density * 1e3), "mg/cm²")
            }
            return snap
        }
        .animation(.smooth, value: workbench.stoppingUnit)
        .animation(.smooth, value: calc.target)
    }

    private func lengthRow(_ label: String, _ a: Double) -> some View {
        let l = Fmt.length(a)
        return ValueRow(label: label, value: l.value, unit: l.unit)
    }
}

/// Toolbar menu that picks one of SRIM's eight stopping units.
struct StoppingUnitMenu: View {
    @Environment(Workbench.self) private var workbench

    var body: some View {
        @Bindable var workbench = workbench
        Menu {
            Picker("Stopping unit", selection: $workbench.stoppingUnit) {
                ForEach(StoppingUnit.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            Label("Units", systemImage: "ruler")
        }
        .accessibilityLabel("Stopping units, \(workbench.stoppingUnit.label)")
    }
}

private struct StoppingChart: View {
    let calc: StoppingCalculator
    let unit: StoppingUnit
    let beamEnergy: Double
    @Binding var selection: Double?

    private struct Point: Identifiable {
        let id: Int
        let energy: Double
        let electronic: Double
        let nuclear: Double
        var total: Double { electronic + nuclear }
    }

    private enum Series: String, CaseIterable {
        case total = "Total", electronic = "Electronic", nuclear = "Nuclear"
        var color: Color {
            switch self {
            case .total: .accent
            case .electronic: .orange.opacity(0.55)
            case .nuclear: .purple
            }
        }
    }

    private var domain: ClosedRange<Double> {
        let lo = 1.0
        let hi = max(1e5, 1e4 * calc.ion.mass, beamEnergy * 10)
        return lo...hi
    }

    private func points() -> [Point] {
        let n = 160
        let a = log(domain.lowerBound), b = log(domain.upperBound)
        return (0..<n).compactMap { i in
            let e = exp(a + (b - a) * Double(i) / Double(n - 1))
            guard let s = try? calc.stopping(at: e) else { return nil }
            return Point(id: i, energy: e, electronic: calc.convert(s.electronic, to: unit),
                         nuclear: calc.convert(s.nuclear, to: unit))
        }
    }

    var body: some View {
        let pts = points()
        let yMax = (pts.map(\.total).max() ?? 1) * 2
        let yMin = max(yMax * 1e-4, pts.map(\.nuclear).filter { $0 > 0 }.min() ?? yMax * 1e-4)
        let probe = selection ?? beamEnergy
        let at = try? calc.stopping(at: probe)

        Chart {
            ForEach(Series.allCases, id: \.self) { series in
                // Points below the axis floor are left out rather than clamped to it.
                ForEach(pts.filter { value(series, $0) >= yMin }) { p in
                    LineMark(x: .value("Energy", p.energy),
                             y: .value("Stopping", value(series, p)),
                             series: .value("Series", series.rawValue))
                        .foregroundStyle(by: .value("Series", series.rawValue))
                        .lineStyle(StrokeStyle(lineWidth: series == .total ? 3 : 1.6, lineCap: .round,
                                               dash: series == .nuclear ? [5, 3] : []))
                        .interpolationMethod(.catmullRom)
                }
            }
            RuleMark(x: .value("Energy", probe))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
            if let at {
                PointMark(x: .value("Energy", probe), y: .value("Stopping", calc.convert(at.total, to: unit)))
                    .symbolSize(80)
                    .foregroundStyle(Color.accent)
                    .annotation(position: .top, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        VStack(spacing: 1) {
                            Text(energyLabel(probe)).foregroundStyle(.secondary)
                            Text(Fmt.significant(calc.convert(at.total, to: unit))).fontWeight(.semibold)
                        }
                        .font(.caption2)
                        .monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
            }
        }
        .chartForegroundStyleScale(domain: Series.allCases.map(\.rawValue), range: Series.allCases.map(\.color))
        .chartLegend(position: .top, alignment: .leading)
        .chartXScale(domain: domain, type: .log)
        .chartYScale(domain: yMin...yMax, type: .log)
        .chartXAxis {
            AxisMarks(values: decades(domain)) { v in
                AxisGridLine()
                AxisTick()
                AxisValueLabel { if let e = v.as(Double.self) { Text(energyLabel(e)) } }
            }
        }
        .chartYAxis {
            AxisMarks(values: decades(yMin...yMax)) { v in
                AxisGridLine()
                AxisValueLabel { if let y = v.as(Double.self) { Text(Fmt.significant(y, digits: 1)) } }
            }
        }
        .chartXAxisLabel("Energy", alignment: .leading)
        .chartYAxisLabel(unit.label)
        .chartXSelection(value: $selection)
        .sensoryFeedback(.selection, trigger: selection.map { Int(log10($0) * 4) })
        .accessibilityLabel("Stopping power versus ion energy")
    }

    private func value(_ s: Series, _ p: Point) -> Double {
        switch s {
        case .total: p.total
        case .electronic: p.electronic
        case .nuclear: p.nuclear
        }
    }

    private func decades(_ r: ClosedRange<Double>) -> [Double] {
        let a = Int(ceil(log10(r.lowerBound) - 1e-9)), b = Int(floor(log10(r.upperBound) + 1e-9))
        guard a <= b else { return [] }
        return (a...b).map { pow(10, Double($0)) }
    }

    private func energyLabel(_ keV: Double) -> String {
        func f(_ x: Double) -> String { x.formatted(.number.precision(.significantDigits(1...3)).grouping(.never)) }
        if keV >= 1e6 { return f(keV / 1e6) + " GeV" }
        if keV >= 1e3 { return f(keV / 1e3) + " MeV" }
        return f(keV) + " keV"
    }
}

/// SRIM-style stopping and range table from 1 keV to 1 GeV (or 5 GeV/u), exported as CSV on demand.
struct StoppingTableExport: Transferable {
    let calculator: StoppingCalculator
    let ionLabel: String
    let unit: StoppingUnit

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { item in
            Data(item.csv().utf8)
        }
        .suggestedFileName { "\($0.ionLabel)_in_\($0.calculator.target.name.replacingOccurrences(of: " ", with: "_")).csv" }
    }

    func csv() -> String {
        let t = calculator.target
        let emax = min(1e6, 5_000 * calculator.ion.mass * 1000)
        let rows = (try? calculator.rangeTable(emin: 1, emax: emax)) ?? []
        var out = "# \(ionLabel) (Z = \(calculator.ion.z), M = \(calculator.ion.mass) u) in \(t.name)\n"
        out += "# composition: " + zip(t.components, t.fractions).map {
            "\(Elements.symbol(z: $0.0.z) ?? "?") \($0.1) (M = \($0.0.mass) u)"
        }.joined(separator: "; ") + "\n"
        out += "# density \(t.density) g/cm3, \(t.isGas ? "gas" : "solid"), Bragg correction \(t.compoundCorrection)\n"
        out += "# SRIM-2013 stopping (Ziegler, Ziegler, Biersack) via a port of LunaSRIM; SR-module table, ZBL nuclear stopping\n"
        out += "energy_keV,electronic_\(unit.csvName),nuclear_\(unit.csvName),projected_range_A,longitudinal_straggling_A,lateral_straggling_A\n"
        for r in rows {
            out += [r.energy, calculator.convert(r.electronic, to: unit), calculator.convert(r.nuclear, to: unit),
                    r.projectedRange, r.longitudinalStraggling, r.lateralStraggling]
                .map { String(format: "%.6g", $0) }.joined(separator: ",") + "\n"
        }
        return out
    }
}

extension StoppingUnit {
    /// ASCII unit name for file headers.
    var csvName: String {
        switch self {
        case .eVPerAngstrom: "eV/A"
        case .keVPerMicron: "keV/um"
        case .MeVPerMillimetre: "MeV/mm"
        case .keVPerMicrogramCm2: "keV/(ug/cm2)"
        case .MeVPerMilligramCm2: "MeV/(mg/cm2)"
        case .keVPerMilligramCm2: "keV/(mg/cm2)"
        case .eVPer1e15AtomsCm2: "eV/(1e15 at/cm2)"
        case .reduced: "LSS"
        }
    }
}
