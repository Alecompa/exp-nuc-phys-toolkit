import Charts
import NucPhysKit
import SwiftUI

// EXFOR explorer: measured cross sections and S factors from IAEA-NDS/exfortables_py.
// The index is bundled; tables download from GitHub when a channel is opened and are cached.

/// The bundled index, decompressed off the main thread the first time it is needed.
func exforIndex() async -> ExforIndex {
    await Task.detached(priority: .userInitiated) { ExforIndex.bundled }.value
}

struct ExforChannelGroup: Identifiable, Hashable {
    let channel: ExforChannel
    let datasets: [ExforDataset]
    var id: String { channel.id }
}

private func channelGroups(target: Nuclide) async -> [ExforChannelGroup] {
    let index = await exforIndex()
    return await Task.detached(priority: .userInitiated) {
        index.channels(target: target).map { ExforChannelGroup(channel: $0.channel, datasets: $0.datasets) }
    }.value
}

// MARK: - Nuclide page section

/// Reaction channels with EXFOR data on this nuclide as a target.
struct ExforTargetSection: View {
    let nuclide: Nuclide
    @State private var groups: [ExforChannelGroup]?

    private static let shown = 6

    var body: some View {
        Section {
            if let groups {
                if groups.isEmpty {
                    Text("No charged-particle cross sections on this target in EXFOR.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groups.prefix(Self.shown)) { g in
                        NavigationLink {
                            ExforChannelView(title: "\(nuclide.label)\(g.channel.label)", target: nuclide,
                                             entrance: g.channel.entranceChannel(target: nuclide), datasets: g.datasets)
                        } label: {
                            ExforChannelRow(target: nuclide, group: g)
                        }
                    }
                    if groups.count > Self.shown {
                        NavigationLink {
                            ExforChannelListView(target: nuclide, groups: groups)
                        } label: {
                            Label("All \(groups.count) reactions, \(groups.reduce(0) { $0 + $1.datasets.count }) tables",
                                  systemImage: "list.bullet")
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the EXFOR index…").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Cross sections · EXFOR")
        } footer: {
            Text("Measured data with \(nuclide.label) as the target, from the IAEA EXFOR library. A reaction's tables download when you open it and stay available offline.")
        }
        .task(id: nuclide.id) { groups = await channelGroups(target: nuclide) }
    }
}

private struct ExforChannelRow: View {
    let target: Nuclide
    let group: ExforChannelGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(target.label)\(group.channel.label)").font(.body.weight(.medium))
                Text(group.channel.kind).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(group.datasets.count)").monospacedDigit()
                Text(yearRange).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var yearRange: String {
        let y = group.datasets.map(\.year)
        guard let a = y.min(), let b = y.max() else { return "" }
        return a == b ? "\(a)" : "\(a)–\(b)"
    }
}

/// Every channel on a target, grouped by projectile.
struct ExforChannelListView: View {
    let target: Nuclide
    let groups: [ExforChannelGroup]
    @State private var search = ""

    var body: some View {
        let shown = search.isEmpty ? groups : groups.filter {
            "\($0.channel.label) \($0.channel.kind)".localizedCaseInsensitiveContains(search)
        }
        let projectiles = shown.map(\.channel.projectile).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        List {
            ForEach(projectiles, id: \.self) { p in
                Section(header: Text("\(ExforChannel(projectile: p, target: "", outgoing: "").projectileLabel)-induced")) {
                    ForEach(shown.filter { $0.channel.projectile == p }) { g in
                        NavigationLink {
                            ExforChannelView(title: "\(target.label)\(g.channel.label)", target: target,
                                             entrance: g.channel.entranceChannel(target: target), datasets: g.datasets)
                        } label: {
                            ExforChannelRow(target: target, group: g)
                        }
                    }
                }
            }
        }
        .groupedList()
        .searchable(text: $search, prompt: "(p,γ), α, capture…")
        .navigationTitle("\(target.label) · EXFOR")
        .inlineTitle()
    }
}

// MARK: - Channel explorer

private enum TableState {
    case loading
    case loaded(ExforTable)
    case failed(String)
}

/// Plots and lists the tables of one reaction channel.
struct ExforChannelView<Header: View>: View {
    let title: String
    let target: Nuclide
    /// Projectile + target; nil disables the S factor and c.m. conversions.
    let entrance: ChargedChannel?
    let datasets: [ExforDataset]
    /// The channel is the current reaction setup: offer "Use in Reaction Rate".
    let isSetupReaction: Bool
    let header: () -> Header

    @Environment(Workbench.self) private var workbench
    @State private var finalState: Int?
    /// Incremented by "Try Again" to rerun the downloads.
    @State private var attempt = 0
    @State private var quantity = ExforTable.Quantity.crossSection
    @State private var frame = ExforTable.Frame.lab
    @State private var logX = true
    @State private var logY = true
    @State private var tables: [String: TableState] = [:]
    @State private var hidden: Set<String> = []

    init(title: String, target: Nuclide, entrance: ChargedChannel?, datasets: [ExforDataset],
         isSetupReaction: Bool = false, @ViewBuilder header: @escaping () -> Header) {
        self.title = title
        self.target = target
        self.entrance = entrance
        self.datasets = datasets
        self.isSetupReaction = isSetupReaction
        self.header = header
        // Total if any table has it, else the ground state, else the lowest level.
        _finalState = State(initialValue: Self.finalStates(of: datasets).first ?? nil)
    }

    /// Final states present, in display order: total, ground state, then levels.
    private var finalStates: [Int?] { Self.finalStates(of: datasets) }

    private static func finalStates(of datasets: [ExforDataset]) -> [Int?] {
        let levels = Set(datasets.map(\.level))
        return (levels.contains(nil) ? [nil] : []) + levels.compactMap { $0 }.sorted().map { Optional($0) }
    }

    private var visible: [ExforDataset] {
        datasets.filter { $0.level == finalState }
    }

    var body: some View {
        let shown = visible
        List {
            header()

            Section {
                ExforChart(series: series(shown), quantity: quantity, frame: frame, unit: workbench.energyUnit,
                           logX: logX, logY: logY)
                    .frame(height: 280)
                    .padding(.vertical, 8)
                if let note = loadingNote(shown) {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
                if shown.contains(where: { if case .failed = tables[$0.id] { true } else { false } }) {
                    Button("Try Again", systemImage: "arrow.clockwise") { attempt += 1 }
                }
            }

            Section {
                if finalStates.count > 1 {
                    Picker("Final state", selection: $finalState.animation(.smooth)) {
                        ForEach(finalStates, id: \.self) { l in
                            Text(Self.finalStateLabel(l, datasets: datasets)).tag(l)
                        }
                    }
                }
                Picker("Quantity", selection: $quantity.animation(.smooth)) {
                    Text("Cross section σ").tag(ExforTable.Quantity.crossSection)
                    Text("S factor").tag(ExforTable.Quantity.sFactor)
                }
                .disabled(entrance == nil)
                Picker("Energy", selection: $frame.animation(.smooth)) {
                    Text("Laboratory").tag(ExforTable.Frame.lab)
                    Text("Centre of mass").tag(ExforTable.Frame.cm)
                }
                .disabled(entrance == nil)
                Toggle("Logarithmic energy axis", isOn: $logX.animation(.smooth))
                Toggle("Logarithmic \(quantity == .sFactor ? "S" : "σ") axis", isOn: $logY.animation(.smooth))
            } header: {
                Text("Display")
            } footer: {
                Text("Tables in EXFOR come as σ or S, at laboratory or c.m. energies; they are converted with the entrance channel (S = σ E exp(2πη), non-relativistic). Measured data include electron screening.")
            }

            Section {
                ForEach(shown) { d in
                    ExforDatasetRow(dataset: d, state: tables[d.id], color: color(for: d, in: shown),
                                    isHidden: hidden.contains(d.id)) {
                        withAnimation(.smooth) {
                            if hidden.contains(d.id) { hidden.remove(d.id) } else { hidden.insert(d.id) }
                        }
                    } destination: {
                        if case .loaded(let t) = tables[d.id] {
                            ExforDatasetView(dataset: d, table: t, target: target, entrance: entrance,
                                             isSetupReaction: isSetupReaction)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("\(shown.count) tables, newest first")
                    Spacer()
                    Button(hidden.isDisjoint(with: shown.map(\.id)) ? "Hide All" : "Show All") {
                        withAnimation(.smooth) {
                            if hidden.isDisjoint(with: shown.map(\.id)) { hidden.formUnion(shown.map(\.id)) }
                            else { hidden.subtract(shown.map(\.id)) }
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            } footer: {
                Text("Tap a colour dot to hide or show a table. EXFOR via IAEA-NDS/exfortables_py, snapshot \(ExforIndex.bundled.date).")
            }
        }
        .groupedList()
        .navigationTitle(title)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .trailingBar) {
                ShareLink(item: CSVFile(name: fileName, text: csv(shown)),
                          preview: SharePreview(title, image: Image(systemName: "tablecells"))) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
            }
        }
        .onChange(of: quantity) { _, q in frame = q == .sFactor ? .cm : .lab }
        .task(id: LoadKey(finalState: finalState, attempt: attempt)) { await load(visible) }
    }

    static func finalStateLabel(_ level: Int?, datasets: [ExforDataset]) -> String {
        let n = datasets.filter { $0.level == level }.count
        let name = switch level {
        case nil: "Total"
        case 0?: "Ground state"
        case let l?: "Level \(l)"
        }
        return "\(name) (\(n))"
    }

    private struct LoadKey: Hashable {
        let finalState: Int?
        let attempt: Int
    }

    /// Loads every table of `ds` that is not loaded yet. A run that SwiftUI cancels (the view disappeared or
    /// the final state changed) writes nothing more; the next run picks up whatever is still missing.
    private func load(_ ds: [ExforDataset]) async {
        let todo = ds.filter { if case .loaded = tables[$0.id] { false } else { true } }
        guard !todo.isEmpty else { return }
        for d in todo { tables[d.id] = .loading }
        await withTaskGroup(of: (String, TableState?).self) { group in
            var next = todo.makeIterator()
            func add() -> Bool {
                guard !Task.isCancelled, let d = next.next() else { return false }
                group.addTask {
                    do { return (d.id, .loaded(try await ExforClient.shared.table(d))) }
                    catch where isCancellation(error) { return (d.id, nil) }
                    catch { return (d.id, .failed(error.localizedDescription)) }
                }
                return true
            }
            for _ in 0..<6 { if !add() { break } }        // at most six downloads at a time
            for await (id, state) in group {
                guard !Task.isCancelled, let state else { continue }
                withAnimation(.smooth) { tables[id] = state }
                _ = add()
            }
        }
    }


    private func loadingNote(_ ds: [ExforDataset]) -> String? {
        let loading = ds.filter { if case .loading = tables[$0.id] { true } else { false } }.count
        let failed = ds.filter { if case .failed = tables[$0.id] { true } else { false } }.count
        let s0 = ds.filter { if case .loaded(let t) = tables[$0.id] { !t.zeroEnergyPoints.isEmpty } else { false } }.count
        var parts: [String] = []
        if loading > 0 { parts.append("Downloading \(loading) of \(ds.count) tables…") }
        if failed > 0 { parts.append("\(failed) could not be loaded.") }
        if s0 > 0 { parts.append("\(s0) \(s0 == 1 ? "table gives" : "tables give") values at E = 0 (extrapolated S(0)), listed in the table but not plotted.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func color(for d: ExforDataset, in ds: [ExforDataset]) -> Color {
        ExforPalette.color(ds.firstIndex(of: d) ?? 0)
    }

    private func series(_ ds: [ExforDataset]) -> [ExforChart.Series] {
        ds.enumerated().compactMap { i, d in
            guard !hidden.contains(d.id), case .loaded(let t) = tables[d.id] else { return nil }
            let pts = entrance.map { t.points(as: quantity, frame: frame, channel: $0) } ?? t.points
            return ExforChart.Series(id: d.id, color: ExforPalette.color(i), upperLimit: t.qualifier == .upperLimit, points: pts)
        }
    }

    private var fileName: String {
        "exfor_" + title.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    private func csv(_ ds: [ExforDataset]) -> String {
        let eName = frame == .cm ? "E_cm_keV" : "E_lab_keV"
        let yName = quantity == .sFactor ? "S_keVb" : "sigma_b"
        var out = "exfor,author,year,final_state,\(eName),d\(eName),\(yName),d\(yName)\n"
        for d in ds where !hidden.contains(d.id) {
            guard case .loaded(let t) = tables[d.id] else { continue }
            let pts = entrance.map { t.points(as: quantity, frame: frame, channel: $0) } ?? t.points
            for p in pts {
                out += [d.exforID, d.author, String(d.year), d.finalStateLabel, Self.g(p.energy),
                        p.energyUncertainty.map(Self.g) ?? "", Self.g(p.value), p.uncertainty.map(Self.g) ?? ""]
                    .map(NotebookEntry.csvField).joined(separator: ",") + "\n"
            }
        }
        return out
    }

    private static func g(_ x: Double) -> String { String(format: "%.6g", x) }
}

extension ExforChannelView where Header == EmptyView {
    init(title: String, target: Nuclide, entrance: ChargedChannel?, datasets: [ExforDataset]) {
        self.init(title: title, target: target, entrance: entrance, datasets: datasets, header: { EmptyView() })
    }
}

enum ExforPalette {
    private static let colors: [Color] = [.orange, .blue, .green, .purple, .red, .teal, .pink, .indigo, .brown, .mint, .cyan, .yellow]
    static func color(_ i: Int) -> Color { colors[i % colors.count] }
}

private struct ExforDatasetRow<Destination: View>: View {
    let dataset: ExforDataset
    let state: TableState?
    let color: Color
    let isHidden: Bool
    let toggle: () -> Void
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isHidden ? "circle" : "circle.fill")
                    .foregroundStyle(color)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isHidden ? "Show \(dataset.author) \(dataset.year)" : "Hide \(dataset.author) \(dataset.year)")

            NavigationLink(destination: destination) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(dataset.author) (\(String(dataset.year)))").font(.body.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .disabled(!isLoaded)
        }
        .opacity(isHidden ? 0.55 : 1)
    }

    private var isLoaded: Bool { if case .loaded = state { true } else { false } }

    private var detail: String {
        var parts = ["EXFOR \(dataset.exforID)"]
        switch state {
        case .loaded(let t)?:
            parts.append("\(t.points.count) points")
            if let a = t.points.first?.energy, let b = t.points.last?.energy {
                parts.append(a == b ? "\(Fmt.keV(a, digits: 4)) keV" : "\(Fmt.keV(a, digits: 3))–\(Fmt.keV(b, digits: 3)) keV")
            }
            if t.quantity == .sFactor { parts.append("S factor") }
            if t.qualifier == .upperLimit { parts.append("DATA-MAX (upper limits)") }
            if t.qualifier == .approximate { parts.append("DATA-APRX (approximate)") }
        case .failed(let e)?:
            parts.append(e)
        case .loading?:
            parts.append("downloading…")
        case nil:
            break
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Chart

struct ExforChart: View {
    struct Series: Identifiable {
        let id: String
        let color: Color
        let upperLimit: Bool
        let points: [ExforTable.Point]
    }

    let series: [Series]
    let quantity: ExforTable.Quantity
    let frame: ExforTable.Frame
    let unit: EnergyUnit
    let logX: Bool
    let logY: Bool

    private struct Mark: Identifiable {
        let id: Int
        let x: Double, y: Double, lo: Double, hi: Double
        let color: Color
        let upper: Bool
    }

    var body: some View {
        let scale = unit == .MeV ? 1e-3 : 1
        var marks: [Mark] = []
        for s in series {
            for p in s.points where p.energy > 0 && (!logY || p.value > 0) {
                let u = p.uncertainty ?? 0
                marks.append(Mark(id: marks.count, x: p.energy * scale, y: p.value,
                                  lo: logY ? max(p.value - u, p.value * 1e-3) : p.value - u, hi: p.value + u,
                                  color: s.color, upper: s.upperLimit))
            }
        }
        let xs = marks.map(\.x), ys = marks.flatMap { [$0.lo, $0.hi] }
        let xLo = xs.min() ?? 1, xHi = max(xs.max() ?? 10, xLo * 1.01)
        let yLo = ys.min() ?? 1e-6, yHi = max(ys.max() ?? 1, yLo * 1.01)
        let xDomain = logX ? (xLo / 1.15)...(xHi * 1.15) : max(0, xLo - 0.05 * (xHi - xLo))...(xHi + 0.05 * (xHi - xLo))
        let yDomain = logY ? (yLo / 1.5)...(yHi * 1.5) : min(0, yLo)...(yHi * 1.08)

        return Group {
            if marks.isEmpty {
                ContentUnavailableView("No points to show", systemImage: "chart.dots.scatter",
                                       description: Text("Tables appear here as they download."))
            } else {
                Chart(marks) { m in
                    if m.hi > m.lo {
                        RuleMark(x: .value("E", m.x), yStart: .value("lo", m.lo), yEnd: .value("hi", m.hi))
                            .foregroundStyle(m.color.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                    PointMark(x: .value("E", m.x), y: .value(quantity == .sFactor ? "S" : "σ", m.y))
                        .foregroundStyle(m.color)
                        .symbol(m.upper ? AnyChartSymbolShape(BasicChartSymbolShape.triangle) : AnyChartSymbolShape(BasicChartSymbolShape.circle))
                        .symbolSize(20)
                }
                .chartXScale(domain: xDomain, type: logX ? .log : .linear)
                .chartYScale(domain: yDomain, type: logY ? .log : .linear)
                .chartXAxis {
                    if logX {
                        AxisMarks(values: logAxisTicks(xDomain)) { v in
                            AxisGridLine(); AxisTick()
                            AxisValueLabel { if let x = v.as(Double.self) { Text(axisNumber(x)) } }
                        }
                    } else {
                        AxisMarks(values: .automatic(desiredCount: 4)) { v in
                            AxisGridLine(); AxisTick()
                            AxisValueLabel { if let x = v.as(Double.self) { Text(axisNumber(x)) } }
                        }
                    }
                }
                .chartYAxis {
                    if logY {
                        AxisMarks(values: sparseDecades(yDomain)) { v in
                            AxisGridLine()
                            AxisValueLabel { if let y = v.as(Double.self) { Text(yLabel(y)) } }
                        }
                    } else {
                        AxisMarks(values: .automatic(desiredCount: 5)) { v in
                            AxisGridLine()
                            AxisValueLabel { if let y = v.as(Double.self) { Text(yLabel(y)) } }
                        }
                    }
                }
                .chartXAxisLabel("\(frame == .cm ? "E (c.m.)" : "E (lab)"), \(unit.label)", alignment: .leading)
                .chartYAxisLabel(quantity == .sFactor ? "S, keV b" : "σ")
                .accessibilityLabel(quantity == .sFactor ? "S factor versus energy" : "Cross section versus energy")
            }
        }
    }

    private func yLabel(_ y: Double) -> String {
        if quantity == .sFactor { return axisNumber(y) }
        let c = Fmt.crossSection(y, digits: 2)
        return c.value + " " + c.unit
    }
}

// MARK: - Dataset detail

struct ExforDatasetView: View {
    let dataset: ExforDataset
    let table: ExforTable
    let target: Nuclide
    let entrance: ChargedChannel?
    let isSetupReaction: Bool

    @Environment(Workbench.self) private var workbench
    @State private var confirmation = 0

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(dataset.author) (\(String(dataset.year)))").font(.title3.weight(.semibold))
                    Text(table.reactionCode).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                ValueRow(label: "EXFOR", value: dataset.exforID)
                ValueRow(label: "Reference", value: table.reference)
                if !table.institute.isEmpty { ValueRow(label: "Institute", value: table.institute) }
                if !table.facility.isEmpty { ValueRow(label: "Facility", value: table.facility) }
                ValueRow(label: "Final state", value: dataset.finalStateLabel,
                         note: table.levelEnergy.flatMap { $0 > 0 ? "Eₓ = \(Fmt.keV($0, digits: 6)) keV" : nil })
                ValueRow(label: "Quantity", value: table.quantity == .sFactor ? "S factor" : "Cross section",
                         note: "Energies \(table.frame == .cm ? "c.m." : "laboratory")")
                if table.qualifier != .value {
                    ValueRow(label: "Values", value: table.qualifier == .upperLimit ? "Upper limits" : "Approximate",
                             note: table.qualifier == .upperLimit ? "EXFOR heading DATA-MAX; see the entry's comments"
                                 : "EXFOR heading DATA-APRX")
                }
                if table.missingValues > 0 {
                    ValueRow(label: "Rows without a value", value: "\(table.missingValues)", note: "NAN in EXFOR; not shown")
                }
                ForEach(Array(table.zeroEnergyPoints.enumerated()), id: \.offset) { _, p in
                    ValueRow(label: table.quantity == .sFactor ? "S(0)" : "Value at E = 0", value: valueText(p),
                             note: "Extrapolation given by the authors; not plotted")
                }
                Link(destination: dataset.exforURL) {
                    Label("Open entry \(dataset.entry) at the IAEA", systemImage: "arrow.up.right.square")
                }
            }

            if isSetupReaction, entrance != nil, table.points.count >= 2 {
                Section {
                    Button {
                        useInRate()
                    } label: {
                        Label("Use as S(E) in Reaction Rate", systemImage: "flame")
                    }
                } footer: {
                    Text("Replaces the S-factor model with these points as a table (S at c.m. energies, interpolated in ln S, constant beyond the ends). The data are used as measured: no fit and no correction for electron screening.")
                }
            }

            Section {
                ForEach(Array(table.points.enumerated()), id: \.offset) { _, p in
                    HStack {
                        Text(Fmt.keV(p.energy, digits: 6) + (p.energyUncertainty.map { " ± " + Fmt.keV($0, digits: 2) } ?? ""))
                        Spacer()
                        Text(valueText(p))
                    }
                    .font(.callout)
                    .monospacedDigit()
                }
            } header: {
                Text("E \(table.frame == .cm ? "(c.m.)" : "(lab)"), keV · \(table.quantity == .sFactor ? "S, keV b" : "σ")")
            } footer: {
                Text("As tabulated in exfortables_py, converted to keV and barn. Uncertainties are those given in EXFOR (often statistical only).")
            }
        }
        .groupedList()
        .navigationTitle("EXFOR \(dataset.exforID)")
        .inlineTitle()
        .sensoryFeedback(.success, trigger: confirmation)
        .toolbar {
            ToolbarItem(placement: .trailingBar) {
                ShareLink(item: CSVFile(name: "exfor_\(dataset.exforID)", text: csv),
                          preview: SharePreview("EXFOR \(dataset.exforID)", image: Image(systemName: "tablecells"))) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func valueText(_ p: ExforTable.Point) -> String {
        if table.quantity == .sFactor {
            return Fmt.significant(p.value, digits: 4) + (p.uncertainty.map { " ± " + Fmt.significant($0, digits: 2) } ?? "")
        }
        let v = Fmt.crossSection(p.value, digits: 4)
        let scale = Self.barnPerUnit[v.unit] ?? 1
        let u = p.uncertainty.map { " ± " + Fmt.significant($0 / scale, digits: 2) } ?? ""
        return "\(v.value)\(u) \(v.unit)"
    }

    /// Units returned by Fmt.crossSection.
    private static let barnPerUnit: [String: Double] = ["b": 1, "mb": 1e-3, "µb": 1e-6, "nb": 1e-9, "pb": 1e-12, "fb": 1e-15]

    private var csv: String {
        let e = table.frame == .cm ? "E_cm_keV" : "E_lab_keV"
        let y = table.quantity == .sFactor ? "S_keVb" : "sigma_b"
        return "# EXFOR \(dataset.exforID) \(table.reactionCode) \(table.reference)\n\(e),d\(e),\(y),d\(y)\n" + table.points.map {
            [String($0.energy), $0.energyUncertainty.map { String($0) } ?? "", String($0.value), $0.uncertainty.map { String($0) } ?? ""]
                .joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }

    private func useInRate() {
        guard let c = entrance else { return }
        let pts = table.points(as: .sFactor, frame: .cm, channel: c)
            .filter { $0.value.isFinite && $0.energy > 0 }
            .map { SFactorModel.Point(energy: $0.energy, s: $0.value) }
        guard pts.count >= 2 else { return }
        workbench.sFactorModel = SFactorModel(kind: .table, s0: workbench.sFactorModel.s0, s1: workbench.sFactorModel.s1,
                                              s2: workbench.sFactorModel.s2, table: pts)
        confirmation += 1
    }
}

// MARK: - Tool: EXFOR data for the current reaction

struct ExforToolView: View {
    @Environment(Workbench.self) private var workbench
    @State private var editingSetup = false
    @State private var datasets: [ExforDataset]?
    @State private var others: [ExforChannelGroup] = []

    var body: some View {
        Group {
            if let r = workbench.reaction {
                if let datasets {
                    if datasets.isEmpty {
                        noData(r)
                    } else {
                        ExforChannelView(title: r.label, target: r.target,
                                         entrance: ChargedChannel.entrance(r).isCharged ? ChargedChannel.entrance(r) : nil,
                                         datasets: datasets, isSetupReaction: true) {
                            Section {
                                ReactionHeader(reaction: r) { editingSetup = true }
                                    .padding(.vertical, 6)
                            }
                        }
                        .id(r)
                    }
                } else {
                    ProgressView("Reading the EXFOR index…")
                }
            } else {
                ContentUnavailableView {
                    Label("No reaction set up", systemImage: "chart.dots.scatter")
                } actions: {
                    Button("Edit Setup") { editingSetup = true }.buttonStyle(.glassProminent)
                }
            }
        }
        .navigationTitle("EXFOR")
        .inlineTitle()
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
        .task(id: workbench.reaction) {
            guard let r = workbench.reaction else { return }
            datasets = nil
            let index = await exforIndex()
            let found = await Task.detached(priority: .userInitiated) { index.datasets(for: r) }.value
            others = found.isEmpty ? await channelGroups(target: r.target) : []
            datasets = found
        }
    }

    private func noData(_ r: Reaction) -> some View {
        List {
            Section {
                ReactionHeader(reaction: r) { editingSetup = true }.padding(.vertical, 6)
            }
            Section {
                ContentUnavailableView("No EXFOR tables for \(r.label)", systemImage: "chart.dots.scatter",
                                       description: Text("EXFOR has no cross-section table for this channel in the bundled index."))
            }
            if !others.isEmpty {
                Section("Other reactions on \(r.target.label)") {
                    ForEach(others) { g in
                        NavigationLink {
                            ExforChannelView(title: "\(r.target.label)\(g.channel.label)", target: r.target,
                                             entrance: g.channel.entranceChannel(target: r.target), datasets: g.datasets)
                        } label: {
                            ExforChannelRow(target: r.target, group: g)
                        }
                    }
                }
            }
        }
        .groupedList()
    }
}

/// Removes downloaded EXFOR tables.
enum ExforCache {
    static func clear() async { await ExforClient.shared.clearCache() }
    static func usage() async -> (bytes: Int, tables: Int) { await ExforClient.shared.cacheUsage() }
}

/// True for the error of a cancelled task or URL request (not a real failure).
nonisolated func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
}

// MARK: - Axis helpers

/// Ticks for a logarithmic axis, at most about six: 1-2-5 or 1-2-3-5-7 steps when the range spans less than
/// two decades (so a narrow range still gets labels), decades otherwise.
func logAxisTicks(_ r: ClosedRange<Double>) -> [Double] {
    guard r.lowerBound > 0, r.upperBound > r.lowerBound else { return [] }
    let span = log10(r.upperBound / r.lowerBound)
    // Keep labels off the trailing edge, where the chart would clip them.
    let inner = r.lowerBound...(r.lowerBound * pow(10, 0.93 * span))
    if span >= 2 { return sparseDecades(inner) }
    let a = Int(floor(log10(r.lowerBound))), b = Int(ceil(log10(r.upperBound)))
    for steps in [[1.0], [1, 2, 5], [1, 2, 3, 5, 7], [1, 1.5, 2, 3, 4, 5, 7]] {
        let t = (a...b).flatMap { e in steps.map { $0 * pow(10, Double(e)) } }.filter { inner.contains($0) }
        if t.count >= 3 || steps.count == 7 { return Array(t.prefix(7)) }
    }
    return []
}

/// Compact axis number: plain between 0.01 and 10⁴ without trailing zeros ("1", "2.5", "300"),
/// powers of ten outside ("10⁵", "2×10⁻³").
func axisNumber(_ x: Double) -> String {
    let a = abs(x)
    if a == 0 || (a >= 0.01 && a < 1e4) {
        return x.formatted(.number.precision(.significantDigits(1...3)).grouping(.never))
    }
    let e = Int(floor(log10(a)))
    let m = x / pow(10, Double(e))
    let exp = "10" + Superscript.string(String(e))
    if abs(m - 1) < 1e-9 { return exp }
    return m.formatted(.number.precision(.significantDigits(1...2))) + "×" + exp
}
