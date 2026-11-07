import NucPhysKit
import SwiftUI

extension Fmt {
    /// A cross section in barn shown in the most readable unit (b, mb, µb, nb, pb, fb).
    static func crossSection(_ barn: Double, digits: Int = 4) -> (value: String, unit: String) {
        let a = abs(barn)
        let units: [(Double, String)] = [(1, "b"), (1e-3, "mb"), (1e-6, "µb"), (1e-9, "nb"), (1e-12, "pb"), (1e-15, "fb")]
        let (scale, unit) = units.first { a >= $0.0 } ?? units.last!
        return (significant(barn / scale, digits: digits), unit)
    }

    /// keV with up to `digits` significant figures.
    static func keV(_ x: Double, digits: Int = 5) -> String { significant(x, digits: digits) }
}

/// Stellar temperatures worth a tap.
enum StellarSite: String, CaseIterable, Identifiable {
    case sun, cno, bbn, agb, novae, carbon, xrb
    var id: String { rawValue }
    var t9: Double {
        switch self {
        case .sun: 0.0157
        case .cno: 0.03
        case .agb: 0.1
        case .novae: 0.3
        case .bbn: 0.6
        case .carbon: 0.9
        case .xrb: 1.5
        }
    }
    var title: String {
        switch self {
        case .sun: "Solar core"
        case .cno: "Massive-star H burning"
        case .agb: "Red giant / AGB He burning"
        case .novae: "Classical novae"
        case .bbn: "Big Bang nucleosynthesis"
        case .carbon: "Core carbon burning"
        case .xrb: "X-ray bursts"
        }
    }
}

/// Temperature entry (GK) with a logarithmic slider and stellar-site presets, bound to the Workbench.
struct TemperatureControl: View {
    @Environment(Workbench.self) private var workbench
    static let range = 0.001...10.0

    var body: some View {
        @Bindable var workbench = workbench
        NumberField(title: "Temperature T₉", value: $workbench.temperatureT9, unit: "GK", range: Self.range)
        HStack(spacing: 12) {
            Slider(value: Binding(get: { log10(workbench.temperatureT9) },
                                  set: { workbench.temperatureT9 = Self.rounded(pow(10, $0)) }),
                   in: log10(Self.range.lowerBound)...log10(Self.range.upperBound)) {
                Text("Temperature")
            } minimumValueLabel: {
                Text("0.001").font(.caption2).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("10").font(.caption2).foregroundStyle(.secondary)
            }
            Menu {
                ForEach(StellarSite.allCases) { site in
                    Button {
                        withAnimation(.smooth) { workbench.temperatureT9 = site.t9 }
                    } label: {
                        Text(site.title)
                        Text("T₉ = \(Fmt.significant(site.t9, digits: 3))")
                    }
                }
            } label: {
                Image(systemName: "star.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("Stellar sites")
        }
        LabeledContent("kT") {
            Text("\(Fmt.keV(ChargedChannel.kT(workbench.temperatureT9), digits: 4)) keV")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// Three significant figures, so slider values read cleanly.
    static func rounded(_ x: Double) -> Double {
        let e = floor(log10(x)) - 2
        return (x / pow(10, e)).rounded() * pow(10, e)
    }
}

/// Placeholder when the current reaction has no charged entrance channel.
struct NoChargedChannelView: View {
    let symbol: String
    @Binding var editingSetup: Bool

    var body: some View {
        ContentUnavailableView {
            Label("No charged-particle channel", systemImage: symbol)
        } description: {
            Text("The astrophysics tools use the entrance channel of the current reaction, and both the projectile and the target must be charged.")
        } actions: {
            Button("Edit Setup") { editingSetup = true }.buttonStyle(.glassProminent)
        }
    }
}

/// Numeric field for very small or large values: accepts 1e-6, 1.5E3, 1.5×10⁻³ and shows the value
/// in scientific notation outside 10⁻³…10⁶.
struct ScientificTextField: View {
    let title: String
    @Binding var value: Double
    var allowsNegative = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .scientificKeyboard()
            .focused($focused)
            .onAppear { text = Self.format(value) }
            .onChange(of: value) { if !focused { text = Self.format(value) } }
            .onChange(of: text) {
                if let v = Self.parse(text), allowsNegative || v >= 0 { value = v }
            }
            .onChange(of: focused) { if !focused { text = Self.format(value) } }
    }

    static func format(_ x: Double) -> String {
        guard x.isFinite else { return "" }
        if x != 0, abs(x) < 1e-3 || abs(x) >= 1e6 { return String(format: "%.4g", x).replacingOccurrences(of: "e-0", with: "e-").replacingOccurrences(of: "e+0", with: "e").replacingOccurrences(of: "e+", with: "e") }
        return x.formatted(.number.precision(.significantDigits(1...7)).grouping(.never))
    }

    static func parse(_ s: String) -> Double? {
        let superscripts: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5",
                                                     "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-"]
        var t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "\u{2212}", with: "-")
        if let r = t.range(of: "×10") ?? t.range(of: "x10") ?? t.range(of: "*10^") {
            let exp = String(t[r.upperBound...].map { superscripts[$0] ?? $0 }).replacingOccurrences(of: "^", with: "")
            t = String(t[..<r.lowerBound]) + "e" + exp
        }
        return Double(t)
    }
}

/// Labelled row around a `ScientificTextField`.
struct ScientificField: View {
    let title: String
    @Binding var value: Double
    var unit: String? = nil
    var note: String? = nil

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                ScientificTextField(title: title, value: $value)
                if let unit { Text(unit).foregroundStyle(.secondary) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Tick labels for log axes: powers of ten as 10ⁿ.
struct PowerOfTenLabel: View {
    let value: Double
    var body: some View {
        let e = log10(value)
        if abs(e - e.rounded()) < 1e-6 {
            Text(Int(e.rounded()) == 0 ? "1" : "10" + Fmt.superscript(Int(e.rounded())))
        } else {
            Text(Fmt.significant(value, digits: 2))
        }
    }
}
