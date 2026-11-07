import Foundation
import NucPhysKit

/// Number formatting tuned for physics results: digits follow the uncertainty,
/// thin grouping, and units always attached.
enum Fmt {
    /// Decimals that show an uncertainty with two significant digits (clamped to 0…6).
    static func decimals(forUncertainty u: Double, fallback: Int = 3) -> Int {
        guard u > 0, u.isFinite else { return fallback }
        let d = 1 - Int(floor(log10(u)))
        return min(6, max(0, d))
    }

    static func number(_ x: Double, decimals: Int) -> String {
        guard x.isFinite else { return "—" }
        // Typographic minus (U+2212) so signs align with digits.
        return x.formatted(.number.precision(.fractionLength(decimals)).grouping(.never))
            .replacingOccurrences(of: "-", with: "\u{2212}")
    }

    /// Value in the chosen energy unit, with decimals chosen from the uncertainty when given.
    static func energy(_ keV: Double, unit: EnergyUnit, uncertainty: Double? = nil, decimals: Int? = nil) -> String {
        let v = keV / unit.scale
        let d = decimals ?? uncertainty.map { Self.decimals(forUncertainty: $0 / unit.scale) } ?? (unit == .keV ? 2 : 4)
        return number(v, decimals: d)
    }

    static func uncertainty(_ keV: Double, unit: EnergyUnit) -> String {
        let u = keV / unit.scale
        return number(u, decimals: decimals(forUncertainty: u))
    }

    /// `digits` significant figures; powers of ten written out (1.23×10⁻⁴) outside 10⁻³…10⁶.
    static func significant(_ x: Double, digits: Int = 4) -> String {
        guard x.isFinite else { return "—" }
        if x == 0 { return "0" }
        let ax = abs(x)
        if ax < 1e-3 || ax >= 1e6 {
            let e = Int(floor(log10(ax)))
            let m = x / pow(10, Double(e))
            return number(m, decimals: max(0, digits - 1)) + "×10" + superscript(e)
        }
        return x.formatted(.number.precision(.significantDigits(digits)).grouping(.never))
            .replacingOccurrences(of: "-", with: "\u{2212}")
    }

    static func superscript(_ n: Int) -> String {
        let map: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵",
                                           "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(n).map { map[$0] ?? $0 })
    }

    /// A length in Å shown in the most readable unit (Å, nm, µm, mm, m).
    static func length(_ angstrom: Double, digits: Int = 4) -> (value: String, unit: String) {
        let a = abs(angstrom)
        let (scale, unit): (Double, String) =
            a < 10 ? (1, "Å") : a < 1e4 ? (10, "nm") : a < 1e7 ? (1e4, "µm") : a < 1e10 ? (1e7, "mm") : (1e10, "m")
        return (significant(angstrom / scale, digits: digits), unit)
    }

    static func angle(_ radians: Double, decimals: Int = 2) -> String {
        number(radians * 180 / .pi, decimals: decimals) + "°"
    }

    /// A duration in seconds in the most readable unit (s, min, h, d, y).
    static func duration(_ seconds: Double, digits: Int = 3) -> (value: String, unit: String) {
        guard seconds.isFinite else { return ("∞", "") }
        let s = abs(seconds)
        let (scale, unit): (Double, String) =
            s < 120 ? (1, "s") : s < 7200 ? (60, "min") : s < 3 * 86400 ? (3600, "h") : s < 2 * HalfLifeFormat.year ? (86400, "d") : (HalfLifeFormat.year, "y")
        return (significant(seconds / scale, digits: digits), unit)
    }

    /// A half-life in seconds with its natural unit (fs … Gy); "stable" for infinity.
    static func halfLife(_ seconds: Double?, digits: Int = 5) -> String {
        guard let seconds else { return "—" }
        if seconds == .infinity { return "stable" }
        let u = HalfLifeFormat.unit(for: seconds)
        return "\(significant(seconds / u.scale, digits: digits)) \(u.label)"
    }

    /// An activity in Bq shown in Bq, kBq, MBq, GBq or TBq.
    static func activity(_ bq: Double, digits: Int = 4) -> (value: String, unit: String) {
        let a = abs(bq)
        let (scale, unit): (Double, String) = a < 1e3 ? (1, "Bq") : a < 1e6 ? (1e3, "kBq") : a < 1e9 ? (1e6, "MBq") : a < 1e12 ? (1e9, "GBq") : (1e12, "TBq")
        return (significant(bq / scale, digits: digits), unit)
    }
}

/// Activity units for entry.
enum ActivityUnit: String, CaseIterable, Identifiable {
    case Bq, kBq, MBq, GBq, nCi = "nCi", µCi = "µCi", mCi = "mCi"
    var id: String { rawValue }
    /// Bq per unit.
    var scale: Double {
        switch self {
        case .Bq: 1
        case .kBq: 1e3
        case .MBq: 1e6
        case .GBq: 1e9
        case .nCi: 37
        case .µCi: 3.7e4
        case .mCi: 3.7e7
        }
    }
}

/// Time units for entry.
enum TimeUnit: String, CaseIterable, Identifiable {
    case s, min, h, d, y
    var id: String { rawValue }
    var scale: Double {
        switch self {
        case .s: 1
        case .min: 60
        case .h: 3600
        case .d: 86400
        case .y: HalfLifeFormat.year
        }
    }
}
