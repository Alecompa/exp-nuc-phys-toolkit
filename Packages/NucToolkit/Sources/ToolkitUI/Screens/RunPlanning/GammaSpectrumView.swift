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
                if let r = workbench.reaction {
                    ResidualLevelField(residual: r.residual, keV: Bindable(workbench).residualExcitation,
                                       unit: workbench.energyUnit, maximum: availableEnergy(r))
                }
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

    /// Energy available to excite the residual: E_cm + Q₀.
    private func availableEnergy(_ r: Reaction) -> Double {
        TwoBodyKinematics(reaction: r, beamEnergy: workbench.reactionEnergy).centerOfMassEnergy + r.qValue
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
    @AppStorage("spectrum.reactionLines") private var includeReaction = true
    @AppStorage("spectrum.reactions") private var reactions = 1e4
    @AppStorage("spectrum.applyEfficiency") private var applyEfficiency = false
    @State private var bins: [SpectrumBin] = []
    @State private var error: String?
    @State private var scheme: LevelScheme?

    private struct Input: Hashable {
        let setup: SpectrumSetup
        let resolution: ResolutionModel
    }

    var body: some View {
        @Bindable var workbench = workbench
        let fromReaction = reactionGammas
        var setup = workbench.spectrumSetup
        if includeReaction { setup.lines += fromReaction.lines.map { line(for: $0) } }
        let input = Input(setup: setup, resolution: workbench.resolutionModel)
        return Group {
            Section {
                if setup.lines.contains(where: \.enabled) {
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
                    ContentUnavailableView("No γ lines", systemImage: "waveform.path", description: Text(noGammaText))
                }
            } header: { Text("Spectrum") }

            if !fromReaction.lines.isEmpty {
                Section {
                    Toggle("Include in spectrum", isOn: $includeReaction)
                    ScientificField(title: "Reactions", value: $reactions)
                    Toggle("Apply efficiency curve", isOn: $applyEfficiency)
                    ForEach(fromReaction.lines) { g in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Fmt.keV(g.energy, digits: 6)) keV").monospacedDigit()
                                Text(g.label).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(Fmt.significant(100 * g.intensity, digits: 3)) %").monospacedDigit()
                                Text("\(Fmt.significant(line(for: g).counts, digits: 3)) counts").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("From the reaction") } footer: {
                    Text(fromReaction.note)
                }
            }

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
                Menu {
                    Button("Custom line") { workbench.spectrumSetup.lines.append(.init(name: "Line", counts: 1000)) }
                    Menu("Calibration source") {
                        ForEach(CalibrationSources.all) { source in Button(source.label) { addSource(source) } }
                    }
                } label: { Label("Add line", systemImage: "plus") }
            } header: { Text("Other lines") } footer: {
                Text("Contaminants and sources. Counts are photopeak areas before the foils.")
            }

            Section("Window") {
                NumberField(title: "Maximum energy", value: $workbench.spectrumSetup.maximumEnergy, unit: "keV", range: 1...20000)
                Picker("Channels", selection: $workbench.spectrumSetup.channels) {
                    ForEach([512, 1024, 2048, 4096, 8192], id: \.self) { Text("\($0)").tag($0) }
                }
                NumberField(title: "Background", value: $workbench.spectrumSetup.background, unit: "counts/keV", range: 0...1e8)
                NumberField(title: "Compton / peak", value: $workbench.spectrumSetup.continuumRatio, range: 0...100)
            }

            EscapeSection(escape: $workbench.spectrumSetup.escape)

            Section {
                Picker("Detector", selection: $workbench.resolutionModel) {
                    if !ResolutionModel.presets.contains(where: { $0.model == workbench.resolutionModel }) {
                        Text("Custom").tag(workbench.resolutionModel)
                    }
                    ForEach(ResolutionModel.presets) { Text($0.name).tag($0.model) }
                }
                .onChange(of: workbench.resolutionModel) { _, model in
                    // Follow the crystal of a chosen preset with typical escape ratios.
                    if let name = ResolutionModel.presets.first(where: { $0.model == model })?.name,
                       let crystal = DetectorCrystal.matching(name), crystal != workbench.spectrumSetup.escape.crystal {
                        workbench.spectrumSetup.escape.useTypical(for: crystal)
                    }
                }
                ValueRow(label: "FWHM at 1332 keV", value: Fmt.significant(workbench.resolutionModel.fwhm(at: 1332.5), digits: 3), unit: "keV")
                NavigationLink("Resolution & efficiency") { DetectorView() }
            } header: { Text("Detector") }

            FoilsSection(foils: $workbench.spectrumSetup.foils)

            Section {
                Link("NIST attenuation tables", destination: URL(string: "https://physics.nist.gov/PhysRefData/XrayMassCoef/chap2.html")!)
            } footer: {
                Text("No summing, pile-up or multiple scattering.")
            }
        }
        .task(id: workbench.reaction?.residual) {
            scheme = nil
            if let residual = workbench.reaction?.residual { scheme = await LevelSchemeLoader.load(residual) }
        }
        .onChange(of: fromReaction.lines.map(\.energy).max() ?? 0, initial: true) { _, top in
            // Keep the reaction's highest γ ray inside the window.
            if includeReaction, top > workbench.spectrumSetup.maximumEnergy * 0.95 {
                workbench.spectrumSetup.maximumEnergy = min(20000, (top * 1.1 / 500).rounded(.up) * 500)
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

    private struct ReactionGamma: Identifiable {
        let energy: Double
        /// γ rays per reaction.
        let intensity: Double
        let label: String
        var id: String { "\(label)-\(energy)" }
    }

    /// Primary capture γ (capture reactions) and the de-excitation cascade of the residual level, from ENSDF.
    private var reactionGammas: (lines: [ReactionGamma], note: String) {
        guard let r = workbench.reaction else { return ([], "") }
        let ex = workbench.residualExcitation
        var out: [ReactionGamma] = []
        var notes: [String] = []
        if r.ejectile.isPhoton, let ecm = workbench.reactionEnergyCM {
            let e = ecm + r.qValue(residualExcitation: ex)
            if e > 1 { out.append(ReactionGamma(energy: e, intensity: 1, label: ex > 0 ? "primary → \(Fmt.keV(ex, digits: 5))" : "primary → g.s.")) }
        }
        if ex > 1 {
            let cascade = scheme.map { GammaCascade.from(excitation: ex, scheme: $0) }
            if let c = cascade, !c.lines.isEmpty {
                out += c.lines.map {
                    ReactionGamma(energy: $0.energy, intensity: $0.intensity,
                                  label: "\(r.residual.label) \(Fmt.keV($0.initialLevel, digits: 5)) → \(Fmt.keV($0.finalLevel, digits: 5))")
                }
                notes.append("Cascade from ENSDF branching ratios")
                if c.unresolved > 0.01 { notes.append("\(Fmt.significant(100 * c.unresolved, digits: 2)) % reaches levels without γ data") }
            } else {
                let e = GammaDoppler.recoilCorrected(transition: ex, mass: r.residual.kinematicMass)
                out.append(ReactionGamma(energy: e, intensity: 1, label: "\(r.residual.label) \(Fmt.keV(ex, digits: 5)) → 0"))
                notes.append(scheme == nil ? "No level scheme loaded: direct decay to the ground state assumed"
                                           : "Eₓ is not an ENSDF level: direct decay to the ground state assumed")
            }
        }
        notes.append(applyEfficiency ? "Counts = reactions × γ per reaction × efficiency" : "Counts = reactions × γ per reaction")
        return (out, notes.joined(separator: ". ") + ".")
    }

    private func line(for g: ReactionGamma) -> SpectrumLine {
        let eff = applyEfficiency ? (workbench.efficiencyCurve.fit()?.efficiency(at: g.energy) ?? 0) : 1
        return SpectrumLine(name: g.label, energy: min(20000, max(1, g.energy)), counts: max(0, reactions * g.intensity * eff))
    }

    private var noGammaText: String {
        guard let r = workbench.reaction else { return "Set a reaction first." }
        return "\(r.label) to the ground state emits no γ ray. Choose a residual level above, or switch to Particles."
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

/// Single/double escape peaks: ratios at 6 MeV, scaled with the crystal's pair-production share.
private struct EscapeSection: View {
    @Binding var escape: EscapeModel

    var body: some View {
        Section {
            Toggle("Escape peaks", isOn: $escape.enabled)
            if escape.enabled {
                Picker("Crystal", selection: Binding(get: { escape.crystal }, set: { escape.useTypical(for: $0) })) {
                    ForEach(DetectorCrystal.allCases) { Text($0.name).tag($0) }
                }
                NumberField(title: "SE / peak at 6 MeV", value: $escape.singleAtReference, range: 0...20)
                NumberField(title: "DE / peak at 6 MeV", value: $escape.doubleAtReference, range: 0...20)
                NumberField(title: "511 keV / SE", value: $escape.annihilation, range: 0...20)
                let r3 = escape.ratios(at: 3000), r10 = escape.ratios(at: 10000)
                ValueRow(label: "SE · DE / peak at 3 MeV", value: "\(Fmt.significant(r3.single, digits: 2)) · \(Fmt.significant(r3.double, digits: 2))")
                ValueRow(label: "SE · DE / peak at 10 MeV", value: "\(Fmt.significant(r10.single, digits: 2)) · \(Fmt.significant(r10.double, digits: 2))")
            }
        } footer: {
            if escape.enabled {
                Text("Single (SE) and double (DE) escape at E − 511 and E − 1022 keV, scaled by pair production (NIST XCOM). Ratios depend on crystal size: prefer measured ones.")
            }
        }
    }
}
