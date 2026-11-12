import Charts
import NucPhysKit
import SwiftUI

struct KinematicsView: View {
    @State private var focusedPlot = false
    @Environment(Workbench.self) private var workbench
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 45 // ejectile lab angle, degrees
    @State private var quantity: PlotQuantity = .ejectileEnergy
    @State private var chartSelection: Double?
    @State private var editingSetup = false

    var body: some View {
        @Bindable var workbench = workbench
        let unit = workbench.energyUnit

        Group {
            if let r = workbench.reaction {
                let k = TwoBodyKinematics(reaction: r, beamEnergy: workbench.reactionEnergy,
                                          residualExcitation: workbench.residualExcitation)
                content(reaction: r, kin: k, unit: unit)
            } else {
                ContentUnavailableView {
                    Label("No valid reaction", systemImage: "arrow.triangle.branch")
                } description: {
                    Text(workbench.reactionError?.localizedDescription ?? "Enter a reaction first.")
                } actions: {
                    Button("Edit Setup") { editingSetup = true }.buttonStyle(.glassProminent)
                }
            }
        }
        .navigationTitle("Kinematics")
        .inlineTitle()
        .hidingTabBar()
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
    }

    /// Full table, 0.5° steps, both branches, energies in keV.
    static func csv(_ r: Reaction, _ k: TwoBodyKinematics, excitation ex: Double) -> String {
        var out = "# \(r.plainLabelForFile), Ebeam = \(k.beamEnergy) keV, Ex = \(ex) keV\n"
        out += "theta_lab_deg,branch,E_ejectile_keV,theta_cm_deg,E_residual_keV,theta_residual_deg,dOmegaCM_dOmegaLab\n"
        let limit = k.maxEjectileAngle.map { $0 * 180 / .pi } ?? 180
        for i in 0...360 {
            let deg = Double(i) * 0.5
            guard deg <= limit + 1e-9 else { break }
            for (b, sol) in k.solutions(labAngle: deg * .pi / 180).enumerated() {
                out += [String(format: "%.1f", deg), b == 0 ? "high" : "low",
                        String(format: "%.4f", sol.ejectileEnergy), String(format: "%.4f", sol.thetaCM * 180 / .pi),
                        String(format: "%.4f", sol.residualEnergy), String(format: "%.4f", sol.residualAngle * 180 / .pi),
                        String(format: "%.6g", sol.jacobian)].joined(separator: ",") + "\n"
            }
        }
        return out
    }

    @ViewBuilder
    private func content(reaction r: Reaction, kin k: TwoBodyKinematics, unit: EnergyUnit) -> some View {
        @Bindable var workbench = workbench
        let solutions = k.solutions(labAngle: angle.radians)
        let ejectileName = r.ejectile.isPhoton ? "γ" : r.ejectile.label

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    ReactionHeader(reaction: r) { editingSetup = true }
                    if let first = solutions.first {
                        HeroNumber(
                            value: Fmt.energy(first.ejectileEnergy, unit: unit, decimals: unit == .keV ? 2 : 5),
                            unit: unit.label,
                            caption: "\(ejectileName) energy at \(Fmt.number(angle, decimals: AngleControl.decimals(limit: k.maxEjectileAngle?.degrees)))°"
                        )
                    } else {
                        HeroNumber(value: "—", unit: unit.label,
                                   caption: k.isOpen ? "Beyond the maximum angle" : "Channel closed")
                    }
                }
                .padding(.vertical, 6)
            }

            if k.isOpen {
                Section {
                    Picker("Quantity", selection: $quantity) {
                        ForEach(PlotQuantity.allCases) { q in Text(q.title).tag(q) }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)

                    Toggle("Focus around selected angle", isOn: $focusedPlot)
                    ExpandablePlot(title: "Kinematics") {
                        KinematicsChart(kin: k, quantity: quantity, unit: unit, angle: angle,
                                        solutions: solutions, selection: $chartSelection, focused: focusedPlot)
                    }.padding(.vertical, 6)
                } header: {
                    Text("vs \(ejectileName) lab angle")
                } footer: {
                    Text("Drag across the chart or use the angle control to move the cursor.")
                }

                ForEach(Array(solutions.enumerated()), id: \.offset) { index, s in
                    Section {
                        ValueRow(label: "\(ejectileName) energy", value: Fmt.energy(s.ejectileEnergy, unit: unit, decimals: unit == .keV ? 2 : 5), unit: unit.label)
                        ValueRow(label: "CM angle θ*", value: Fmt.angle(s.thetaCM))
                        ValueRow(label: "\(r.residual.label) energy", value: Fmt.energy(s.residualEnergy, unit: unit, decimals: unit == .keV ? 2 : 5), unit: unit.label)
                        ValueRow(label: "\(r.residual.label) angle", value: Fmt.angle(s.residualAngle))
                        ValueRow(label: "dΩ*/dΩ", value: Fmt.number(s.jacobian, decimals: 4), note: "σ(lab) = (dΩ*/dΩ) · σ(c.m.)")
                        ValueRow(label: "dE/dθ", value: Fmt.number(s.energySlope * .pi / 180 / unit.scale, decimals: unit == .keV ? 3 : 6),
                                 unit: "\(unit.label)/°", note: "Kinematic broadening")
                    } header: {
                        Text(solutions.count > 1 ? (index == 0 ? "High-energy branch" : "Low-energy branch") : "At \(Fmt.number(angle, decimals: AngleControl.decimals(limit: k.maxEjectileAngle?.degrees)))°")
                    }
                }
            }

            Section {
                EnergyField(title: "Beam energy", keV: $workbench.beamEnergy, unit: unit)
                TargetEnergyToggle()
                EnergyField(title: "Residual Eₓ", keV: $workbench.residualExcitation, unit: unit)
                ValueRow(label: "E (c.m.)", value: Fmt.energy(k.centerOfMassEnergy, unit: unit), unit: unit.label)
                ValueRow(label: "β of CM", value: Fmt.number(k.beta, decimals: 5))
                if let max = k.maxEjectileAngle {
                    ValueRow(label: "Max \(ejectileName) angle", value: Fmt.angle(max))
                }
                if let max = k.maxResidualAngle {
                    ValueRow(label: "Max \(r.residual.label) angle", value: Fmt.angle(max))
                }
            } header: {
                Text("Setup")
            }
        }
        .groupedList()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .toolbar {
            if k.isOpen {
                ToolbarItem(placement: .trailingBar) {
                    ShareLink(item: CSVFile(name: "kinematics_\(r.plainLabelForFile)_\(Int(workbench.reactionEnergy))keV", text: Self.csv(r, k, excitation: workbench.residualExcitation)),
                              preview: SharePreview("Kinematics table, \(r.label)", image: Image(systemName: "tablecells"))) {
                        Label("Export Table", systemImage: "tablecells")
                    }
                }
            }
        }
        .notebookSnapshot {
            var s = NotebookSnapshot(tool: .kinematics, title: "\(r.label) at \(Fmt.number(angle, decimals: 1))°",
                                     subtitle: "\(Fmt.energy(workbench.reactionEnergy, unit: unit)) \(unit.label)")
            s.add("Setup", "Beam energy", Fmt.energy(workbench.reactionEnergy, unit: unit), unit.label)
            s.add("Setup", "Residual Eₓ", Fmt.energy(workbench.residualExcitation, unit: unit), unit.label)
            s.add("Setup", "E (c.m.)", Fmt.energy(k.centerOfMassEnergy, unit: unit), unit.label)
            s.add("Setup", "\(ejectileName) lab angle", Fmt.number(angle, decimals: 2), "°")
            for (i, sol) in solutions.enumerated() {
                let sec = solutions.count > 1 ? (i == 0 ? "High-energy branch" : "Low-energy branch") : "Result"
                s.add(sec, "\(ejectileName) energy", Fmt.energy(sol.ejectileEnergy, unit: unit, decimals: unit == .keV ? 2 : 5), unit.label)
                s.add(sec, "θ*", Fmt.angle(sol.thetaCM))
                s.add(sec, "\(r.residual.label) energy", Fmt.energy(sol.residualEnergy, unit: unit, decimals: unit == .keV ? 2 : 5), unit.label)
                s.add(sec, "\(r.residual.label) angle", Fmt.angle(sol.residualAngle))
                s.add(sec, "dΩ*/dΩ", Fmt.number(sol.jacobian, decimals: 4))
            }
            return s
        }
        .safeAreaInset(edge: .bottom) {
            if k.isOpen {
                AngleControl(angle: $angle, limit: k.maxEjectileAngle.map { $0.degrees })
                    .onAppear { angle = AngleControl.clamp(angle, limit: k.maxEjectileAngle?.degrees) }
                    .onChange(of: k.maxEjectileAngle) { _, new in
                        angle = AngleControl.clamp(angle, limit: new?.degrees)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .onChange(of: chartSelection) { _, new in
            if let new {
                let limit = k.maxEjectileAngle?.degrees
                let step = AngleControl.step(limit: limit)
                angle = AngleControl.clamp((new / step).rounded() * step, limit: limit)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: solutions.count)
    }
}

enum PlotQuantity: String, CaseIterable, Identifiable {
    case ejectileEnergy, residualEnergy, cmAngle
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ejectileEnergy: "Ejectile E"
        case .residualEnergy: "Recoil E"
        case .cmAngle: "θ CM"
        }
    }
}

private struct KinematicsChart: View {
    let kin: TwoBodyKinematics
    let quantity: PlotQuantity
    let unit: EnergyUnit
    let angle: Double
    let solutions: [KinematicSolution]
    @Binding var selection: Double?
    var focused = false

    private struct Point: Identifiable { let id: Int; let x: Double; let y: Double }

    private func y(_ s: KinematicSolution) -> Double {
        switch quantity {
        case .ejectileEnergy: s.ejectileEnergy / unit.scale
        case .residualEnergy: s.residualEnergy / unit.scale
        case .cmAngle: s.thetaCM.degrees
        }
    }

    var body: some View {
        // Sampled uniformly in θ*, so inverse-kinematics curves fold back in order.
        let points = kin.curve(samples: 361).enumerated().map { Point(id: $0.offset, x: $0.element.ejectileAngle.degrees, y: y($0.element)) }
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("θ lab", p.x), y: .value(quantity.title, p.y), series: .value("curve", "c"))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.accent.gradient)
            }
            RuleMark(x: .value("θ", angle))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
            ForEach(Array(solutions.enumerated()), id: \.offset) { _, s in
                // Two branches at one angle: label the upper point above, the lower one below.
                let isLower = solutions.count > 1 && y(s) < (solutions.map(y).max() ?? 0)
                PointMark(x: .value("θ lab", angle), y: .value(quantity.title, y(s)))
                    .symbolSize(90)
                    .foregroundStyle(Color.accent)
                    .annotation(position: isLower ? .bottomTrailing : .topTrailing, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        Text(Fmt.number(y(s), decimals: quantity == .cmAngle ? 1 : (unit == .keV ? 1 : 4)))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.background, in: Capsule())
                    }
            }
        }
        .chartXScale(domain: focused ? max(0, min(angle - 10, max(0, xMax(points) - 20)))...min(xMax(points), max(20, angle + 10)) : 0...xMax(points))
        .chartPlotStyle { $0.clipped() }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.grouping(.never))
            }
        }
        .chartXAxisLabel("θ lab (°)")
        .chartYAxisLabel(quantity == .cmAngle ? "θ* (°)" : "E (\(unit.label))")
        .chartXSelection(value: $selection)
        .accessibilityLabel("\(quantity.title) versus laboratory angle")
    }

    private func xMax(_ points: [Point]) -> Double {
        let m = points.map(\.x).max() ?? 180
        return m > 150 ? 180 : max(1, (m * 1.1).rounded(.up))
    }
}

/// Floating angle control in the functional layer: Liquid Glass, interactive.
private struct AngleControl: View {
    @Binding var angle: Double
    let limit: Double?

    var body: some View {
        HStack(spacing: 4) {
            stepButton("minus", delta: -0.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("θ \(Fmt.number(angle, decimals: decimals))°")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: angle))
                    if let limit {
                        Text("max \(Fmt.number(limit, decimals: 2))°")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Slider(value: $angle, in: 0...Self.upper(limit: limit), step: step)
                    .controlSize(.small)
                    .accessibilityLabel("Laboratory angle")
                    .accessibilityValue("\(Fmt.number(angle, decimals: decimals)) degrees")
            }
            stepButton("plus", delta: 0.5)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: .capsule)
        .sensoryFeedback(.selection, trigger: Int(angle / (Self.upper(limit: limit) / 12)))
    }

    private var step: Double { Self.step(limit: limit) }
    private var decimals: Int { Self.decimals(limit: limit) }
    static func decimals(limit: Double?) -> Int { step(limit: limit) < 0.1 ? 2 : 1 }

    /// Largest reachable lab angle, rounded down to the slider step.
    static func upper(limit: Double?) -> Double {
        guard let limit, limit < 180 else { return 180 }
        let s = step(limit: limit)
        return max(s, (limit / s).rounded(.down) * s)
    }

    /// Finer steps when the kinematic cone is narrow (inverse kinematics).
    static func step(limit: Double?) -> Double {
        guard let limit, limit < 180 else { return 0.5 }
        return limit < 10 ? 0.01 : (limit < 45 ? 0.1 : 0.5)
    }

    static func clamp(_ angle: Double, limit: Double?) -> Double {
        min(upper(limit: limit), max(0, angle))
    }

    private func stepButton(_ symbol: String, delta: Double) -> some View {
        Button {
            angle = Self.clamp(angle + (delta < 0 ? -step : step), limit: limit)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        // Plain buttons: they already sit on the glass surface (no glass on glass).
        .buttonStyle(.borderless)
        .contentShape(Circle())
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(delta < 0 ? "Decrease angle" : "Increase angle")
    }
}
