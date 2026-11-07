import Charts
import NucPhysKit
import SwiftUI
import UniformTypeIdentifiers

/// The rate of the current entrance channel on the standard temperature grid.
struct RateTable: Sendable {
    struct Row: Identifiable, Sendable {
        var id: Double { t9 }
        let t9: Double
        let nonResonant: Double
        let resonant: Double
        var total: Double { nonResonant + resonant }
    }
    let rows: [Row]

    init(channel c: ChargedChannel, model: SFactorModel, resonances: [NarrowResonance], grid: [Double] = ChargedChannel.rateGrid) {
        rows = grid.map { t in
            Row(t9: t, nonResonant: c.rate(sFactor: model, t9: t),
                resonant: resonances.reduce(0) { $0 + c.narrowResonanceRate($1, t9: t) })
        }
    }
}

struct ReactionRateView: View {
    @Environment(Workbench.self) private var workbench
    @State private var editingSetup = false
    @State private var editingTable = false
    @State private var table: RateTable?
    @State private var showsTable = false

    private struct Key: Hashable {
        let channel: ChargedChannel
        let model: SFactorModel
        let resonances: [NarrowResonance]
    }

    var body: some View {
        Group {
            if let r = workbench.reaction, let c = workbench.entranceChannel {
                content(r, c)
                    .task(id: Key(channel: c, model: workbench.sFactorModel, resonances: workbench.resonances)) {
                        let model = workbench.sFactorModel, res = workbench.resonances
                        let t = await Task.detached(priority: .userInitiated) {
                            RateTable(channel: c, model: model, resonances: res)
                        }.value
                        withAnimation(.smooth) { table = t }
                    }
            } else {
                NoChargedChannelView(symbol: "flame.fill", editingSetup: $editingSetup)
            }
        }
        .navigationTitle("Reaction Rate")
        .inlineTitle()
        .toolbar {
            if let table, let r = workbench.reaction {
                ToolbarItem(placement: .trailingBar) {
                    ShareLink(item: RateTableExport(table: table, label: r.plainLabelForFile),
                              preview: SharePreview("Rate table, \(r.label)", image: Image(systemName: "tablecells"))) {
                        Label("Export Rate Table", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
        .sheet(isPresented: $editingTable) { SFactorTableSheet() }
    }

    @ViewBuilder
    private func content(_ r: Reaction, _ c: ChargedChannel) -> some View {
        @Bindable var workbench = workbench
        let t9 = workbench.temperatureT9
        let model = workbench.sFactorModel
        let nonRes = c.rate(sFactor: model, t9: t9)
        let res = workbench.resonances.reduce(0) { $0 + c.narrowResonanceRate($1, t9: t9) }
        let total = nonRes + res
        let w = c.gamowWindow(t9: t9)
        let extrapolated = model.tableRange.map { w.lower < $0.lowerBound || w.upper > $0.upperBound } ?? false

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    ReactionHeader(reaction: r) { editingSetup = true }
                    HeroNumber(value: Fmt.significant(total), unit: "cm³/(mol s)",
                               caption: "Nₐ⟨σv⟩ at T₉ = \(Fmt.significant(t9, digits: 3))")
                    HStack(spacing: 8) {
                        if total > 0, !workbench.resonances.isEmpty {
                            StatusBadge(text: "Resonant \(Fmt.number(100 * res / total, decimals: 1)) %",
                                        symbol: "waveform.path.ecg", tint: .pink)
                        }
                        if extrapolated {
                            StatusBadge(text: "S(E) extrapolated", symbol: "exclamationmark.triangle.fill", tint: .orange)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                TemperatureControl()
                ValueRow(label: "Non-resonant", value: Fmt.significant(nonRes),
                         note: "Gamow window \(Fmt.keV(w.lower, digits: 3))–\(Fmt.keV(w.upper, digits: 3)) keV")
                ValueRow(label: "Narrow resonances", value: Fmt.significant(res))
            } header: {
                Text("Temperature")
            } footer: {
                Text("Rates in cm³ mol⁻¹ s⁻¹.")
            }

            Section {
                if let table {
                    RateChart(table: table, t9: t9)
                        .frame(height: 260)
                        .padding(.vertical, 8)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 260)
                }
                DisclosureGroup("Rate table", isExpanded: $showsTable) {
                    if let table {
                        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("T₉"); Text("Non-res."); Text("Res."); Text("Total")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            ForEach(table.rows) { row in
                                GridRow {
                                    Text(Fmt.significant(row.t9, digits: 3))
                                    Text(Fmt.significant(row.nonResonant, digits: 3))
                                    Text(Fmt.significant(row.resonant, digits: 3))
                                    Text(Fmt.significant(row.total, digits: 3)).fontWeight(.semibold)
                                }
                                .font(.caption.monospacedDigit())
                            }
                        }
                        .textSelection(.enabled)
                    }
                }
            } header: {
                Text("vs temperature")
            } footer: {
                Text("Nₐ⟨σv⟩ = Nₐ √(8/πμ) (kT)^−3/2 ∫ S(E) exp(−2πη − E/kT) dE, integrated numerically, plus the narrow resonances. Bare rate: no stellar or laboratory screening, no thermal excitation of the target.")
            }

            Section {
                Picker("S factor", selection: $workbench.sFactorModel.kind.animation(.smooth)) {
                    Text("Polynomial").tag(SFactorModel.Kind.polynomial)
                    Text("Table").tag(SFactorModel.Kind.table)
                }
                .pickerStyle(.segmented)

                switch model.kind {
                case .polynomial:
                    ScientificField(title: "S(0)", value: $workbench.sFactorModel.s0, unit: "keV b")
                    SignedField(title: "S′(0)", value: $workbench.sFactorModel.s1, unit: "b")
                    SignedField(title: "S″(0)", value: $workbench.sFactorModel.s2, unit: "b/keV")
                case .table:
                    if let range = model.tableRange {
                        ValueRow(label: "Points", value: "\(model.table.count)")
                        ValueRow(label: "Range", value: "\(Fmt.keV(range.lowerBound, digits: 4))–\(Fmt.keV(range.upperBound, digits: 4))", unit: "keV")
                    } else {
                        Text("No table yet").foregroundStyle(.secondary)
                    }
                    Button {
                        editingTable = true
                    } label: {
                        Label(model.table.isEmpty ? "Add Table" : "Edit Table", systemImage: "tablecells")
                    }
                }
                ValueRow(label: "S at E₀", value: Fmt.significant(model.s(at: w.peak)), unit: "keV b")
            } header: {
                Text("Non-resonant S factor")
            } footer: {
                Text(model.kind == .polynomial
                     ? "S(E) = S(0) + S′(0)E + ½S″(0)E², E in keV (c.m.); negative values are cut at zero."
                     : "Interpolated linearly in ln S, held constant beyond the table ends. Energies in keV (c.m.), S in keV b.")
            }

            Section {
                ForEach($workbench.resonances) { $res in
                    ResonanceRow(resonance: $res, channel: c, t9: t9)
                }
                .onDelete { workbench.resonances.remove(atOffsets: $0) }
                Button {
                    let e = (workbench.resonances.last?.energy ?? w.peak * 2).rounded(toPlaces: 1)
                    withAnimation(.smooth) { workbench.resonances.append(NarrowResonance(energy: e, strength: 1e-6)) }
                } label: {
                    Label("Add Resonance", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Narrow resonances")
            } footer: {
                Text("E_R in the centre of mass. Measure ωγ in Resonance Strength and add it from there.")
            }
        }
        .groupedList()
        .notebookSnapshot {
            var s = NotebookSnapshot(tool: .reactionRate, title: "\(r.label) at T₉ = \(Fmt.significant(t9, digits: 3))")
            s.add("Rate", "Total Nₐ⟨σv⟩", Fmt.significant(total), "cm³/(mol s)")
            s.add("Rate", "Non-resonant", Fmt.significant(nonRes), "cm³/(mol s)")
            s.add("Rate", "Narrow resonances", Fmt.significant(res), "cm³/(mol s)")
            s.add("Gamow window", "E₀", Fmt.keV(w.peak), "keV")
            s.add("Gamow window", "S at E₀", Fmt.significant(model.s(at: w.peak)), "keV b")
            for (i, rr) in workbench.resonances.enumerated() {
                s.add("Resonances", "\(i + 1). E_R = \(Fmt.keV(rr.energy)) keV", Fmt.significant(rr.strength), "eV")
            }
            return s
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
    }
}

private struct ResonanceRow: View {
    @Binding var resonance: NarrowResonance
    let channel: ChargedChannel
    let t9: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("E_R", value: $resonance.energy, format: .number.precision(.significantDigits(1...7)).grouping(.never))
                    .monospacedDigit()
                    .decimalKeyboard()
                    .fixedSize()
                Text("keV").foregroundStyle(.secondary)
                Spacer()
                Text("ωγ").foregroundStyle(.secondary)
                ScientificTextField(title: "ωγ", value: $resonance.strength)
                    .fixedSize()
                Text("eV").foregroundStyle(.secondary)
            }
            Text("Nₐ⟨σv⟩ = \(Fmt.significant(channel.narrowResonanceRate(resonance, t9: t9), digits: 3)) at this T₉")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

/// A value that may be negative (polynomial coefficients).
struct SignedField: View {
    let title: String
    @Binding var value: Double
    var unit: String? = nil

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                ScientificTextField(title: title, value: $value, allowsNegative: true)
                if let unit { Text(unit).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct RateChart: View {
    let table: RateTable
    let t9: Double

    private enum Series: String, CaseIterable {
        case total = "Total", nonResonant = "Non-resonant", resonant = "Resonances"
        var color: Color {
            switch self {
            case .total: .red
            case .nonResonant: .indigo
            case .resonant: .orange
            }
        }
    }

    private func value(_ s: Series, _ r: RateTable.Row) -> Double {
        switch s {
        case .total: r.total
        case .nonResonant: r.nonResonant
        case .resonant: r.resonant
        }
    }

    var body: some View {
        let positive = table.rows.map(\.total).filter { $0 > 0 }
        let yMax = (positive.max() ?? 1) * 10
        let yMin = max(positive.min() ?? 1e-30, yMax * 1e-40, 1e-99)
        let series = Series.allCases.filter { s in s == .total || table.rows.contains { value(s, $0) > 0 } }
        let xr = (table.rows.first?.t9 ?? 0.001)...(table.rows.last?.t9 ?? 10)

        Chart {
            ForEach(series, id: \.self) { s in
                ForEach(table.rows.filter { value(s, $0) >= yMin }) { r in
                    LineMark(x: .value("T₉", r.t9), y: .value("Rate", value(s, r)), series: .value("Series", s.rawValue))
                        .foregroundStyle(by: .value("Series", s.rawValue))
                        .lineStyle(StrokeStyle(lineWidth: s == .total ? 3.5 : 1.8, lineCap: .round,
                                               dash: s == .total ? [] : [5, 3]))
                        .opacity(s == .total ? 0.55 : 1)
                        .interpolationMethod(.catmullRom)
                }
            }
            RuleMark(x: .value("T₉", t9))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
        }
        .chartForegroundStyleScale(domain: series.map(\.rawValue), range: series.map(\.color))
        .chartLegend(position: .top, alignment: .leading)
        .chartXScale(domain: xr, type: .log)
        .chartYScale(domain: yMin...yMax, type: .log)
        .chartXAxis {
            AxisMarks(values: decades(xr)) { v in
                AxisGridLine(); AxisTick()
                AxisValueLabel { if let x = v.as(Double.self) { Text(Fmt.significant(x, digits: 1)) } }
            }
        }
        .chartYAxis {
            AxisMarks(values: sparseDecades(yMin...yMax)) { v in
                AxisGridLine()
                AxisValueLabel { if let y = v.as(Double.self) { PowerOfTenLabel(value: y) } }
            }
        }
        .chartXAxisLabel("T₉ (GK)", alignment: .leading)
        .chartYAxisLabel("cm³/(mol s)")
        .accessibilityLabel("Reaction rate versus temperature")
    }
}

/// Paste or import an S-factor table.
private struct SFactorTableSheet: View {
    @Environment(Workbench.self) private var workbench
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var importing = false
    @State private var importError: String?

    private var parsed: Result<[SFactorModel.Point], Error> {
        Result { try SFactorModel.parseTable(text) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 220)
                        .notationInput()
                } header: {
                    Text("E (keV, c.m.), S (keV b)")
                } footer: {
                    Text("One point per line; commas, semicolons, tabs or spaces between columns; # starts a comment; a header line is skipped.")
                }
                Section {
                    switch parsed {
                    case .success(let pts):
                        Label("\(pts.count) points, \(Fmt.keV(pts.first!.energy, digits: 4))–\(Fmt.keV(pts.last!.energy, digits: 4)) keV",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let e):
                        Label(e.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if let importError {
                        Label(importError, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Import CSV or Text File", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationTitle("S-Factor Table")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        if case .success(let pts) = parsed {
                            workbench.sFactorModel.table = pts
                            workbench.sFactorModel.kind = .table
                        }
                        dismiss()
                    }
                    .disabled((try? parsed.get()) == nil)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .tabSeparatedText, .text]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    text = try String(contentsOf: url, encoding: .utf8)
                    importError = nil
                } catch {
                    importError = error.localizedDescription
                }
            }
            .onAppear { if text.isEmpty { text = workbench.sFactorModel.tableText } }
        }
    }
}

struct RateTableExport: Transferable {
    let table: RateTable
    let label: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.csv().utf8) }
            .suggestedFileName { "rate_\($0.label).csv" }
    }

    func csv() -> String {
        var s = "# N_A<sigma v> in cm^3 mol^-1 s^-1 (bare, narrow resonances)\nT9,non_resonant,resonant,total\n"
        for r in table.rows {
            s += [r.t9, r.nonResonant, r.resonant, r.total].map { String(format: "%.6e", $0) }.joined(separator: ",") + "\n"
        }
        return s
    }
}

extension Reaction {
    /// ASCII label for file names, e.g. 12C_p_g_13N.
    var plainLabelForFile: String {
        let ej = ejectile.nuclide?.plainLabel ?? "g"
        return "\(target.plainLabel)_\(projectile.plainLabel)_\(ej)_\(residual.plainLabel)"
    }
}
