import Charts
import NucPhysKit
import SwiftUI

struct RutherfordView: View {
    @Environment(Workbench.self) private var workbench
    @State private var editingSetup = false
    @State private var angle = 135.0          // lab, degrees
    @State private var solidAngle = 1.0       // msr
    @State private var chargeState = 1

    var body: some View {
        Group {
            if let r = workbench.reaction, r.projectile.z > 0, r.target.z > 0 {
                content(r)
            } else {
                ContentUnavailableView {
                    Label("No charged beam", systemImage: "scope")
                } description: {
                    Text("Rutherford scattering of the reaction's projectile on its target needs both to be charged.")
                } actions: {
                    Button("Edit Setup") { editingSetup = true }.buttonStyle(.glassProminent)
                }
            }
        }
        .navigationTitle("Rutherford")
        .inlineTitle()
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
    }

    @ViewBuilder
    private func content(_ r: Reaction) -> some View {
        let energy = workbench.reactionEnergy
        let ruth = RutherfordScattering(projectile: r.projectile, target: r.target, beamEnergy: energy)
        let sols = ruth.at(labAngle: angle * .pi / 180)
        let unit = workbench.energyUnit
        // Target nuclei per cm² in the target layer of the Energy Loss tool.
        let areal: Double? = workbench.stoppingTarget.flatMap { t in
            workbench.activeAtomFraction.map { workbench.layerThickness * 1e-8 * t.atomDensity * $0 }
        }

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    ReactionHeader(reaction: r) { editingSetup = true }
                    if let s = sols.first {
                        let v = Fmt.crossSection(s.crossSectionLab)
                        HeroNumber(value: v.value, unit: "\(v.unit)/sr",
                                   caption: "\(r.projectile.label) on \(r.target.label), lab dσ/dΩ at \(Fmt.number(angle, decimals: 1))°")
                    } else {
                        HeroNumber(value: "—", unit: "b/sr", caption: "Beyond the maximum scattering angle")
                    }
                    HStack(spacing: 8) {
                        StatusBadge(text: "\(Fmt.energy(energy, unit: unit)) \(unit.label)", symbol: "bolt.fill", tint: .mint)
                        if sols.count > 1 {
                            StatusBadge(text: "Two solutions", symbol: "arrow.triangle.branch", tint: .orange)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                LabeledContent("Lab angle") {
                    Text("\(Fmt.number(angle, decimals: 1))°").monospacedDigit()
                }
                Slider(value: Binding(get: { angle }, set: { angle = ($0 * 2).rounded() / 2 }), in: 1...179) { Text("Lab angle") }
                TargetEnergyToggle()
            } header: {
                Text("Detector")
            }

            ForEach(Array(sols.enumerated()), id: \.offset) { i, s in
                Section {
                    ValueRow(label: "θ (c.m.)", value: Fmt.angle(s.thetaCM))
                    ValueRow(label: "Scattered energy", value: Fmt.energy(s.energy, unit: unit), unit: unit.label)
                    let cm = Fmt.crossSection(s.crossSectionCM)
                    ValueRow(label: "dσ/dΩ (c.m.)", value: cm.value, unit: "\(cm.unit)/sr")
                    let lab = Fmt.crossSection(s.crossSectionLab)
                    ValueRow(label: "dσ/dΩ (lab)", value: lab.value, unit: "\(lab.unit)/sr")
                    ValueRow(label: "dΩ_cm/dΩ_lab", value: Fmt.significant(s.crossSectionLab / s.crossSectionCM, digits: 5))
                } header: {
                    Text(sols.count > 1 ? (i == 0 ? "Forward solution" : "Backward solution") : "Scattered \(r.projectile.label)")
                }
            }

            Section {
                RutherfordChart(scattering: ruth, angle: angle)
                    .frame(height: 240)
                    .padding(.vertical, 8)
            } header: {
                Text("vs lab angle")
            }

            if let first = sols.first {
                Section {
                    NumberField(title: "Solid angle", value: $solidAngle, unit: "msr", range: 1e-6...4000)
                    Stepper(value: $chargeState, in: 1...max(1, r.projectile.z)) {
                        LabeledContent("Beam charge state") { Text("\(chargeState)+").monospacedDigit() }
                    }
                    if let areal {
                        ValueRow(label: "\(r.target.label) areal density", value: Fmt.significant(areal / 1e15), unit: "10¹⁵ at/cm²",
                                 note: "Energy Loss target layer")
                        let perMicroC = first.crossSectionLab * 1e-24 * solidAngle * 1e-3 * areal * 1e-6 / (Double(chargeState) * 1.602_176_634e-19)
                        ValueRow(label: "Counts per µC", value: Fmt.significant(perMicroC), note: "Elastic, at \(Fmt.number(angle, decimals: 1))°")
                    } else {
                        Label("The target material contains no \(r.target.elementName.lowercased()).", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                } header: {
                    Text("Monitor rate")
                } footer: {
                    Text("N = dσ/dΩ · ΔΩ · N_t · Q/(qe), for a thin target. Pure point-charge scattering: valid well below the Coulomb barrier; electron screening lowers it slightly at low energy (≈ 1% for light ions at a few hundred keV on heavy targets).")
                }
            }
        }
        .groupedList()
        .notebookSnapshot {
            var s = NotebookSnapshot(tool: .rutherford, title: "\(r.projectile.label) on \(r.target.label) at \(Fmt.number(angle, decimals: 1))°",
                                     subtitle: "\(Fmt.energy(energy, unit: unit)) \(unit.label)")
            s.add("Input", "Beam energy", Fmt.energy(energy, unit: unit), unit.label)
            s.add("Input", "Lab angle", Fmt.number(angle, decimals: 1), "°")
            for (i, sol) in sols.enumerated() {
                let sec = sols.count > 1 ? "Solution \(i + 1)" : "Result"
                s.add(sec, "θ (c.m.)", Fmt.angle(sol.thetaCM))
                s.add(sec, "Scattered energy", Fmt.energy(sol.energy, unit: unit), unit.label)
                let lab = Fmt.crossSection(sol.crossSectionLab)
                s.add(sec, "dσ/dΩ (lab)", lab.value, "\(lab.unit)/sr")
            }
            return s
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .sensoryFeedback(.selection, trigger: Int(angle / 5))
    }
}

private struct RutherfordChart: View {
    let scattering: RutherfordScattering
    let angle: Double

    private struct Point: Identifiable {
        let id: Int
        let theta: Double
        let sigma: Double
        let branch: String
    }

    var body: some View {
        let pts: [Point] = stride(from: 5.0, through: 175.0, by: 2.5).enumerated().flatMap { i, th in
            scattering.at(labAngle: th * .pi / 180).enumerated().map { j, s in
                Point(id: i * 2 + j, theta: th, sigma: s.crossSectionLab, branch: j == 0 ? "Forward" : "Backward")
            }
        }
        let yMax = (pts.map(\.sigma).max() ?? 1) * 2
        let yMin = max((pts.map(\.sigma).min() ?? 1e-6) / 2, 1e-12)
        let now = scattering.at(labAngle: angle * .pi / 180).first

        Chart {
            ForEach(pts) { p in
                LineMark(x: .value("θ", p.theta), y: .value("dσ/dΩ", p.sigma), series: .value("Branch", p.branch))
                    .foregroundStyle(p.branch == "Forward" ? Color.mint : Color.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            if let now {
                PointMark(x: .value("θ", angle), y: .value("dσ/dΩ", now.crossSectionLab))
                    .symbolSize(70)
                    .foregroundStyle(.mint)
            }
        }
        .chartXScale(domain: 0...180)
        .chartYScale(domain: yMin...yMax, type: .log)
        .chartXAxis {
            AxisMarks(values: [0, 30, 60, 90, 120, 150, 180]) { v in
                AxisGridLine(); AxisTick()
                AxisValueLabel { if let x = v.as(Double.self) { Text("\(Int(x))°") } }
            }
        }
        .chartYAxis {
            AxisMarks(values: decades(yMin...yMax)) { v in
                AxisGridLine()
                AxisValueLabel { if let y = v.as(Double.self) { Text(Fmt.crossSection(y, digits: 1).value + " " + Fmt.crossSection(y, digits: 1).unit) } }
            }
        }
        .chartXAxisLabel("θ (lab)", alignment: .leading)
        .chartYAxisLabel("per sr")
        .accessibilityLabel("Rutherford cross section versus laboratory angle")
    }
}
