import Charts
import NucPhysKit
import SwiftUI

/// Energy loss of the beam through a stack: optional layers in front (window, dead layer), the
/// target layer, optional layers behind (backing). The target layer gives the effective energy.
struct EnergyLossView: View {
    @Environment(Workbench.self) private var workbench
    @State private var editingSetup = false
    @State private var editing: LayerEdit?

    enum LayerEdit: Identifiable, Hashable {
        case target
        case layer(UUID)
        case add(front: Bool)
        var id: Self { self }
    }

    var body: some View {
        Group {
            if let ion = workbench.stoppingIon, let target = workbench.stoppingTarget, let r = workbench.reaction {
                content(ion: ion, target: target, reaction: r)
            } else {
                ContentUnavailableView {
                    Label("No beam ion", systemImage: "arrow.down.right")
                } description: {
                    Text("Energy loss uses the projectile and beam energy of the current reaction (Z ≤ 92).")
                } actions: {
                    Button("Edit Setup") { editingSetup = true }.buttonStyle(.glassProminent)
                }
            }
        }
        .navigationTitle("Energy Loss")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .trailingBar) {
                Menu {
                    Button("Layer in Front of Target", systemImage: "square.stack.3d.up") { editing = .add(front: true) }
                    Button("Layer Behind Target", systemImage: "square.stack.3d.down.right") { editing = .add(front: false) }
                } label: {
                    Label("Add Layer", systemImage: "plus")
                }
                .disabled(workbench.stoppingIon == nil)
            }
        }
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
        .sheet(item: $editing) { edit in editor(edit) }
    }

    // MARK: Content

    @ViewBuilder
    private func content(ion: StoppingIon, target: StoppingTarget, reaction r: Reaction) -> some View {
        @Bindable var workbench = workbench
        let unit = workbench.energyUnit
        let tUnit = workbench.thicknessUnit
        let outcome = workbench.stackOutcome
        let result = outcome?.target
        let hasStack = !workbench.layersBefore.isEmpty || !workbench.layersAfter.isEmpty

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    StoppingHeader(ion: ion, ionLabel: r.projectile.label, target: target,
                                   isReactionTarget: workbench.customTarget == nil) { editing = .target }
                    if let result, !result.stopped {
                        HeroNumber(value: energy(result.energyOut, unit),
                                   unit: unit.label, caption: hasStack ? "Exit energy from the target layer" : "Exit energy")
                        VStack(alignment: .leading, spacing: 8) {
                            if !workbench.layersBefore.isEmpty {
                                StatusBadge(text: "Enters the target at \(energy(result.energyIn, unit)) \(unit.label)",
                                            symbol: "arrow.right.to.line", tint: .indigo)
                            }
                            HStack(spacing: 8) {
                                StatusBadge(text: "ΔE \(energy(result.energyLoss, unit)) \(unit.label)",
                                            symbol: "arrow.down.right", tint: .orange)
                                StatusBadge(text: "FWHM \(energy(result.fwhm, unit)) \(unit.label)",
                                            symbol: "waveform.path", tint: .teal)
                            }
                        }
                    } else {
                        HeroNumber(value: "Stopped", unit: "",
                                   caption: result == nil ? "The beam stops before the target layer" : "The beam stops in the target layer")
                        StatusBadge(text: "Mean energy below 1 % of the entrance energy", symbol: "exclamationmark.triangle.fill", tint: .orange)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                EnergyField(title: "Beam energy", keV: $workbench.beamEnergy, unit: unit)
                NumberField(title: "Tilt", value: $workbench.layerAngle, unit: "°", range: 0...89)
            } header: {
                Text("Beam")
            } footer: {
                Text("Tilt: angle between the beam and the layer normal, for every layer.")
            }

            Section {
                ForEach(workbench.layersBefore) { layer in
                    layerRow(layer, result: outcome.flatMap { o in
                        workbench.layersBefore.firstIndex(of: layer).flatMap { o.before.indices.contains($0) ? o.before[$0] : nil }
                    }, unit: unit, tUnit: tUnit)
                }
                .onDelete { workbench.layersBefore.remove(atOffsets: $0) }
                .onMove { workbench.layersBefore.move(fromOffsets: $0, toOffset: $1) }

                if let t = workbench.targetLayer {
                    layerRow(t, result: result, unit: unit, tUnit: tUnit, isTarget: true)
                }

                ForEach(workbench.layersAfter) { layer in
                    layerRow(layer, result: outcome.flatMap { o in
                        workbench.layersAfter.firstIndex(of: layer).flatMap { o.after.indices.contains($0) ? o.after[$0] : nil }
                    }, unit: unit, tUnit: tUnit)
                }
                .onDelete { workbench.layersAfter.remove(atOffsets: $0) }
                .onMove { workbench.layersAfter.move(fromOffsets: $0, toOffset: $1) }

                if !hasStack {
                    Button("Add Layer in Front (Window, Dead Layer)", systemImage: "plus") { editing = .add(front: true) }
                    Button("Add Layer Behind (Backing)", systemImage: "plus") { editing = .add(front: false) }
                }
            } header: {
                Text("Layers · beam direction ↓")
            } footer: {
                Text("Tap a layer to edit its material and thickness. Mean energy and energy spread leaving one layer enter the next.")
            }

            if let outcome, outcome.all.contains(where: { $0.profile.count > 2 }) {
                Section {
                    StackDepthChart(outcome: outcome, layers: workbench.allLayers, unit: unit, thicknessUnit: tUnit)
                        .frame(height: 230)
                        .padding(.vertical, 8)
                } header: {
                    Text("Energy along the path")
                } footer: {
                    Text("Band: ±1σ energy straggling. Shaded: the target layer.")
                }
            }

            if let result {
                Section {
                    ValueRow(label: "Energy loss", value: Fmt.energy(result.energyLoss, unit: unit), unit: unit.label)
                    ValueRow(label: "Electronic", value: small(result.electronicLoss, unit), unit: unit.label)
                    ValueRow(label: "Nuclear", value: small(result.nuclearLoss, unit), unit: unit.label)
                    if !workbench.layersBefore.isEmpty {
                        ValueRow(label: "Straggling σ, entering", value: small(result.profile.first?.sigma ?? 0, unit), unit: unit.label)
                    }
                    ValueRow(label: "Straggling σ\(workbench.layersBefore.isEmpty ? "" : ", leaving")", value: small(result.sigma, unit),
                             unit: unit.label, note: "TRIM model (Bohr, integer mean Z₂)")
                    ValueRow(label: "Straggling σ, Bohr", value: small(result.sigmaBohr, unit), unit: unit.label)
                    if workbench.layerAngle > 0 {
                        let l = Fmt.length(result.pathLength)
                        ValueRow(label: "Path length", value: l.value, unit: l.unit)
                    }
                } header: {
                    Text("Through the target layer")
                } footer: {
                    Text("Mean energy from dE/dx = −S(E); variance from Bohr straggling stretched by the slope of S (LunaSRIM). Path-length and nuclear straggling are neglected.")
                }

                if !result.stopped {
                    Section {
                        ValueRow(label: "Mean energy in target", value: Fmt.energy(result.meanEnergy, unit: unit), unit: unit.label,
                                 note: "Path-averaged, lab")
                        let k = TwoBodyKinematics(reaction: r, beamEnergy: result.meanEnergy)
                        ValueRow(label: "Centre-of-mass energy", value: Fmt.energy(k.centerOfMassEnergy, unit: unit), unit: unit.label)
                        if let cn = r.compoundNucleus(), let ex = r.compoundExcitation(beamEnergy: result.meanEnergy) {
                            ValueRow(label: "Compound \(cn.label) Eₓ", value: Fmt.energy(ex, unit: unit), unit: unit.label)
                        }
                        Toggle(isOn: $workbench.useTargetMeanEnergy.animation(.smooth)) {
                            Label("Use in Kinematics and Q-Value", systemImage: "arrow.triangle.branch")
                        }
                    } header: {
                        Text("Effective energy · \(r.label)")
                    } footer: {
                        Text("For a thin target with a slowly varying cross section, the reaction effectively happens at the mean energy. With the switch on, the other tools use it in place of the beam energy.")
                    }
                }
            }
        }
        .groupedList()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .notebookSnapshot {
            guard let result else { return nil }
            var s = NotebookSnapshot(tool: .energyLoss, title: "\(r.projectile.label) through \(target.name)",
                                     subtitle: "\(Fmt.energy(workbench.beamEnergy, unit: unit)) \(unit.label)")
            s.add("Input", "Beam energy", Fmt.energy(workbench.beamEnergy, unit: unit), unit.label)
            for (i, l) in workbench.allLayers.enumerated() {
                s.add("Layers", "\(i + 1). \(l.target.name)", Fmt.significant(tUnit.fromAngstrom(l.thickness, target: l.target)), tUnit.rawValue)
            }
            s.add("Target layer", "Energy in", energy(result.energyIn, unit), unit.label)
            s.add("Target layer", "Energy out", result.stopped ? "stopped" : energy(result.energyOut, unit), unit.label)
            s.add("Target layer", "Energy loss", Fmt.energy(result.energyLoss, unit: unit), unit.label)
            s.add("Target layer", "Straggling σ", small(result.sigma, unit), unit.label)
            if !result.stopped {
                s.add("Target layer", "Mean energy", Fmt.energy(result.meanEnergy, unit: unit), unit.label)
            }
            return s
        }
        .animation(.smooth, value: workbench.allLayers)
        .animation(.smooth, value: workbench.thicknessUnit)
    }

    private func layerRow(_ layer: StackLayer, result: StoppingCalculator.EnergyLoss?, unit: EnergyUnit,
                          tUnit: ThicknessUnit, isTarget: Bool = false) -> some View {
        Button {
            editing = isTarget ? .target : .layer(layer.id)
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isTarget ? Color.accent : Color.secondary.opacity(0.45))
                    .frame(width: 6)
                    .padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(layer.target.name).font(.body.weight(isTarget ? .semibold : .regular)).lineLimit(1)
                        if isTarget {
                            Text("TARGET")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .foregroundStyle(Color.accent)
                                .background(Color.accent.opacity(0.14), in: Capsule())
                        }
                    }
                    Text("\(Fmt.significant(tUnit.fromAngstrom(layer.thickness, target: layer.target))) \(tUnit.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    if let result {
                        if result.stopped {
                            Text("Stops here").font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                        } else {
                            Text("\(energy(result.energyOut, unit)) \(unit.label)").font(.subheadline.weight(.semibold))
                            Text("−\(energy(result.energyLoss, unit))").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Not reached").font(.subheadline).foregroundStyle(.tertiary)
                    }
                }
                .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .accessibilityHint("Edit layer")
    }

    // MARK: Editor

    @ViewBuilder
    private func editor(_ edit: LayerEdit) -> some View {
        switch edit {
        case .target:
            if let t = workbench.stoppingTarget {
                TargetEditor(title: "Target Layer", initial: t, thickness: workbench.layerThickness,
                             reactionTarget: workbench.reactionTargetMaterial) { target, thickness in
                    workbench.customTarget = target == workbench.reactionTargetMaterial ? nil : target
                    workbench.layerThickness = thickness
                }
            }
        case .layer(let id):
            if let layer = (workbench.layersBefore + workbench.layersAfter).first(where: { $0.id == id }) {
                TargetEditor(title: "Layer", initial: layer.target, thickness: layer.thickness,
                             onDelete: { remove(id) }) { target, thickness in
                    update(id) { $0.target = target; $0.thickness = thickness }
                }
            }
        case .add(let front):
            // Front: a thin carbon dead layer; behind: a tantalum backing, as in many (p,γ) targets.
            let t: StoppingTarget = front ? .element(6) : .element(73)
            TargetEditor(title: front ? "Layer in Front" : "Layer Behind", initial: t,
                         thickness: front ? ThicknessUnit.microgramCm2.toAngstrom(2, target: t) : 2.5e6) { target, thickness in
                let layer = StackLayer(target: target, thickness: thickness)
                if front { workbench.layersBefore.append(layer) } else { workbench.layersAfter.append(layer) }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout StackLayer) -> Void) {
        if let i = workbench.layersBefore.firstIndex(where: { $0.id == id }) { change(&workbench.layersBefore[i]) }
        if let i = workbench.layersAfter.firstIndex(where: { $0.id == id }) { change(&workbench.layersAfter[i]) }
    }

    private func remove(_ id: UUID) {
        workbench.layersBefore.removeAll { $0.id == id }
        workbench.layersAfter.removeAll { $0.id == id }
    }

    // MARK: Formatting

    private func energy(_ keV: Double, _ unit: EnergyUnit) -> String {
        Fmt.energy(keV, unit: unit, decimals: unit == .keV ? 2 : 5)
    }

    /// Small energies with significant figures, so a 2 eV nuclear loss does not read "0.00".
    private func small(_ keV: Double, _ unit: EnergyUnit) -> String {
        Fmt.significant(keV / unit.scale, digits: 3)
    }
}

/// Mean energy (±σ band) against depth along the path through the whole stack; layer boundaries
/// as rules, the target layer shaded. Depth in the display unit, each layer converted with its own material.
private struct StackDepthChart: View {
    let outcome: Workbench.StackOutcome
    let layers: [StackLayer]
    let unit: EnergyUnit
    let thicknessUnit: ThicknessUnit

    private struct Point: Identifiable {
        let id: Int
        let x: Double, e: Double, lo: Double, hi: Double
    }

    private struct Span: Identifiable {
        let id: Int
        let start: Double, end: Double
        let isTarget: Bool
    }

    var body: some View {
        let (pts, spans) = series()
        let target = spans.first(where: \.isTarget)
        Chart {
            if let target {
                RectangleMark(xStart: .value("Start", target.start), xEnd: .value("End", target.end))
                    .foregroundStyle(Color.accent.opacity(0.09))
            }
            ForEach(spans.dropLast()) { s in
                RuleMark(x: .value("Boundary", s.end))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            ForEach(pts) { p in
                AreaMark(x: .value("Depth", p.x), yStart: .value("E − σ", p.lo), yEnd: .value("E + σ", p.hi), series: .value("s", "band"))
                    .foregroundStyle(Color.accent.opacity(0.2))
            }
            ForEach(pts) { p in
                LineMark(x: .value("Depth", p.x), y: .value("Energy", p.e), series: .value("s", "mean"))
                    .foregroundStyle(Color.accent.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .chartXScale(domain: 0...max(pts.last?.x ?? 1, 1e-12))
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.grouping(.never))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.grouping(.never))
            }
        }
        .chartXAxisLabel("Path depth (\(thicknessUnit.rawValue))", alignment: .leading)
        .chartYAxisLabel("E (\(unit.label))")
        .accessibilityLabel("Beam energy versus depth through the layers")
    }

    private func series() -> ([Point], [Span]) {
        let results = outcome.all
        let reached = layers.filter { $0.thickness > 0 }
        let targetIndex = outcome.before.count
        var pts: [Point] = [], spans: [Span] = []
        var offset = 0.0
        var id = 0
        for (k, r) in results.enumerated() where k < reached.count {
            let t = reached[k].target
            let stride = max(1, r.profile.count / 80)
            for (i, p) in r.profile.enumerated() where i % stride == 0 || i == r.profile.count - 1 {
                let x = offset + thicknessUnit.fromAngstrom(p.depth, target: t)
                pts.append(Point(id: id, x: x, e: p.energy / unit.scale,
                                 lo: (p.energy - p.sigma) / unit.scale, hi: (p.energy + p.sigma) / unit.scale))
                id += 1
            }
            let end = offset + thicknessUnit.fromAngstrom(r.stopped ? (r.profile.last?.depth ?? 0) : r.pathLength, target: t)
            spans.append(Span(id: k, start: offset, end: end, isTarget: k == targetIndex && outcome.target != nil))
            offset = end
        }
        return (pts, spans)
    }
}
