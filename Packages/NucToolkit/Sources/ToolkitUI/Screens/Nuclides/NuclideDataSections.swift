import NucPhysKit
import SwiftUI

/// Half-life, spin-parity, decay modes, abundance and isomers from NUBASE2020.
struct NubaseSection: View {
    let nuclide: Nuclide

    var body: some View {
        let states = Nubase.nubase2020.states(z: nuclide.z, a: nuclide.a)
        if let gs = states.first(where: \.isGroundState) {
            Section {
                ValueRow(label: "Half-life", value: gs.isStable ? "stable" : (gs.halfLifeText.isEmpty ? Fmt.halfLife(gs.halfLife) : gs.halfLifeText))
                if !gs.spinParity.isEmpty {
                    ValueRow(label: "Jπ", value: gs.spinParity, note: gs.spinParityIsEstimated ? "From systematics" : nil)
                }
                if let ab = gs.abundance {
                    ValueRow(label: "Natural abundance", value: Fmt.significant(ab, digits: 5), unit: "%")
                }
                ForEach(gs.decayModes, id: \.self) { m in
                    ValueRow(label: "Decay", value: m.text)
                }
            } header: {
                Text("NUBASE2020")
            }

            let isomers = states.filter { !$0.isGroundState }
            if !isomers.isEmpty {
                Section {
                    ForEach(isomers) { s in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.label).font(.body.weight(.medium))
                                Text("\(Fmt.keV(s.excitation, digits: 6))\(s.excitationIsEstimated ? "#" : "") keV\(s.spinParity.isEmpty ? "" : " · " + s.spinParity)")
                                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(s.halfLifeText.isEmpty ? Fmt.halfLife(s.halfLife) : s.halfLifeText).monospacedDigit()
                                Text(s.decayModes.prefix(2).map(\.text).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Isomers")
                }
            }
        }
    }
}

/// Excited levels and γ rays from ENSDF, fetched from the IAEA LiveChart API and cached.
struct LevelSchemeSection: View {
    let nuclide: Nuclide
    @Environment(Workbench.self) private var workbench
    @State private var scheme: LevelScheme?
    @State private var error: String?
    @State private var loading = false
    @State private var confirmation = 0

    private static let shown = 12

    var body: some View {
        Section {
            if let scheme {
                let isResidual = workbench.reaction?.residual == nuclide
                ForEach(scheme.levels.prefix(Self.shown)) { l in
                    LevelRow(level: l)
                        .contextMenu {
                            if isResidual, l.energy > 0 {
                                Button("Use as Final State", systemImage: "scope") {
                                    workbench.residualExcitation = l.energy
                                    confirmation += 1
                                }
                            }
                            Button("Copy Energy", systemImage: "doc.on.doc") { Pasteboard.copy(Fmt.keV(l.energy, digits: 8)) }
                        }
                }
                NavigationLink {
                    LevelSchemeDetailView(nuclide: nuclide, scheme: scheme)
                } label: {
                    Label("All \(scheme.levels.count) levels and \(scheme.gammas.count) γ rays", systemImage: "list.bullet.indent")
                }
            } else if loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading from the IAEA…").foregroundStyle(.secondary)
                }
            } else if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                    Button("Try Again") { Task { await load(force: true) } }
                }
            } else {
                Button {
                    Task { await load(force: false) }
                } label: {
                    Label("Load levels and γ rays", systemImage: "icloud.and.arrow.down")
                }
            }
        } header: {
            HStack {
                Text("Levels · ENSDF")
                Spacer()
                if scheme != nil {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await load(force: true) } }
                        .labelStyle(.iconOnly)
                        .disabled(loading)
                }
            }
        } footer: {
            if let scheme {
                Text("\(scheme.reference.isEmpty ? "ENSDF" : "ENSDF: " + scheme.reference). From the IAEA LiveChart of Nuclides, retrieved \(scheme.retrieved.formatted(date: .abbreviated, time: .omitted)); cached for offline use. \(workbench.reaction?.residual == nuclide ? "Touch and hold a level to use it as the final state." : "")")
            } else {
                Text("Needs an internet connection the first time; afterwards the data stay available offline.")
            }
        }
        .sensoryFeedback(.success, trigger: confirmation)
        .task(id: nuclide.id) {
            // Show cached data instantly; otherwise fetch unless automatic loading is off in Settings.
            if let c = await LiveChartClient.shared.cached(z: nuclide.z, a: nuclide.a) {
                scheme = c
            } else if UserDefaults.standard.object(forKey: "livechart.autoload") as? Bool ?? true {
                await load(force: false)
            }
        }
    }

    private func load(force: Bool) async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let s = try await LiveChartClient.shared.levelScheme(z: nuclide.z, a: nuclide.a, forceRefresh: force)
            withAnimation(.smooth) { scheme = s }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct LevelRow: View {
    let level: Level
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Fmt.levelEnergy(level.energy, uncertainty: level.energyUncertainty))
                .monospacedDigit()
                .frame(minWidth: 80, alignment: .leading)
            Text(level.spinParity.isEmpty ? "—" : level.spinParity)
                .foregroundStyle(.secondary)
            Spacer()
            Text(Fmt.levelHalfLife(level))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct LevelSchemeDetailView: View {
    let nuclide: Nuclide
    let scheme: LevelScheme
    @State private var mode = Mode.levels
    @State private var search = ""

    enum Mode: String, CaseIterable, Identifiable {
        case levels = "Levels", gammas = "γ rays"
        var id: String { rawValue }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            switch mode {
            case .levels:
                Section {
                    ForEach(filteredLevels) { l in
                        DisclosureGroup {
                            let out = scheme.gammas.filter { abs($0.initialLevel - l.energy) < 0.01 }
                            if out.isEmpty {
                                Text("No γ decay listed").foregroundStyle(.secondary)
                            }
                            ForEach(out) { g in GammaRow(gamma: g) }
                        } label: {
                            LevelRow(level: l)
                        }
                    }
                } header: {
                    Text("E (keV) · Jπ · T½")
                }
            case .gammas:
                Section {
                    ForEach(filteredGammas) { g in GammaRow(gamma: g) }
                } header: {
                    Text("Eγ (keV) · initial → final level · I_rel · multipolarity")
                }
            }
        }
        .groupedList()
        .searchable(text: $search, prompt: "Energy (keV)")
        .navigationTitle("\(nuclide.label) levels")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .trailingBar) {
                ShareLink(item: CSVFile(name: "\(nuclide.plainLabel)_\(mode == .levels ? "levels" : "gammas")", text: csv),
                          preview: SharePreview("\(nuclide.label) \(mode.rawValue)", image: Image(systemName: "tablecells"))) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var filteredLevels: [Level] {
        guard let e = Double(search) else { return scheme.levels }
        return scheme.levels.filter { abs($0.energy - e) < max(50, 0.02 * e) }
    }

    private var filteredGammas: [GammaTransition] {
        let all = scheme.gammas.sorted { $0.energy < $1.energy }
        guard let e = Double(search) else { return all }
        return all.filter { abs($0.energy - e) < max(20, 0.01 * e) }
    }

    private var csv: String {
        switch mode {
        case .levels:
            "energy_keV,unc_keV,jpi,half_life\n" + scheme.levels.map {
                [String($0.energy), $0.energyUncertainty.map { String($0) } ?? "", $0.spinParity, $0.halfLife].map(NotebookEntry.csvField).joined(separator: ",")
            }.joined(separator: "\n") + "\n"
        case .gammas:
            "egamma_keV,unc_keV,initial_keV,final_keV,relative_intensity,multipolarity\n" + scheme.gammas.map {
                [String($0.energy), $0.energyUncertainty.map { String($0) } ?? "", String($0.initialLevel), String($0.finalLevel),
                 $0.relativeIntensity.map { String($0) } ?? "", $0.multipolarity].map(NotebookEntry.csvField).joined(separator: ",")
            }.joined(separator: "\n") + "\n"
        }
    }
}

private struct GammaRow: View {
    let gamma: GammaTransition
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.levelEnergy(gamma.energy, uncertainty: gamma.energyUncertainty) + " keV").monospacedDigit()
                Text("\(Fmt.levelEnergy(gamma.initialLevel, uncertainty: nil)) → \(Fmt.levelEnergy(gamma.finalLevel, uncertainty: nil))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let i = gamma.relativeIntensity { Text(Fmt.significant(i, digits: 3)).monospacedDigit() }
                if !gamma.multipolarity.isEmpty { Text(gamma.multipolarity).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension Fmt {
    /// Level or γ energy with as many decimals as its uncertainty supports.
    static func levelEnergy(_ keV: Double, uncertainty: Double?) -> String {
        if keV == 0 { return "0" }
        // PDG rule: two significant digits of uncertainty when it starts with 1 or 2, otherwise one.
        let d = uncertainty.flatMap { u -> Int? in
            guard u > 0, u.isFinite else { return nil }
            let exp = Int(floor(log10(u)))
            let lead = u / pow(10, Double(exp))
            return min(4, max(0, (lead < 3 ? 1 : 0) - exp))
        }
            ?? min(3, max(0, String(keV).split(separator: ".").last.map { $0 == "0" ? 0 : $0.count } ?? 0))
        return number(keV, decimals: d)
    }

    /// ENSDF half-life: converted from seconds when available ("717 ky"), otherwise the evaluator's text (widths, "STABLE").
    static func levelHalfLife(_ l: Level) -> String {
        if l.halfLife.uppercased().hasPrefix("STABLE") { return "stable" }
        if let s = l.halfLifeSeconds, s > 0 { return halfLife(s, digits: 3) }
        return l.halfLife
    }
}
