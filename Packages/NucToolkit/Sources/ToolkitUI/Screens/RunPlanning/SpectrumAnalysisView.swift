import Charts
import NucPhysKit
import SwiftUI
import UniformTypeIdentifiers

/// Imports a measured spectrum, finds its peaks, calibrates it against known lines and names the peaks.
struct SpectrumAnalysisView: View {
    @Environment(Workbench.self) private var workbench
    @State private var spectrum: MeasuredSpectrum?
    /// Changes on every import, so a new file with the same name and size is searched again.
    @State private var generation = UUID()
    @State private var importing = false
    @State private var importError: String?

    @AppStorage("analysis.fwhm") private var fwhmChannels = 6.0
    @AppStorage("analysis.threshold") private var threshold = 5.0
    @AppStorage("analysis.sources") private var sourceIDs = "60Co,137Cs,152Eu"
    @AppStorage("analysis.room") private var useRoom = true
    @AppStorage("analysis.setup") private var useSetup = true
    @AppStorage("analysis.quadratic") private var quadratic = false
    @AppStorage("analysis.log") private var logScale = true

    @State private var peaks: [FoundPeak] = []
    @State private var calibration: EnergyCalibration?
    @State private var result: CalibrationResult?
    @State private var calibrationNote: String?
    @State private var zoom: ClosedRange<Double>?
    @State private var selection: Double?

    var body: some View {
        List {
            if let spectrum {
                Section {
                    chart(spectrum)
                    readout(spectrum)
                    HStack {
                        Button { zoomBy(0.5) } label: { Image(systemName: "plus.magnifyingglass") }.accessibilityLabel("Zoom in")
                        Button { zoomBy(2) } label: { Image(systemName: "minus.magnifyingglass") }.accessibilityLabel("Zoom out")
                        Button { pan(-0.5) } label: { Image(systemName: "arrow.left") }.accessibilityLabel("Pan left")
                        Button { pan(0.5) } label: { Image(systemName: "arrow.right") }.accessibilityLabel("Pan right")
                        Button("Reset") { zoom = nil }
                    }
                    .buttonStyle(.bordered)
                    Toggle("Logarithmic counts", isOn: $logScale)
                } header: {
                    Text(spectrum.name)
                } footer: {
                    Text(summary(spectrum))
                }

                Section {
                    NumberField(title: "Peak FWHM (guess)", value: $fwhmChannels, unit: "channels", range: 1...500)
                    NumberField(title: "Threshold", value: $threshold, unit: "σ", range: 2...50)
                    ValueRow(label: "Peaks found", value: "\(peaks.count)")
                } header: { Text("Peak search") } footer: {
                    Text("Second-derivative filter matched to the FWHM (Mariscotti) on the raw counts; areas above a SNIP background. Set the FWHM to the width of a clean peak.")
                }

                calibrationSection(spectrum)
                peakList
            } else {
                Section {
                    ContentUnavailableView {
                        Label("No spectrum", systemImage: "waveform.badge.magnifyingglass")
                    } description: {
                        Text("Import ORTEC .Spe or .Chn, or a text/CSV file with counts, (channel, counts) or (energy, counts).")
                    } actions: {
                        Button("Import Spectrum") { importing = true }.buttonStyle(.glassProminent)
                    }
                }
            }
            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .groupedList()
        .navigationTitle("Spectrum Analysis")
        .inlineTitle()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .trailingBar) {
                Button("Import", systemImage: "square.and.arrow.down") { importing = true }
            }
            if let spectrum, !peaks.isEmpty {
                ToolbarItem(placement: .trailingBar) {
                    ShareLink(item: CSVFile(name: "peaks", text: peaksCSV(spectrum)),
                              preview: SharePreview("Peaks", image: Image(systemName: "tablecells"))) {
                        Label("Export peaks", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .plainText, .commaSeparatedText, .text]) { r in
            load(r)
        }
        .task(id: SearchKey(generation: generation, fwhm: fwhmChannels, threshold: threshold)) {
            guard let counts = spectrum?.counts else { peaks = []; return }
            let (fw, th) = (fwhmChannels, threshold)
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            let found = await Task.detached(priority: .userInitiated) { PeakSearch.find(counts, fwhm: fw, threshold: th) }.value
            guard !Task.isCancelled else { return }
            peaks = found
        }
    }

    private struct SearchKey: Hashable { let generation: UUID; let fwhm: Double; let threshold: Double }

    // MARK: Reference lines

    private var selectedSources: [CalibrationSource] {
        let ids = Set(sourceIDs.split(separator: ",").map(String.init))
        return CalibrationSources.all.filter { ids.contains($0.id) }
    }

    /// Lines used to calibrate: source γ rays, room background, and the setup's in-beam γ rays.
    private var referenceLines: [CalibrationLine] {
        var out = AutoCalibration.lines(sources: selectedSources)
        if useRoom {
            for s in BackgroundLibrary.room where s.id != "511" {
                for l in s.lines(beamEnergy: 0, geometry: GammaGeometry()) {
                    out.append(CalibrationLine(energy: l.restEnergy, weight: 30 * l.intensity, label: s.name))
                }
            }
        }
        if useSetup { out += setupLines.map { CalibrationLine(energy: $0.energy, weight: 20, label: $0.label) } }
        return out
    }

    /// In-beam lines of the current setup: capture primary, residual level, enabled contaminants.
    private var setupLines: [(energy: Double, label: String)] {
        guard let r = workbench.reaction else { return [] }
        let geo = workbench.spectrumSetup.geometry
        var out: [(Double, String)] = []
        if let p = InBeamGamma.primary(r, beamEnergy: workbench.reactionEnergy, finalLevel: workbench.residualExcitation, geometry: geo) {
            out.append((p.meanEnergy, "\(r.label) \(p.label)"))
        }
        if workbench.residualExcitation > 1,
           let l = InBeamGamma.residualLevel(r, beamEnergy: workbench.reactionEnergy, level: workbench.residualExcitation, meanLife: nil, geometry: geo) {
            out.append((l.meanEnergy, l.label))
        }
        for e in workbench.spectrumSetup.backgrounds where e.enabled {
            guard let s = BackgroundLibrary.source(id: e.id), s.notation != nil else { continue }
            for l in s.lines(beamEnergy: workbench.reactionEnergy, geometry: geo) { out.append((l.meanEnergy, l.label)) }
        }
        return out
    }

    /// Everything a peak may be, including single and double escape peaks of lines above 1.5 MeV.
    private var identificationLines: [CalibrationLine] {
        let base = referenceLines + [CalibrationLine(energy: 510.999, weight: 10, label: "Annihilation")]
        let escapes = base.filter { $0.energy > 1500 }.flatMap {
            [CalibrationLine(energy: $0.energy - 510.999, weight: $0.weight / 4, label: "\($0.label) SE"),
             CalibrationLine(energy: $0.energy - 1021.998, weight: $0.weight / 8, label: "\($0.label) DE")]
        }
        return base + escapes
    }

    // MARK: Calibration

    @ViewBuilder
    private func calibrationSection(_ s: MeasuredSpectrum) -> some View {
        Section {
            DisclosureGroup("Calibration sources (\(selectedSources.count))") {
                ForEach(CalibrationSources.all) { src in
                    Toggle(src.label, isOn: Binding(get: { selectedSources.contains(src) }, set: { on in
                        var ids = Set(sourceIDs.split(separator: ",").map(String.init))
                        if on { ids.insert(src.id) } else { ids.remove(src.id) }
                        sourceIDs = ids.sorted().joined(separator: ",")
                    }))
                }
            }
            Toggle("Room background (⁴⁰K, ²⁰⁸Tl, ²¹⁴Bi)", isOn: $useRoom)
            Toggle("In-beam lines of the setup", isOn: $useSetup)
            Toggle("Quadratic (≥ 4 matched lines)", isOn: $quadratic)
            Button("Auto-calibrate", systemImage: "wand.and.stars") { autoCalibrate() }
                .disabled(peaks.count < 2)
            if let c = s.fileCalibration {
                Button("Use the file's calibration") { calibration = c; result = nil; calibrationNote = "From the file." }
            }
            if let note = calibrationNote { Text(note).font(.footnote).foregroundStyle(.secondary) }
            if let calibration {
                ValueRow(label: "Gain", value: Fmt.significant(calibration.gain, digits: 6), unit: "keV/ch")
                ValueRow(label: "Offset", value: Fmt.significant(calibration.energy(channel: 0), digits: 5), unit: "keV")
                if calibration.coefficients.count > 2 {
                    ValueRow(label: "Quadratic", value: Fmt.significant(calibration.coefficients[2], digits: 3), unit: "keV/ch²")
                }
                Button("Remove calibration", role: .destructive) { self.calibration = nil; result = nil; calibrationNote = nil }
            }
            if let result {
                ValueRow(label: "Matched lines", value: "\(result.matches.count)", note: "RMS residual \(Fmt.significant(result.rms, digits: 2)) keV")
                ForEach(result.matches) { m in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Fmt.keV(m.line.energy, digits: 6)) keV").monospacedDigit()
                            Text(m.line.label).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("ch \(Fmt.number(m.peak.centroid, decimals: 2))").monospacedDigit()
                            Text("\(m.residual >= 0 ? "+" : "")\(Fmt.significant(m.residual, digits: 2)) keV").font(.caption).monospacedDigit()
                                .foregroundStyle(abs(m.residual) > 1 ? .orange : .secondary)
                        }
                    }
                }
            }
        } header: { Text("Energy calibration") } footer: {
            Text("Every pair of strong peaks is tried against every pair of reference lines; the gain and offset that place the most (intensity-weighted) lines on peaks win, then a weighted least-squares fit refines them. Check the residuals: a wrong source selection gives a confident wrong answer.")
        }
    }

    private func autoCalibrate() {
        let lines = referenceLines
        guard lines.count >= 2 else { calibrationNote = "Select at least one source or line set."; return }
        if let r = AutoCalibration.calibrate(peaks: peaks, lines: lines, quadratic: quadratic) {
            result = r; calibration = r.calibration
            calibrationNote = nil
        } else {
            calibrationNote = "No consistent gain found. Check the FWHM guess and the selected sources."
        }
    }

    // MARK: Peaks

    private var peakList: some View {
        Section {
            ForEach(peaks) { p in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let c = calibration {
                            Text("\(Fmt.keV(c.energy(channel: p.centroid), digits: 6)) keV").monospacedDigit()
                        }
                        Text("ch \(Fmt.number(p.centroid, decimals: 2)) ± \(Fmt.significant(p.centroidUncertainty, digits: 1))")
                            .font(calibration == nil ? .body : .caption).monospacedDigit()
                            .foregroundStyle(calibration == nil ? .primary : .secondary)
                        if let id = identify(p) { Text(id).font(.caption).foregroundStyle(Color.accent) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Fmt.significant(p.area, digits: 4)) ± \(Fmt.significant(p.areaUncertainty, digits: 2))").monospacedDigit()
                        Text("FWHM \(Fmt.significant(fwhmText(p), digits: 3)) \(calibration == nil ? "ch" : "keV")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { zoomTo(p) }
            }
        } header: { Text("Peaks") } footer: {
            Text("Tap a peak to zoom to it. Areas are net counts within ±1.5 FWHM above the SNIP background (no fit); use them for orientation, not for a final yield.")
        }
    }

    private func fwhmText(_ p: FoundPeak) -> Double { calibration.map { p.fwhm * $0.gain } ?? p.fwhm }

    /// Nearest reference line within 1.5 FWHM (and 1 keV), or nil.
    private func identify(_ p: FoundPeak) -> String? {
        guard let c = calibration else { return nil }
        let e = c.energy(channel: p.centroid)
        let tol = max(1, 1.5 * p.fwhm * c.gain)
        let hits = identificationLines.filter { abs($0.energy - e) <= tol }.sorted { abs($0.energy - e) < abs($1.energy - e) }
        guard let best = hits.first else { return nil }
        let more = hits.count > 1 ? " (+\(hits.count - 1) more)" : ""
        return "\(best.label) \(Fmt.keV(best.energy, digits: 6)) keV\(more)"
    }

    // MARK: Chart

    private func x(_ ch: Double) -> Double { calibration?.energy(channel: ch) ?? ch }

    /// Axis range of the whole spectrum; ordered even for a calibration with negative gain.
    private func fullRange(_ s: MeasuredSpectrum) -> ClosedRange<Double> {
        let a = x(0), b = x(Double(max(1, s.counts.count - 1)))
        return a == b ? a...(a + 1) : min(a, b)...max(a, b)
    }

    private func chart(_ s: MeasuredSpectrum) -> some View {
        let full = fullRange(s)
        let domain = zoom ?? full
        let pts = envelope(s.counts, domain: domain)
        let shownPeaks = peaks.filter { domain.contains(x($0.centroid)) }
        return Chart {
            ForEach(pts, id: \.0) { p in
                LineMark(x: .value("x", p.1), y: .value("Counts", logScale ? max(0.5, p.2) : p.2))
                    .interpolationMethod(.stepCenter)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(shownPeaks) { p in
                let i = min(s.counts.count - 1, max(0, Int(p.centroid.rounded())))
                PointMark(x: .value("x", x(p.centroid)), y: .value("Counts", max(1, s.counts[i]) * (logScale ? 1.6 : 1.05)))
                    .symbol(.triangle).symbolSize(28).foregroundStyle(Color.accent)
            }
            if let selection, domain.contains(selection) {
                RuleMark(x: .value("x", selection)).foregroundStyle(.secondary)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(type: logScale ? .log : .linear)
        .chartXSelection(value: $selection)
        .chartPlotStyle { $0.clipped() }
        .chartXAxisLabel(calibration == nil ? "Channel" : "Energy (keV)")
        .chartYAxisLabel("Counts")
        .frame(height: 280)
        .accessibilityLabel("Measured spectrum")
    }

    private func readout(_ s: MeasuredSpectrum) -> some View {
        let text: String = {
            guard let selection else { return "Drag on the plot to read a channel" }
            let ch: Double = calibration.map { $0.channel(energy: selection) } ?? selection
            let i = min(s.counts.count - 1, max(0, Int(ch.rounded())))
            let pos = calibration == nil ? "ch \(i)" : "\(Fmt.keV(selection, digits: 6)) keV (ch \(i))"
            return "\(pos) · \(Fmt.significant(s.counts[i], digits: 6)) counts"
        }()
        return Text(text).font(.caption.monospacedDigit()).foregroundStyle(selection == nil ? .secondary : .primary)
    }

    /// Min/max per bucket so narrow peaks survive at any zoom; (index, x, counts).
    private func envelope(_ counts: [Double], domain: ClosedRange<Double>, budget: Int = 1400) -> [(Int, Double, Double)] {
        let c1 = calibration?.channel(energy: domain.lowerBound) ?? domain.lowerBound
        let c2 = calibration?.channel(energy: domain.upperBound) ?? domain.upperBound
        guard c1.isFinite, c2.isFinite else { return [] }
        let lo = max(0, Int(floor(min(c1, c2)))), hi = min(counts.count - 1, Int(ceil(max(c1, c2))))
        guard hi > lo else { return [] }
        let n = hi - lo + 1
        if n <= budget { return (lo...hi).map { ($0, x(Double($0)), counts[$0]) } }
        let size = Int(ceil(Double(n) / Double(budget / 2)))
        var out: [(Int, Double, Double)] = []
        for start in stride(from: lo, through: hi, by: size) {
            let end = min(hi, start + size - 1)
            var a = start, b = start
            for i in start...end {
                if counts[i] < counts[a] { a = i }
                if counts[i] > counts[b] { b = i }
            }
            for i in [a, b].sorted() where out.last?.0 != i { out.append((i, x(Double(i)), counts[i])) }
        }
        return out
    }

    private func zoomBy(_ f: Double) {
        guard let s = spectrum else { return }
        let full = fullRange(s)
        let d = zoom ?? full
        let centre = selection ?? (d.lowerBound + d.upperBound) / 2
        let span = min(full.upperBound - full.lowerBound, max(10 * (calibration?.gain ?? 1), (d.upperBound - d.lowerBound) * f))
        let lo = min(max(full.lowerBound, centre - span / 2), full.upperBound - span)
        zoom = span >= full.upperBound - full.lowerBound ? nil : lo...(lo + span)
    }

    private func pan(_ f: Double) {
        guard let s = spectrum, let d = zoom else { return }
        let full = fullRange(s)
        let span = d.upperBound - d.lowerBound
        let lo = min(max(full.lowerBound, d.lowerBound + f * span), full.upperBound - span)
        zoom = lo...(lo + span)
    }

    private func zoomTo(_ p: FoundPeak) {
        let half = 8 * p.fwhm * (calibration?.gain ?? 1)
        let c = x(p.centroid)
        withAnimation(.smooth) { zoom = (c - half)...(c + half); selection = c }
    }

    // MARK: Import and export

    private func load(_ r: Result<URL, Error>) {
        importError = nil
        do {
            let url = try r.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let s = try MeasuredSpectrum.read(data, name: url.lastPathComponent)
            spectrum = s
            generation = UUID()
            peaks = []
            calibration = s.fileCalibration
            calibrationNote = s.fileCalibration == nil ? nil : "Calibration read from the file."
            result = nil; zoom = nil; selection = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func summary(_ s: MeasuredSpectrum) -> String {
        var parts = ["\(s.counts.count) channels", "\(Fmt.significant(s.counts.reduce(0, +), digits: 4)) counts"]
        if let l = s.liveTime { parts.append("live \(Fmt.significant(l, digits: 5)) s") }
        if let r = s.realTime, let l = s.liveTime, r > 0 { parts.append("dead time \(Fmt.significant(100 * (1 - l / r), digits: 2)) %") }
        return parts.joined(separator: " · ")
    }

    private func peaksCSV(_ s: MeasuredSpectrum) -> String {
        var out = "# \(s.name)\nchannel,d_channel,energy_keV,fwhm_ch,area,d_area,significance,identification\n"
        for p in peaks {
            let e = calibration.map { String(format: "%.3f", $0.energy(channel: p.centroid)) } ?? ""
            out += [String(format: "%.3f", p.centroid), String(format: "%.3f", p.centroidUncertainty), e,
                    String(format: "%.2f", p.fwhm), String(format: "%.1f", p.area), String(format: "%.1f", p.areaUncertainty),
                    String(format: "%.1f", p.significance), identify(p) ?? ""].map(NotebookEntry.csvField).joined(separator: ",") + "\n"
        }
        return out
    }
}
