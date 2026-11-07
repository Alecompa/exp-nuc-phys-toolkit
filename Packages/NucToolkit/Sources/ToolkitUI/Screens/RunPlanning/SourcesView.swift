import NucPhysKit
import SwiftUI

struct SourcesView: View {
    @Environment(Workbench.self) private var workbench
    @State private var adding: SourceCertificate?

    var body: some View {
        List {
            Section {
                if workbench.sources.isEmpty {
                    ContentUnavailableView {
                        Label("No sources yet", systemImage: "rays")
                    } description: {
                        Text("Add the sources of your lab with their certificate activity and reference date.")
                    }
                }
                ForEach(workbench.sources) { cert in
                    NavigationLink {
                        SourceDetailView(certificateID: cert.id, catalog: catalogSource(cert))
                    } label: {
                        CertificateRow(certificate: cert)
                    }
                }
                .onDelete { workbench.sources.remove(atOffsets: $0) }
                Button {
                    adding = SourceCertificate(nuclide: "137Cs", activity: 1e4, referenceDate: .now)
                } label: {
                    Label("Add Source", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("My sources")
            }

            Section {
                ForEach(CalibrationSources.all) { s in
                    NavigationLink {
                        SourceDetailView(certificateID: nil, catalog: s)
                    } label: {
                        HStack(spacing: 12) {
                            SourceTile(label: s.state.plainLabel, z: s.state.z)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.label).font(.body.weight(.medium))
                                Text(s.prominentLines(minIntensity: 5).filter { $0.kind != .xray }.prefix(3)
                                        .map { Fmt.keV($0.energy, digits: 4) }.joined(separator: ", ") + " keV")
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(Fmt.halfLife(s.state.halfLife, digits: 4))
                                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Catalog")
            } footer: {
                Text("Half-lives from NUBASE2020; γ- and X-ray intensities from ENSDF via the IAEA LiveChart of Nuclides (snapshot bundled with the app).")
            }
        }
        .groupedList()
        .navigationTitle("Calibration Sources")
        .inlineTitle()
        .sheet(item: $adding) { cert in
            CertificateSheet(initial: cert, isNew: true)
        }
    }

    private func catalogSource(_ c: SourceCertificate) -> CalibrationSource? {
        CalibrationSources.source(named: c.nuclide)
    }
}

private struct SourceTile: View {
    let label: String
    let z: Int
    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(width: 44, height: 44)
            .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct CertificateRow: View {
    let certificate: SourceCertificate
    var body: some View {
        HStack(spacing: 12) {
            SourceTile(label: certificate.nuclide, z: certificate.state?.z ?? 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(certificate.name.isEmpty ? (certificate.state?.label ?? certificate.nuclide) : certificate.name)
                    .font(.body.weight(.medium))
                Text("Reference \(certificate.referenceDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if let now = certificate.activity(at: .now) {
                let a = Fmt.activity(now.activity)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(a.value) \(a.unit)").monospacedDigit()
                    Text("± \(Fmt.significant(100 * now.relativeUncertainty, digits: 2)) %").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SourceDetailView: View {
    @Environment(Workbench.self) private var workbench
    let certificateID: UUID?
    let catalog: CalibrationSource?
    @AppStorage("sources.freeActivity") private var freeActivity = 1e4      // Bq, for catalog sources
    @AppStorage("sources.distance") private var distance = 1.0             // m
    @AppStorage("sources.liveHours") private var liveHours = 1.0
    @State private var editing: SourceCertificate?
    @State private var date = Date.now

    private var certificate: SourceCertificate? { workbench.sources.first { $0.id == certificateID } }

    var body: some View {
        let state = certificate?.state ?? catalog?.state
        let lines = (catalog ?? certificate.flatMap { CalibrationSources.source(named: $0.nuclide) })?.lines ?? []
        let now = certificate?.activity(at: date)
        let activity = now?.activity ?? freeActivity
        let fit = workbench.efficiencyCurve.fit()

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    let a = Fmt.activity(activity)
                    HeroNumber(value: a.value, unit: a.unit,
                               caption: certificate != nil ? "Activity on \(date.formatted(date: .abbreviated, time: .omitted))" : "Activity")
                    HStack(spacing: 8) {
                        if let now { StatusBadge(text: "\(Fmt.significant(100 * now.relativeUncertainty, digits: 2)) %", symbol: "plusminus", tint: .orange) }
                        if let s = state { StatusBadge(text: "T½ \(Fmt.halfLife(s.halfLife, digits: 4))", symbol: "hourglass", tint: .cyan) }
                    }
                }
                .padding(.vertical, 6)
                if certificate != nil {
                    DatePicker("Date", selection: $date)
                } else {
                    LabeledContent("Activity") {
                        HStack { ScientificTextField(title: "Activity", value: $freeActivity); Text("Bq").foregroundStyle(.secondary) }
                    }
                }
            }

            if let cert = certificate, let now {
                Section {
                    let a0 = Fmt.activity(cert.activity)
                    ValueRow(label: "Reference activity", value: a0.value, unit: a0.unit, note: "± \(Fmt.significant(100 * cert.relativeUncertainty, digits: 2)) % on \(cert.referenceDate.formatted(date: .abbreviated, time: .omitted))")
                    let d = Fmt.duration(now.elapsed)
                    ValueRow(label: "Elapsed", value: d.value, unit: d.unit)
                    ValueRow(label: "Remaining fraction", value: Fmt.significant(now.activity / cert.activity, digits: 4))
                    Button("Edit Certificate") { editing = cert }
                } header: {
                    Text(cert.name.isEmpty ? "Certificate" : cert.name)
                } footer: {
                    Text("The uncertainty combines the certificate and the half-life (λt · σ_T/T) in quadrature.")
                }
            }

            if let s = state {
                Section {
                    ValueRow(label: "Half-life", value: s.halfLifeText.isEmpty ? Fmt.halfLife(s.halfLife) : s.halfLifeText)
                    if !s.spinParity.isEmpty { ValueRow(label: "Jπ", value: s.spinParity) }
                    ForEach(s.decayModes, id: \.self) { m in ValueRow(label: "Decay", value: m.text) }
                    if s.excitation > 0 { ValueRow(label: "Isomer energy", value: Fmt.keV(s.excitation), unit: "keV") }
                } header: {
                    Text("\(s.label) · NUBASE2020")
                }
            }

            Section {
                NumberField(title: "Live time", value: $liveHours, unit: "h", range: 1e-4...1e5)
                let shown = lines.filter { $0.kind == .xray ? $0.intensity >= 5 : $0.intensity >= 0.5 }
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        Text("E (keV)"); Text("I (%)"); Text("γ/s"); Text(fit != nil ? "Counts" : "")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    ForEach(shown) { l in
                        let rate = activity * l.intensity / 100
                        GridRow {
                            Text(Fmt.keV(l.energy, digits: 6) + (l.kind == .xray ? " X" : l.kind == .annihilation ? " β⁺" : ""))
                            Text(Fmt.significant(l.intensity, digits: 4))
                            Text(Fmt.significant(rate, digits: 3))
                            Text(fit.map { Fmt.significant(rate * $0.efficiency(at: l.energy) * liveHours * 3600, digits: 3) } ?? "")
                        }
                        .font(.caption.monospacedDigit())
                    }
                }
                .textSelection(.enabled)
            } header: {
                Text("Photon emissions")
            } footer: {
                Text("Counts in the full-energy peak with the Detector Response efficiency curve, during the live time; decay during the measurement and coincidence summing are neglected.")
            }

            Section {
                NumberField(title: "Distance", value: $distance, unit: "m", range: 0.01...1000)
                let k = AirKerma.rateConstant(lines: lines)
                ValueRow(label: "Air-kerma rate", value: Fmt.significant(AirKerma.rate(lines: lines, activity: activity, distance: distance), digits: 3),
                         unit: "µGy/h")
                ValueRow(label: "Rate constant", value: Fmt.significant(k, digits: 3), unit: "µGy m²/(MBq h)")
            } header: {
                Text("Dose rate")
            } footer: {
                Text("Unshielded point source in air, photons above 20 keV, NIST μ_en/ρ of air. The ambient dose equivalent H*(10) is about 1.1–1.2 × the air kerma for these energies. Not a substitute for a survey meter.")
            }
        }
        .groupedList()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .navigationTitle(certificate.map { $0.name.isEmpty ? (state?.label ?? $0.nuclide) : $0.name } ?? state?.label ?? "Source")
        .inlineTitle()
        .sheet(item: $editing) { CertificateSheet(initial: $0, isNew: false) }
        .notebookSnapshot {
            var s = NotebookSnapshot(tool: .sources, title: "\(state?.label ?? "Source") activity",
                                     subtitle: date.formatted(date: .abbreviated, time: .shortened))
            let a = Fmt.activity(activity)
            s.add("Source", "Activity", a.value, a.unit)
            if let now { s.add("Source", "Uncertainty", Fmt.significant(100 * now.relativeUncertainty, digits: 2), "%") }
            if let st = state { s.add("Source", "Half-life", Fmt.halfLife(st.halfLife)) }
            for l in lines where l.kind == .gamma && l.intensity >= 1 {
                s.add("γ lines", Fmt.keV(l.energy) + " keV", Fmt.significant(activity * l.intensity / 100, digits: 4), "γ/s")
            }
            return s
        }
    }
}

/// Add or edit a source certificate.
struct CertificateSheet: View {
    @Environment(Workbench.self) private var workbench
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SourceCertificate
    @State private var value: Double
    @State private var unit: ActivityUnit = .kBq
    let isNew: Bool

    init(initial: SourceCertificate, isNew: Bool) {
        _draft = State(initialValue: initial)
        self.isNew = isNew
        let u: ActivityUnit = initial.activity >= 1e6 ? .MBq : initial.activity >= 1e3 ? .kBq : .Bq
        _unit = State(initialValue: u)
        _value = State(initialValue: initial.activity / u.scale)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Nuclide", selection: $draft.nuclide) {
                        ForEach(CalibrationSources.all) { Text($0.label).tag($0.id) }
                        if CalibrationSources.source(named: draft.nuclide) == nil {
                            Text(draft.nuclide).tag(draft.nuclide)
                        }
                    }
                    TextField("Name (e.g. certificate number)", text: $draft.name)
                } footer: {
                    if let s = draft.state { Text("T½ = \(s.halfLifeText.isEmpty ? Fmt.halfLife(s.halfLife) : s.halfLifeText)") }
                }
                Section("Certificate") {
                    LabeledContent("Activity") {
                        HStack(spacing: 6) {
                            ScientificTextField(title: "Activity", value: $value)
                            Picker("Unit", selection: $unit) {
                                ForEach(ActivityUnit.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                    NumberField(title: "Uncertainty", value: Binding(get: { draft.relativeUncertainty * 100 },
                                                                     set: { draft.relativeUncertainty = $0 / 100 }), unit: "%", range: 0...100)
                    DatePicker("Reference date", selection: $draft.referenceDate, displayedComponents: .date)
                }
            }
            .navigationTitle(isNew ? "New Source" : "Edit Source")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        draft.activity = value * unit.scale
                        if let i = workbench.sources.firstIndex(where: { $0.id == draft.id }) {
                            workbench.sources[i] = draft
                        } else {
                            workbench.sources.append(draft)
                        }
                        dismiss()
                    }
                    .disabled(value <= 0 || draft.state?.halfLife == nil)
                }
            }
        }
    }
}
