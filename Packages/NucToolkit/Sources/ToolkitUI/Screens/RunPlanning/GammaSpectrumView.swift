import Charts
import NucPhysKit
import SwiftUI

/// Expected detector spectrum for the current setup: γ rays in a γ detector, or the charged particles
/// (reaction ejectile and elastically scattered beam) reaching a particle detector behind absorber foils.
struct DetectorSpectrumView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case gamma = "γ rays", particles = "Particles"
        var id: String { rawValue }
    }

    @Environment(Workbench.self) private var workbench
    @State private var mode: Mode?
    @State private var editingSetup = false

    var body: some View {
        let mode = mode ?? defaultMode
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if let r = workbench.reaction { ReactionHeader(reaction: r) { editingSetup = true } }
                    Picker("Detector", selection: Binding(get: { mode }, set: { self.mode = $0 })) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }
            switch mode {
            case .gamma: GammaSpectrumSections()
            case .particles: ParticleSpectrumSections()
            }
        }
        .groupedList()
        .navigationTitle("Detector Spectrum")
        .inlineTitle()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
    }

    /// Particles for a charged ejectile, γ rays for capture and neutron channels.
    private var defaultMode: Mode {
        guard let r = workbench.reaction, case .nuclide(let e) = r.ejectile, e.z > 0 else { return .gamma }
        return .particles
    }
}

// MARK: - γ rays

private struct GammaSpectrumSections: View {
    @Environment(Workbench.self) private var workbench
    @State private var bins: [SpectrumBin] = []
    @State private var error: String?
    @State private var calculating = false

    private struct Input: Hashable {
        let setup: SpectrumSetup
        let resolution: ResolutionModel
    }

    var body: some View {
        @Bindable var workbench = workbench
        let input = Input(setup: workbench.spectrumSetup, resolution: workbench.resolutionModel)
        let suggestions = reactionLines
        Group {
            Section {
                if workbench.spectrumSetup.lines.contains(where: \.enabled) {
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    } else if bins.isEmpty {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        SpectrumExplorer(bins: bins, maximumEnergy: input.setup.maximumEnergy)
                        ShareLink(item: CSVFile(name: "gamma_spectrum", text: GammaSpectrum.csv(bins)),
                                  preview: SharePreview("Gamma spectrum")) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                } else {
                    ContentUnavailableView("No γ lines", systemImage: "waveform.path",
                                           description: Text(suggestions.isEmpty ? noGammaText : "Add the reaction lines below."))
                }
            } header: { Text("Spectrum") }

            Section {
                ForEach($workbench.spectrumSetup.lines) { $line in
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $line.enabled) {
                            TextField("Label", text: $line.name).font(.body.weight(.medium))
                        }
                        NumberField(title: "Energy", value: $line.energy, unit: "keV", range: 1...20000)
                        NumberField(title: "Peak counts", value: $line.counts, range: 0...1e12)
                        if let t = transmission(at: line.energy) {
                            Text("Foil transmission \(Fmt.significant(t * 100, digits: 3)) %")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { workbench.spectrumSetup.lines.remove(atOffsets: $0) }
                ForEach(suggestions.filter { s in !workbench.spectrumSetup.lines.contains { abs($0.energy - s.energy) < 0.05 } },
                        id: \.name) { s in
                    Button("Add \(s.name), \(Fmt.keV(s.energy)) keV", systemImage: "plus.circle") {
                        workbench.spectrumSetup.lines.append(SpectrumLine(name: s.name, energy: s.energy, counts: 1000))
                        if s.energy > workbench.spectrumSetup.maximumEnergy {
                            workbench.spectrumSetup.maximumEnergy = min(20000, (s.energy * 1.15 / 500).rounded(.up) * 500)
                        }
                    }
                }
                Menu {
                    Button("Custom line") { workbench.spectrumSetup.lines.append(.init(name: "Line", counts: 1000)) }
                    Menu("Calibration source") {
                        ForEach(CalibrationSources.all) { source in Button(source.label) { addSource(source) } }
                    }
                } label: { Label("Add line", systemImage: "plus") }
            } header: { Text("Lines") } footer: {
                Text("Counts are photopeak areas before the foils. Swipe to delete.")
            }

            Section("Window") {
                NumberField(title: "Maximum energy", value: $workbench.spectrumSetup.maximumEnergy, unit: "keV", range: 1...20000)
                Picker("Channels", selection: $workbench.spectrumSetup.channels) {
                    ForEach([512, 1024, 2048, 4096, 8192], id: \.self) { Text("\($0)").tag($0) }
                }
                NumberField(title: "Background", value: $workbench.spectrumSetup.background, unit: "counts/keV", range: 0...1e8)
                NumberField(title: "Compton / peak", value: $workbench.spectrumSetup.continuumRatio, range: 0...100)
            }

            Section {
                Picker("Detector", selection: $workbench.resolutionModel) {
                    if !ResolutionModel.presets.contains(where: { $0.model == workbench.resolutionModel }) {
                        Text("Custom").tag(workbench.resolutionModel)
                    }
                    ForEach(ResolutionModel.presets) { Text($0.name).tag($0.model) }
                }
                ValueRow(label: "FWHM at 1332 keV", value: Fmt.significant(workbench.resolutionModel.fwhm(at: 1332.5), digits: 3), unit: "keV")
                NavigationLink("Resolution & efficiency") { DetectorView() }
            } header: { Text("Detector") }

            FoilsSection(foils: $workbench.spectrumSetup.foils)

            Section {
                Link("NIST attenuation tables", destination: URL(string: "https://physics.nist.gov/PhysRefData/XrayMassCoef/chap2.html")!)
            } footer: {
                Text("Gaussian peaks and a single-scatter Compton continuum; no escape peaks, summing or pile-up.")
            }
        }
        .task(id: input) {
            error = nil
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            let calculation = Task.detached(priority: .userInitiated) {
                Result { try GammaSpectrum.simulate(input.setup, resolution: input.resolution) }
            }
            let result = await withTaskCancellationHandler { await calculation.value } onCancel: { calculation.cancel() }
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let output): bins = output
            case .failure(let failure): bins = []; error = failure.localizedDescription
            }
        }
    }

    /// γ rays the current reaction produces: the primary capture γ and the residual's level → ground state.
    private var reactionLines: [(name: String, energy: Double)] {
        guard let r = workbench.reaction else { return [] }
        var out: [(String, Double)] = []
        let ex = workbench.residualExcitation
        if r.ejectile.isPhoton, let ecm = workbench.reactionEnergyCM {
            let e = ecm + r.qValue(residualExcitation: ex)
            if e > 1 { out.append(("primary γ", e.rounded(toPlaces: 1))) }
        }
        if ex > 1 {
            let e = GammaDoppler.recoilCorrected(transition: ex, mass: r.residual.kinematicMass)
            out.append(("\(r.residual.label) \(Fmt.keV(ex, digits: 5)) → 0", e.rounded(toPlaces: 1)))
        }
        return out
    }

    private var noGammaText: String {
        guard let r = workbench.reaction else { return "Set a reaction first." }
        return "\(r.label) to the ground state emits no γ ray. Set a residual Eₓ in the setup, or switch to Particles."
    }

    private func transmission(at energy: Double) -> Double? {
        guard !workbench.spectrumSetup.foils.isEmpty else { return nil }
        return try? workbench.spectrumSetup.foils.reduce(1.0) { $0 * (try $1.transmission(at: energy)) }
    }

    private func addSource(_ source: CalibrationSource) {
        let lines = source.prominentLines().filter { (1...20000).contains($0.energy) }
        let strongest = lines.map(\.intensity).max() ?? 1
        guard strongest > 0 else { return }
        workbench.spectrumSetup.lines += lines.map {
            SpectrumLine(name: source.label, energy: $0.energy, counts: 1000 * $0.intensity / strongest)
        }
    }
}

// MARK: - Charged particles

private struct ParticleSpectrumSections: View {
    @Environment(Workbench.self) private var workbench

    var body: some View {
        @Bindable var workbench = workbench
        let groups = workbench.reaction.map {
            ParticleSpectrum.groups(reaction: $0, beamEnergy: workbench.reactionEnergy,
                                    residualExcitation: workbench.residualExcitation,
                                    material: workbench.stoppingTarget, setup: workbench.particleDetector)
        } ?? []
        Group {
            Section {
                if groups.contains(where: { $0.detected != nil && !$0.neutral }) {
                    ParticleChart(groups: groups.filter { !$0.neutral })
                        .frame(height: 220)
                        .padding(.vertical, 6)
                } else if groups.isEmpty {
                    ContentUnavailableView("No particles at this angle", systemImage: "scope")
                }
                ForEach(groups) { g in ParticleGroupRow(group: g) }
            } header: { Text("At the detector") } footer: {
                if !groups.isEmpty { Text("Equal-area peaks: heights are not yields. Energy loss in the target is not included.") }
            }

            Section {
                LabeledContent("Angle") { Text("\(Fmt.number(workbench.particleDetector.angle, decimals: 1))°").monospacedDigit() }
                Slider(value: Binding(get: { workbench.particleDetector.angle },
                                      set: { workbench.particleDetector.angle = ($0 * 2).rounded() / 2 }), in: 1...179)
                NumberField(title: "Resolution", value: $workbench.particleDetector.resolution, unit: "keV FWHM", range: 0.1...1000)
                NumberField(title: "Half-opening", value: $workbench.particleDetector.halfOpening, unit: "°", range: 0...45)
                Toggle("Elastic scattering", isOn: $workbench.particleDetector.showElastic)
            } header: { Text("Detector") } footer: {
                Text("Elastic peaks are the beam scattered by each element of the target material.")
            }

            FoilsSection(foils: $workbench.particleDetector.foils,
                         footer: "Energy loss and straggling from SRIM. Add foils to stop elastic scattering before the detector.")
        }
    }
}

private struct ParticleGroupRow: View {
    let group: ParticleGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text(group.particle).font(.body.weight(.semibold)))  \(Text(group.origin).font(.subheadline).foregroundStyle(.secondary))")
                if group.detected.map({ abs($0 - group.emitted) > 0.05 }) ?? true {
                    Text("\(Fmt.keV(group.emitted)) keV before foils").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if group.neutral {
                    Text("neutral").foregroundStyle(.secondary)
                } else if let e = group.detected {
                    Text("\(Fmt.keV(e)) keV").monospacedDigit()
                    Text("FWHM \(Fmt.significant(group.fwhm, digits: 3)) keV").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("stopped in foil \((group.stoppedIn ?? 0) + 1)").foregroundStyle(.orange)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ParticleChart: View {
    let groups: [ParticleGroup]

    var body: some View {
        let seen = groups.filter { $0.detected != nil }
        let top = (seen.map { $0.detected! + 2 * $0.fwhm }.max() ?? 1000) * 1.05
        Chart {
            ForEach(seen) { g in
                let e = g.detected!, s = max(g.fwhm, 0.5) / 2.3548
                ForEach(Array(stride(from: max(0, e - 4 * s), through: e + 4 * s, by: s / 6).enumerated()), id: \.offset) { _, x in
                    AreaMark(x: .value("Energy", x), y: .value("Counts", exp(-0.5 * pow((x - e) / s, 2)) / s),
                             series: .value("Group", g.id))
                        .foregroundStyle(by: .value("Kind", g.kind == .reaction ? "Reaction" : "Elastic"))
                        .opacity(0.75)
                }
            }
        }
        .chartForegroundStyleScale(["Reaction": Color.accent, "Elastic": Color.gray])
        .chartXScale(domain: 0...top)
        .chartYAxis(.hidden)
        .chartXAxisLabel("Energy (keV)")
        .chartLegend(position: .top, alignment: .leading)
        .accessibilityLabel("Expected particle peaks at the detector")
    }
}

// MARK: - Foils

/// Absorbers in front of a detector; each one opens the composition editor.
private struct FoilsSection: View {
    @Environment(Workbench.self) private var workbench
    @Binding var foils: [DetectorFoil]
    var footer = "Swipe to remove."
    @State private var editing: DetectorFoil?

    var body: some View {
        @Bindable var workbench = workbench
        Section {
            ForEach($foils) { $foil in
                VStack(alignment: .leading, spacing: 6) {
                    Button { editing = foil } label: {
                        LabeledContent {
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        } label: {
                            Text(foil.material.name).foregroundStyle(.primary)
                            Text(TargetSummary.composition(foil.material) + " · \(Fmt.significant(foil.material.density)) g/cm³")
                        }
                    }
                    .tint(.primary)
                    ThicknessField(angstrom: $foil.thickness, target: foil.material, unit: $workbench.thicknessUnit)
                    NumberField(title: "Tilt", value: $foil.angle, unit: "°", range: 0...89)
                }
            }
            .onDelete { foils.remove(atOffsets: $0) }
            Button("Add foil", systemImage: "plus") { editing = DetectorFoil() }
                .sheet(item: $editing) { foil in
                    TargetEditor(title: "Foil", initial: foil.material, thickness: foil.thickness) { material, thickness in
                        var updated = foil
                        updated.material = material; updated.thickness = thickness
                        if let i = foils.firstIndex(where: { $0.id == foil.id }) { foils[i] = updated } else { foils.append(updated) }
                    }
                }
        } header: { Text("Foils") } footer: { Text(footer) }
    }
}
