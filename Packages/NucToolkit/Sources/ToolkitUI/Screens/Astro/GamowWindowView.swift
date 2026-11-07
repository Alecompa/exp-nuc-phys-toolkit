import Charts
import NucPhysKit
import SwiftUI

struct GamowWindowView: View {
    @Environment(Workbench.self) private var workbench
    @State private var editingSetup = false

    var body: some View {
        Group {
            if let r = workbench.reaction, let c = workbench.entranceChannel {
                content(r, c)
            } else {
                NoChargedChannelView(symbol: "sun.max.fill", editingSetup: $editingSetup)
            }
        }
        .navigationTitle("Gamow Window")
        .inlineTitle()
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
    }

    @ViewBuilder
    private func content(_ r: Reaction, _ c: ChargedChannel) -> some View {
        let t9 = workbench.temperatureT9
        let w = c.gamowWindow(t9: t9)
        let rc = c.radius(r0: workbench.channelRadiusR0)

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    ReactionHeader(reaction: r) { editingSetup = true }
                    HeroNumber(value: Fmt.keV(w.peak, digits: 4), unit: "keV",
                               caption: "Gamow peak E₀ at T₉ = \(Fmt.significant(t9, digits: 3))")
                    HStack(spacing: 8) {
                        StatusBadge(text: "\(Fmt.keV(w.lower, digits: 3))–\(Fmt.keV(w.upper, digits: 3)) keV",
                                    symbol: "arrow.left.and.right", tint: .orange)
                        StatusBadge(text: "Lab \(Fmt.keV(c.labEnergy(cm: w.peak), digits: 4)) keV",
                                    symbol: "scope", tint: .teal)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                TemperatureControl()
            } header: {
                Text("Temperature")
            }

            Section {
                GamowIntegrandChart(channel: c, t9: t9)
                    .frame(height: 230)
                    .padding(.vertical, 8)
            } header: {
                Text("Integrand at this temperature")
            } footer: {
                Text("Maxwell–Boltzmann factor × tunnelling probability, exp(−E/kT − √(E_G/E)), normalised to its maximum. Dashed: the Gaussian approximation; band: E₀ ± Δ/2.")
            }

            Section {
                ValueRow(label: "Peak E₀", value: Fmt.keV(w.peak), unit: "keV", note: "Centre of mass")
                ValueRow(label: "Width Δ", value: Fmt.keV(w.width), unit: "keV", note: "1/e full width")
                ValueRow(label: "Window E₀ ± Δ/2", value: "\(Fmt.keV(w.lower, digits: 4))–\(Fmt.keV(w.upper, digits: 4))", unit: "keV")
                ValueRow(label: "Lab window", value: "\(Fmt.keV(c.labEnergy(cm: w.lower), digits: 4))–\(Fmt.keV(c.labEnergy(cm: w.upper), digits: 4))",
                         unit: "keV", note: "Projectile on target at rest")
                ValueRow(label: "τ = 3E₀/kT", value: Fmt.significant(w.tau))
                ValueRow(label: "Sommerfeld η at E₀", value: Fmt.significant(c.sommerfeld(w.peak)))
                ValueRow(label: "exp(−2πη) at E₀", value: Fmt.significant(c.gamowFactor(w.peak), digits: 3))
            } header: {
                Text("Gamow window · \(c.label)")
            }

            Section {
                GamowBandChart(channel: c, t9: t9)
                    .frame(height: 230)
                    .padding(.vertical, 8)
            } header: {
                Text("Window vs temperature")
            } footer: {
                Text("E₀ = (√E_G · kT/2)^⅔ and Δ = 4√(E₀kT/3) assume a constant S factor; resonances and a steep S(E) move the effective window (see Reaction Rate).")
            }

            Section {
                ValueRow(label: "Reduced mass μ", value: Fmt.significant(c.reducedMass, digits: 6), unit: "u")
                ValueRow(label: "Gamow energy E_G", value: Fmt.significant(c.gamowEnergy / 1000, digits: 5), unit: "MeV",
                         note: "exp(−2πη) = exp(−√(E_G/E))")
                ValueRow(label: "Coulomb barrier", value: Fmt.keV(c.coulombBarrier(radius: rc), digits: 4), unit: "keV",
                         note: "At R = \(Fmt.significant(rc, digits: 3)) fm (r₀ = \(Fmt.significant(workbench.channelRadiusR0, digits: 3)) fm)")
                ValueRow(label: "E₀ / barrier", value: Fmt.number(100 * w.peak / c.coulombBarrier(radius: rc), decimals: 2), unit: "%")
            } header: {
                Text("Channel")
            }
        }
        .groupedList()
        .notebookSnapshot {
            var s = NotebookSnapshot(tool: .gamowWindow, title: "\(r.label) at T₉ = \(Fmt.significant(t9, digits: 3))")
            s.add("Window", "Peak E₀", Fmt.keV(w.peak), "keV")
            s.add("Window", "Width Δ", Fmt.keV(w.width), "keV")
            s.add("Window", "E₀ ± Δ/2", "\(Fmt.keV(w.lower, digits: 4))–\(Fmt.keV(w.upper, digits: 4))", "keV")
            s.add("Window", "Lab window", "\(Fmt.keV(c.labEnergy(cm: w.lower), digits: 4))–\(Fmt.keV(c.labEnergy(cm: w.upper), digits: 4))", "keV")
            s.add("Channel", "Sommerfeld η at E₀", Fmt.significant(c.sommerfeld(w.peak)))
            s.add("Channel", "Coulomb barrier", Fmt.keV(c.coulombBarrier(radius: rc), digits: 4), "keV")
            return s
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .animation(.smooth, value: workbench.reactionText)
    }
}

/// The Gamow integrand at one temperature, normalised, with the Gaussian approximation and the window.
private struct GamowIntegrandChart: View {
    let channel: ChargedChannel
    let t9: Double

    private struct Point: Identifiable {
        let id: Int
        let e: Double
        let exact: Double
        let gauss: Double
    }

    var body: some View {
        let w = channel.gamowWindow(t9: t9)
        let hi = w.peak + 2.2 * w.width
        let lo = max(0, w.peak - 1.6 * w.width)
        let peak = channel.gamowIntegrand(w.peak, t9: t9)
        let pts: [Point] = (0...140).map { i in
            let e = lo + (hi - lo) * Double(i) / 140
            let exact = peak > 0 ? channel.gamowIntegrand(e, t9: t9) / peak : 0
            let g = exp(-pow((e - w.peak) / (w.width / 2), 2))
            return Point(id: i, e: e, exact: exact, gauss: g)
        }

        Chart {
            RectangleMark(xStart: .value("E", w.lower), xEnd: .value("E", w.upper))
                .foregroundStyle(.yellow.opacity(0.16))
            ForEach(pts) { p in
                AreaMark(x: .value("E", p.e), y: .value("Integrand", p.exact))
                    .foregroundStyle(.linearGradient(colors: [.orange.opacity(0.45), .orange.opacity(0.05)],
                                                     startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(pts) { p in
                LineMark(x: .value("E", p.e), y: .value("Integrand", p.exact), series: .value("S", "Exact"))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("E", p.e), y: .value("Integrand", p.gauss), series: .value("S", "Gauss"))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .interpolationMethod(.catmullRom)
            }
            RuleMark(x: .value("E₀", w.peak))
                .foregroundStyle(.orange.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .top, alignment: .center, spacing: 2) {
                    Text("E₀").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                }
        }
        .chartXScale(domain: lo...hi)
        .chartYScale(domain: 0...1.12)
        .chartYAxis(.hidden)
        .chartXAxisLabel("E (c.m.), keV", alignment: .leading)
        .accessibilityLabel("Gamow peak at \(Fmt.keV(w.peak, digits: 3)) keV, width \(Fmt.keV(w.width, digits: 3)) keV")
    }
}

/// E₀ and the window E₀ ± Δ/2 as a band over temperature.
private struct GamowBandChart: View {
    let channel: ChargedChannel
    let t9: Double

    private struct Point: Identifiable {
        let id: Int
        let t9: Double
        let lower: Double, peak: Double, upper: Double
    }

    var body: some View {
        let range = TemperatureControl.range
        let a = log10(range.lowerBound), b = log10(range.upperBound)
        let pts: [Point] = (0...80).map { i in
            let t = pow(10, a + (b - a) * Double(i) / 80)
            let w = channel.gamowWindow(t9: t)
            return Point(id: i, t9: t, lower: max(w.lower, 1e-3), peak: w.peak, upper: w.upper)
        }
        let yMin = max(pts.map(\.lower).min() ?? 1, 1e-2)
        let yMax = (pts.map(\.upper).max() ?? 1e4) * 1.2
        let now = channel.gamowWindow(t9: t9)

        Chart {
            ForEach(pts) { p in
                AreaMark(x: .value("T₉", p.t9), yStart: .value("E", p.lower), yEnd: .value("E", p.upper))
                    .foregroundStyle(.yellow.opacity(0.3))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("T₉", p.t9), y: .value("E", p.peak))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            RuleMark(x: .value("T₉", t9))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
            PointMark(x: .value("T₉", t9), y: .value("E", now.peak))
                .symbolSize(70)
                .foregroundStyle(.orange)
        }
        .chartXScale(domain: range, type: .log)
        .chartYScale(domain: yMin...yMax, type: .log)
        .chartXAxis {
            AxisMarks(values: decades(range)) { v in
                AxisGridLine(); AxisTick()
                AxisValueLabel { if let x = v.as(Double.self) { Text(Fmt.significant(x, digits: 1)) } }
            }
        }
        .chartYAxis {
            AxisMarks(values: decades(yMin...yMax)) { v in
                AxisGridLine()
                AxisValueLabel { if let y = v.as(Double.self) { Text(Fmt.significant(y, digits: 1)) } }
            }
        }
        .chartXAxisLabel("T₉ (GK)", alignment: .leading)
        .chartYAxisLabel("keV")
        .accessibilityLabel("Gamow window versus temperature")
    }
}

/// Powers of ten inside a range, for log axes.
func decades(_ r: ClosedRange<Double>) -> [Double] {
    let a = Int(ceil(log10(r.lowerBound) - 1e-9)), b = Int(floor(log10(r.upperBound) + 1e-9))
    guard a <= b else { return [] }
    return (a...b).map { pow(10, Double($0)) }
}
