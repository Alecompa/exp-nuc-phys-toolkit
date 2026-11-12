import Charts
import NucPhysKit
import SwiftUI

struct GammaSpectrumView: View {
    @Environment(Workbench.self) private var workbench
    @State private var bins: [SpectrumBin] = []
    @State private var error: String?
    @State private var calculating = false
    @State private var editingFoil: DetectorFoil?

    private struct Input: Hashable {
        let setup: SpectrumSetup
        let resolution: ResolutionModel
    }

    var body: some View {
        @Bindable var workbench = workbench
        let input = Input(setup: workbench.spectrumSetup, resolution: workbench.resolutionModel)
        List {
            Section {
                if calculating { ProgressView("Calculating spectrum…") }
                if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                if !bins.isEmpty {
                    SpectrumExplorer(bins: bins, maximumEnergy: input.setup.maximumEnergy)
                    ValueRow(label: "Expected counts in window", value: Fmt.significant(bins.reduce(0) { $0 + $1.total }, digits: 6))
                    ShareLink(item: CSVFile(name: "gamma_spectrum", text: GammaSpectrum.csv(bins)),
                              preview: SharePreview("Gamma spectrum")) {
                        Label("Export spectrum CSV", systemImage: "square.and.arrow.up")
                    }
                }
            } header: { Text("Expected gamma spectrum") } footer: {
                Text("Smooth expected counts per channel, without counting noise. Peaks and the single-scatter Compton continuum are broadened using the selected resolution.")
            }

            Section("Spectrum window") {
                NumberField(title: "Maximum energy", value: $workbench.spectrumSetup.maximumEnergy, unit: "keV", range: 1...20000)
                Picker("Channels", selection: $workbench.spectrumSetup.channels) {
                    ForEach([512, 1024, 2048, 4096, 8192], id: \.self) { Text("\($0)").tag($0) }
                }
                NumberField(title: "Background", value: $workbench.spectrumSetup.background, unit: "counts/keV", range: 0...1e8)
                NumberField(title: "Compton / peak area", value: $workbench.spectrumSetup.continuumRatio, range: 0...100)
            }

            Section {
                Menu("Choose HPGe, BGO, NaI…") {
                    ForEach(ResolutionModel.presets) { preset in
                        Button(preset.name) { workbench.resolutionModel = preset.model }
                    }
                }
                Text(resolutionLabel).font(.subheadline)
                if workbench.resolutionModel.kind == .scintillator {
                    NumberField(title: "FWHM at 662 keV", value: Binding(
                        get: { workbench.resolutionModel.resolutionAt662 * 100 },
                        set: { workbench.resolutionModel.resolutionAt662 = $0 / 100 }), unit: "%", range: 0.1...100)
                } else {
                    NumberField(title: "Electronic noise FWHM", value: $workbench.resolutionModel.noise, unit: "keV", range: 0.01...100)
                }
                NavigationLink("Full resolution & efficiency settings") { DetectorView() }
            } header: { Text("Detector resolution") } footer: {
                Text("Shared with Detector Response. Selecting a detector changes resolution only. Peak counts and the Compton / peak area remain your inputs; crystal geometry and efficiency are not inferred from detector type.")
            }

            Section {
                ForEach($workbench.spectrumSetup.lines) { $line in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $line.enabled) {
                            TextField("Reaction or contaminant label", text: $line.name)
                        }
                        NumberField(title: "Gamma energy", value: $line.energy, unit: "keV", range: 1...20000)
                        NumberField(title: "Peak counts without foils", value: $line.counts, range: 0...1e12)
                        Text("Compton edge: \(Fmt.keV(GammaSpectrum.comptonEdge(energy: line.energy))) keV")
                            .font(.caption).foregroundStyle(.secondary)
                        if !workbench.spectrumSetup.foils.isEmpty,
                           let transmission = try? workbench.spectrumSetup.foils.reduce(1.0, { $0 * (try $1.transmission(at: line.energy)) }) {
                            Text("Foil transmission: \(Fmt.significant(transmission * 100, digits: 4)) %")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
                .onDelete { workbench.spectrumSetup.lines.remove(atOffsets: $0) }
                Button("Add reaction / contaminant line", systemImage: "plus.circle") {
                    workbench.spectrumSetup.lines.append(.init())
                }
                Menu("Add source-line template") {
                    ForEach(CalibrationSources.all) { source in
                        Button(source.label) { addSource(source) }
                    }
                }
            } header: { Text("Gamma lines & contaminants") } footer: {
                Text("Enter expected photopeak counts for your live time, including geometry and efficiency, before front-foil attenuation. Source templates use ENSDF energies and relative intensities normalized to 1000 counts in the strongest line, assuming equal efficiency; edit their counts for your experiment. Reaction yields and cascades are not generated automatically. Swipe a line to delete it.")
            }

            Section {
                ForEach($workbench.spectrumSetup.foils) { $foil in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { editingFoil = foil } label: {
                            Label(foil.material.name, systemImage: "square.stack.3d.up")
                        }
                        Text(TargetSummary.line(foil.material, reaction: false)).font(.caption).foregroundStyle(.secondary)
                        ThicknessField(angstrom: $foil.thickness, target: foil.material, unit: $workbench.thicknessUnit)
                        NumberField(title: "Angle to foil normal", value: $foil.angle, unit: "°", range: 0...89)
                    }
                }
                .onDelete { workbench.spectrumSetup.foils.remove(atOffsets: $0) }
                Button("Add detector foil", systemImage: "plus.circle") { editingFoil = DetectorFoil() }
            } header: { Text("Foils in front of this detector") } footer: {
                Text("Independent of the beam/target stack. Choose any element or compound and its density. Transmission uses NIST total attenuation and path thickness t/cos θ, with mass-fraction mixing. This narrow-beam model removes scattered photons; it does not add foil-scattered radiation or fluorescence. Swipe to remove a foil.")
            }

            Section("Model & references") {
                Text("Gaussian photopeaks + a free-electron Klein–Nishina single-scatter continuum. No multiple scattering, escape peaks, pair-production response, summing, pile-up, target self-absorption or Doppler effects. Foil tables cover 1 keV–20 MeV and natural elemental isotope mixtures. The continuum / peak ratio is empirical. This is a planning model, not a detector Monte Carlo.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("NIST photon attenuation tables", destination: URL(string: "https://physics.nist.gov/PhysRefData/XrayMassCoef/chap2.html")!)
                Link("Klein–Nishina reference (Geant4)", destination: URL(string: "https://geant4.web.cern.ch/documentation/pipelines/master/prm_html/PhysicsReferenceManual/electromagnetic/gamma_incident/compton/compton.html")!)
            }
        }
        .groupedList()
        .navigationTitle("Gamma Spectrum")
        .inlineTitle()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .sheet(item: $editingFoil) { foil in
            TargetEditor(title: "Detector foil", initial: foil.material, thickness: foil.thickness) { material, thickness in
                var updated = foil
                updated.material = material; updated.thickness = thickness
                if let i = workbench.spectrumSetup.foils.firstIndex(where: { $0.id == foil.id }) {
                    workbench.spectrumSetup.foils[i] = updated
                } else { workbench.spectrumSetup.foils.append(updated) }
            }
        }
        .task(id: input) {
            calculating = true; bins = []; error = nil
            // Debounce edits before launching integration.
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            // Keep numerical integration off the main thread; discard results of superseded inputs.
            let calculation = Task.detached(priority: .userInitiated) {
                do { return Result<[SpectrumBin], Error>.success(try GammaSpectrum.simulate(input.setup, resolution: input.resolution)) }
                catch { return .failure(error) }
            }
            let result = await withTaskCancellationHandler {
                await calculation.value
            } onCancel: {
                calculation.cancel()
            }
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let output): bins = output
            case .failure(let failure): error = failure.localizedDescription
            }
            calculating = false
        }
    }

    private var resolutionLabel: String {
        let model = workbench.resolutionModel
        if let preset = ResolutionModel.presets.first(where: { $0.model == model }) { return preset.name }
        return "Custom \(model.kind == .semiconductor ? "semiconductor" : "scintillator") · \(Fmt.keV(model.fwhm(at: 1332.5))) keV FWHM at 1332.5 keV"
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
