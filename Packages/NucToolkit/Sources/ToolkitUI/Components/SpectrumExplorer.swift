import Charts
import NucPhysKit
import SwiftUI

struct SpectrumExplorer: View {
    let bins: [SpectrumBin]
    let maximumEnergy: Double
    var expanded = false
    @State private var lower = 0.0
    @State private var upper = 3000.0
    @State private var selection: Double?
    @State private var logarithmic = false
    @State private var components = true
    @State private var fullScreen = false
    @State private var roiLower = 0.0
    @State private var roiUpper = 3000.0
    private var width: Double { maximumEnergy / Double(max(1, bins.count)) }
    private var domain: ClosedRange<Double> { max(0, lower)...max(max(0, lower) + width, upper) }
    private var visible: [SpectrumBin] {
        SpectrumPlotSampling.envelope(bins.filter { $0.energy >= domain.lowerBound - width && $0.energy <= domain.upperBound + width })
    }
    private var selectedBin: SpectrumBin? {
        guard let selection, selection >= 0, selection <= maximumEnergy, !bins.isEmpty else { return nil }
        return bins[min(bins.count - 1, max(0, Int(selection / width)))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach(visible) { bin in
                    LineMark(x: .value("Energy", bin.energy), y: .value("Counts", plotted(bin.total)))
                        .foregroundStyle(by: .value("Component", "Total"))
                    if components {
                        LineMark(x: .value("Energy", bin.energy), y: .value("Counts", plotted(bin.photopeak)))
                            .foregroundStyle(by: .value("Component", "Photopeaks"))
                        LineMark(x: .value("Energy", bin.energy), y: .value("Counts", plotted(bin.compton)))
                            .foregroundStyle(by: .value("Component", "Compton"))
                    }
                }
                if let bin = selectedBin, domain.contains(bin.energy) {
                    RuleMark(x: .value("Selected energy", bin.energy)).foregroundStyle(.secondary)
                }
                RuleMark(x: .value("ROI lower", roiLower)).lineStyle(.init(dash: [3, 3])).foregroundStyle(.gray.opacity(0.6))
                RuleMark(x: .value("ROI upper", roiUpper)).lineStyle(.init(dash: [3, 3])).foregroundStyle(.gray.opacity(0.6))
            }
            .chartXScale(domain: domain)
            .chartYScale(type: logarithmic ? .log : .linear)
            .chartXSelection(value: $selection)
            .chartXAxisLabel("Energy (keV)")
            .chartYAxisLabel("Counts / channel")
            .chartPlotStyle { $0.clipped() }
            .frame(height: expanded ? 420 : 260)
            .accessibilityLabel("Gamma spectrum")

            Text(selectedBin.map { "\(Fmt.keV($0.energy)) keV · \(Fmt.significant($0.total, digits: 5)) counts" } ?? "Drag on the plot to read a channel")
                .font(.caption.monospacedDigit())
                .foregroundStyle(selectedBin == nil ? .secondary : .primary)
            HStack {
                Button { move(-0.5) } label: { Image(systemName: "arrow.left") }.accessibilityLabel("Pan to lower energy")
                Button { zoom(0.5) } label: { Image(systemName: "plus.magnifyingglass") }.accessibilityLabel("Zoom in")
                Button { zoom(2) } label: { Image(systemName: "minus.magnifyingglass") }.accessibilityLabel("Zoom out")
                Button { move(0.5) } label: { Image(systemName: "arrow.right") }.accessibilityLabel("Pan to higher energy")
                Button("Reset") { lower = 0; upper = maximumEnergy; selection = nil }
                if !expanded {
                    Button { fullScreen = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.accessibilityLabel("Expand spectrum")
                }
            }.buttonStyle(.bordered)
            Toggle("Log scale", isOn: $logarithmic)
            Toggle("Components", isOn: $components)
            DisclosureGroup("View range") {
                NumberField(title: "From", value: $lower, unit: "keV", range: 0...max(0, upper - width))
                NumberField(title: "To", value: $upper, unit: "keV", range: min(maximumEnergy, lower + width)...maximumEnergy)
            }
            DisclosureGroup("Region of interest") {
                NumberField(title: "ROI from", value: $roiLower, unit: "keV", range: 0...maximumEnergy)
                NumberField(title: "ROI to", value: $roiUpper, unit: "keV", range: 0...maximumEnergy)
                Button("Use visible range") { roiLower = lower; roiUpper = upper }
                if roiUpper <= roiLower { Text("Upper limit must exceed the lower one.").foregroundStyle(.orange) }
                else {
                    let roi = SpectrumRegion.integrate(bins, binWidth: width, lower: roiLower, upper: roiUpper)
                    ValueRow(label: "Total", value: Fmt.significant(roi.total, digits: 6))
                    ValueRow(label: "Photopeak", value: Fmt.significant(roi.photopeak, digits: 6))
                    ValueRow(label: "Compton", value: Fmt.significant(roi.compton, digits: 6))
                    ValueRow(label: "Background", value: Fmt.significant(roi.background, digits: 6))
                }
            }
        }
        .onAppear { resetRange() }
        .onChange(of: maximumEnergy) { _, _ in resetRange() }
        .sheet(isPresented: $fullScreen) {
            NavigationStack {
                ScrollView { AnyView(SpectrumExplorer(bins: bins, maximumEnergy: maximumEnergy, expanded: true)).padding() }
                    .navigationTitle("Spectrum")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { fullScreen = false } } }
            }
        }
    }
    private func plotted(_ value: Double) -> Double { logarithmic ? max(0.01, value) : value }
    private func resetRange() { lower = 0; upper = maximumEnergy; roiLower = 0; roiUpper = maximumEnergy; selection = nil }
    private func setWindow(center: Double, span: Double) {
        let span = min(maximumEnergy, max(width * 8, span))
        lower = min(max(0, center - span / 2), maximumEnergy - span)
        upper = lower + span
    }
    private func zoom(_ factor: Double) { setWindow(center: selection ?? (lower + upper) / 2, span: (upper - lower) * factor) }
    private func move(_ fraction: Double) { setWindow(center: (lower + upper) / 2 + fraction * (upper - lower), span: upper - lower) }
}
