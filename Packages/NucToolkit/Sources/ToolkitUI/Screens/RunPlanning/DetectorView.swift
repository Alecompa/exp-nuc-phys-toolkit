import Charts
import NucPhysKit
import SwiftUI

struct DetectorView: View {
    @Environment(Workbench.self) private var workbench
    @AppStorage("detector.queryEnergy") private var energy = 1332.5
    @AppStorage("detector.radius") private var radius = 3.5
    @AppStorage("detector.distance") private var distance = 10.0
    @State private var confirmReset = false

    var body: some View {
        @Bindable var workbench = workbench
        let res = workbench.resolutionModel
        let fit = workbench.efficiencyCurve.fit()

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HeroNumber(value: Fmt.significant(res.fwhm(at: energy), digits: 3), unit: "keV FWHM",
                               caption: "At \(Fmt.keV(energy, digits: 5)) keV")
                    HStack(spacing: 8) {
                        if let fit {
                            StatusBadge(text: "ε = \(Fmt.significant(100 * fit.efficiency(at: energy), digits: 3)) %",
                                        symbol: "scope", tint: .green)
                        }
                        StatusBadge(text: "R = \(Fmt.significant(100 * res.fwhm(at: energy) / energy, digits: 2)) %",
                                    symbol: "chart.bar.xaxis", tint: .gray)
                    }
                }
                .padding(.vertical, 6)
                NumberField(title: "Energy", value: $energy, unit: "keV", range: 1...1e5)
            }

            Section {
                Menu {
                    ForEach(ResolutionModel.presets) { p in
                        Button(p.name) { withAnimation(.smooth) { workbench.resolutionModel = p.model } }
                    }
                } label: {
                    Label("Presets", systemImage: "list.bullet")
                }
                Picker("Detector type", selection: $workbench.resolutionModel.kind.animation(.smooth)) {
                    Text("Semiconductor").tag(ResolutionModel.Kind.semiconductor)
                    Text("Scintillator").tag(ResolutionModel.Kind.scintillator)
                }
                .pickerStyle(.segmented)
                switch res.kind {
                case .semiconductor:
                    NumberField(title: "Electronic noise", value: $workbench.resolutionModel.noise, unit: "keV", range: 0...100)
                    NumberField(title: "Fano factor", value: $workbench.resolutionModel.fano, range: 0...1)
                    NumberField(title: "Charge collection", value: $workbench.resolutionModel.collection, range: 0...0.1)
                case .scintillator:
                    NumberField(title: "Resolution at 662 keV", value: Binding(
                        get: { workbench.resolutionModel.resolutionAt662 * 100 },
                        set: { workbench.resolutionModel.resolutionAt662 = $0 / 100 }), unit: "%", range: 0.1...100)
                }
                ResolutionChart(model: res, energy: energy)
                    .frame(height: 180)
                    .padding(.vertical, 6)
            } header: {
                Text("Energy resolution")
            } footer: {
                Text(res.kind == .semiconductor
                     ? "FWHM² = a² + 2.355² F w E + (cE)², with w = 2.96 eV per pair in germanium: electronic noise, Fano statistics and incomplete charge collection."
                     : "FWHM ∝ √E (photo-electron statistics), scaled to the resolution at 662 keV.")
            }

            Section {
                if let fit {
                    EfficiencyChart(curve: workbench.efficiencyCurve, fit: fit, energy: energy)
                        .frame(height: 230)
                        .padding(.vertical, 6)
                    ValueRow(label: "ε at \(Fmt.keV(energy, digits: 5)) keV", value: Fmt.significant(100 * fit.efficiency(at: energy), digits: 4), unit: "%")
                    ValueRow(label: "χ²/ν", value: fit.reducedChiSquared.map { Fmt.significant($0, digits: 3) } ?? "—",
                             note: "\(fit.degreesOfFreedom) degrees of freedom")
                } else {
                    Label("Need at least \(workbench.efficiencyCurve.order + 1) points for this order.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Stepper(value: $workbench.efficiencyCurve.order.animation(.smooth), in: 1...4) {
                    LabeledContent("Polynomial order in ln E") { Text("\(workbench.efficiencyCurve.order)").monospacedDigit() }
                }
            } header: {
                Text("Full-energy-peak efficiency")
            } footer: {
                Text("ln ε = Σ aᵢ ln(E/1 MeV)ⁱ, weighted by the point uncertainties. The default points are an illustrative coaxial HPGe at 10 cm: replace them with your calibration.")
            }

            Section {
                ForEach($workbench.efficiencyCurve.points) { $p in
                    EfficiencyPointRow(point: $p)
                }
                .onDelete { workbench.efficiencyCurve.points.remove(atOffsets: $0) }
                Button {
                    let e = (workbench.efficiencyCurve.points.map(\.energy).max() ?? 1000) * 1.5
                    let eff = fit?.efficiency(at: e) ?? 0.001
                    withAnimation(.smooth) {
                        workbench.efficiencyCurve.points.append(.init(energy: e.rounded(), efficiency: eff))
                    }
                } label: {
                    Label("Add Point", systemImage: "plus.circle.fill")
                }
                Button("Reset to Example", role: .destructive) { confirmReset = true }
            } header: {
                Text("Calibration points · E (keV), ε (%), uncertainty (%)")
            }

            Section {
                NumberField(title: "Crystal radius", value: $radius, unit: "cm", range: 0...100)
                NumberField(title: "Distance to face", value: $distance, unit: "cm", range: 0...1e4)
                let omega = Geometry.diskSolidAngle(radius: radius, distance: distance)
                ValueRow(label: "Solid angle", value: Fmt.significant(omega, digits: 4), unit: "sr")
                ValueRow(label: "Geometric efficiency", value: Fmt.significant(100 * omega / (4 * .pi), digits: 4), unit: "% of 4π")
            } header: {
                Text("Geometry")
            } footer: {
                Text("Point source on the detector axis. The full-energy efficiency is this fraction times the intrinsic photopeak efficiency.")
            }
        }
        .groupedList()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .navigationTitle("Detector Response")
        .inlineTitle()
        .confirmationDialog("Replace your calibration points with the example?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { withAnimation(.smooth) { workbench.efficiencyCurve = .example } }
        }
        .notebookSnapshot {
            var s = NotebookSnapshot(tool: .detector, title: "Detector at \(Fmt.keV(energy, digits: 5)) keV",
                                     subtitle: res.kind == .semiconductor ? "Semiconductor" : "Scintillator")
            s.add("Resolution", "FWHM", Fmt.significant(res.fwhm(at: energy), digits: 4), "keV")
            if let fit {
                s.add("Efficiency", "ε", Fmt.significant(100 * fit.efficiency(at: energy), digits: 4), "%")
                for (i, c) in fit.coefficients.enumerated() { s.add("Efficiency", "a\(i)", Fmt.significant(c, digits: 6)) }
            }
            for p in workbench.efficiencyCurve.points {
                s.add("Calibration points", Fmt.keV(p.energy) + " keV", Fmt.significant(100 * p.efficiency, digits: 4), "%")
            }
            return s
        }
    }
}

private struct EfficiencyPointRow: View {
    @Binding var point: EfficiencyCurve.Point

    var body: some View {
        HStack(spacing: 10) {
            TextField("E", value: $point.energy, format: .number.precision(.significantDigits(1...7)).grouping(.never))
                .monospacedDigit().decimalKeyboard()
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("keV").foregroundStyle(.secondary).font(.caption)
            TextField("ε", value: Binding(get: { point.efficiency * 100 }, set: { point.efficiency = max(0, $0) / 100 }),
                      format: .number.precision(.significantDigits(1...5)).grouping(.never))
                .monospacedDigit().decimalKeyboard()
                .multilineTextAlignment(.trailing)
            Text("%").foregroundStyle(.secondary).font(.caption)
            TextField("±", value: Binding(get: { point.relativeUncertainty * 100 }, set: { point.relativeUncertainty = max(0.01, $0) / 100 }),
                      format: .number.precision(.significantDigits(1...3)).grouping(.never))
                .monospacedDigit().decimalKeyboard()
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
            Text("±%").foregroundStyle(.secondary).font(.caption)
        }
    }
}

private struct ResolutionChart: View {
    let model: ResolutionModel
    let energy: Double
    var body: some View {
        let pts = (0...60).map { i -> (Double, Double) in
            let e = 20 * pow(500.0, Double(i) / 60)
            return (e, model.fwhm(at: e))
        }
        Chart {
            ForEach(pts, id: \.0) { p in
                LineMark(x: .value("E", p.0), y: .value("FWHM", p.1))
                    .foregroundStyle(.gray)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            PointMark(x: .value("E", energy), y: .value("FWHM", model.fwhm(at: energy)))
                .foregroundStyle(Color.accent)
                .symbolSize(60)
        }
        .chartXScale(domain: 20...10000, type: .log)
        .chartXAxis {
            AxisMarks(values: [10, 30, 100, 300, 1000, 3000, 10000]) { v in
                AxisGridLine(); AxisTick()
                AxisValueLabel { if let x = v.as(Double.self) { Text(x >= 1000 ? "\(Int(x / 1000)) MeV" : "\(Int(x))") } }
            }
        }
        .chartXAxisLabel("E (keV)", alignment: .leading)
        .chartYAxisLabel("FWHM (keV)")
    }
}

private struct EfficiencyChart: View {
    let curve: EfficiencyCurve
    let fit: EfficiencyCurve.Fit
    let energy: Double

    var body: some View {
        let es = curve.points.map(\.energy) + [energy]
        let lo = max(10, (es.min() ?? 50) / 1.5), hi = (es.max() ?? 3000) * 1.5
        let line = (0...80).map { i -> (Double, Double) in
            let e = lo * pow(hi / lo, Double(i) / 80)
            return (e, 100 * fit.efficiency(at: e))
        }
        Chart {
            ForEach(line, id: \.0) { p in
                LineMark(x: .value("E", p.0), y: .value("ε", p.1))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(curve.points) { p in
                PointMark(x: .value("E", p.energy), y: .value("ε", 100 * p.efficiency))
                    .foregroundStyle(.primary)
                    .symbolSize(30)
            }
            RuleMark(x: .value("E", energy))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
        }
        .chartXScale(domain: lo...hi, type: .log)
        .chartXAxis {
            AxisMarks(values: [10, 30, 100, 300, 1000, 3000, 10000]) { v in
                AxisGridLine(); AxisTick()
                AxisValueLabel { if let x = v.as(Double.self) { Text(x >= 1000 ? "\(Int(x / 1000)) MeV" : "\(Int(x))") } }
            }
        }
        .chartYScale(type: .log)
        .chartXAxisLabel("E (keV)", alignment: .leading)
        .chartYAxisLabel("ε (%)")
        .accessibilityLabel("Efficiency curve with calibration points")
    }
}
