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
            .chartYAxisLabel("Expected counts / channel")
            .chartPlotStyle { $0.clipped() }
            .frame(height: expanded ? 420 : 260)
            .accessibilityLabel("Gamma spectrum. Select an energy for channel counts; use range and zoom controls to navigate.")

            if let bin = selectedBin {
                Text("\(Fmt.keV(bin.energy)) keV · \(Fmt.significant(bin.total, digits: 5)) counts/channel")
                    .font(.subheadline.monospacedDigit())
            } else { Text("Touch and drag on the plot to inspect a channel.").font(.caption).foregroundStyle(.secondary) }
            if bins.count > 1200 {
                Text("Overview retains peak extrema; zoom in for channel detail. Readouts, ROI counts and export use all channels.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
            NumberField(title: "View from", value: $lower, unit: "keV", range: 0...max(0, upper - width))
            NumberField(title: "View to", value: $upper, unit: "keV", range: min(maximumEnergy, lower + width)...maximumEnergy)
            Toggle("Logarithmic counts", isOn: $logarithmic)
            if logarithmic { Text("Log display floor: 0.01 counts. Readouts and areas use unmodified counts.").font(.caption).foregroundStyle(.secondary) }
            Toggle("Show response components", isOn: $components)
            DisclosureGroup("Region of interest") {
                NumberField(title: "ROI from", value: $roiLower, unit: "keV", range: 0...maximumEnergy)
                NumberField(title: "ROI to", value: $roiUpper, unit: "keV", range: 0...maximumEnergy)
                Button("Use visible range") { roiLower = lower; roiUpper = upper }
                if roiUpper <= roiLower { Text("ROI upper energy must exceed lower energy.").foregroundStyle(.orange) }
                else {
                    let roi = SpectrumRegion.integrate(bins, binWidth: width, lower: roiLower, upper: roiUpper)
                    ValueRow(label: "Total expected counts", value: Fmt.significant(roi.total, digits: 6))
                    ValueRow(label: "Photopeak component", value: Fmt.significant(roi.photopeak, digits: 6))
                    ValueRow(label: "Compton component", value: Fmt.significant(roi.compton, digits: 6))
                    ValueRow(label: "Background component", value: Fmt.significant(roi.background, digits: 6))
                    Text("Fractional boundary channels are weighted by overlap. These are predicted components, not a measured net-peak extraction.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { resetRange() }
        .onChange(of: maximumEnergy) { _, _ in resetRange() }
        .sheet(isPresented: $fullScreen) {
            NavigationStack {
                ScrollView { AnyView(SpectrumExplorer(bins: bins, maximumEnergy: maximumEnergy, expanded: true)).padding() }
                    .navigationTitle("Explore spectrum")
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
