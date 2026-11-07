import Foundation

/// A ground state or isomer from NUBASE2020: half-life, spin and parity, decay modes, abundance.
public struct NuclearState: Hashable, Sendable, Identifiable {
    public let z: Int
    public let a: Int
    /// 0 for the ground state, 1, 2… for isomers and levels in NUBASE order.
    public let state: Int
    /// Excitation energy, keV (0 for the ground state).
    public let excitation: Double
    public let excitationIsEstimated: Bool
    /// Half-life in seconds; `.infinity` when stable, nil when unknown or particle unstable.
    public let halfLife: Double?
    public let halfLifeUncertainty: Double?
    /// NUBASE's half-life as printed, e.g. "5.2714 y", ">2.2 Zy", "stable".
    public let halfLifeText: String
    /// Spin and parity as printed by NUBASE without markers, e.g. "5/2+", "(3/2-)".
    public let spinParity: String
    /// True when NUBASE marks J^π as from systematics (#).
    public let spinParityIsEstimated: Bool
    public let decayModes: [DecayMode]
    /// Natural isotopic abundance, %.
    public let abundance: Double?

    public var id: Int { (z * 1000 + a) * 10 + state }
    public var isGroundState: Bool { state == 0 }
    public var isStable: Bool { halfLife == .infinity }

    /// Label such as "⁶⁰Co" or "⁶⁰ᵐCo".
    public var label: String {
        let sym = Elements.symbol(z: z) ?? "?"
        let mark = state == 0 ? "" : (state == 1 ? "ᵐ" : state == 2 ? "ⁿ" : "ᵐ\(Superscript.digits(state))")
        return z == 0 && a == 1 ? "n" : Superscript.digits(a) + mark + sym
    }

    /// ASCII label such as "60Co" or "166mHo".
    public var plainLabel: String {
        let sym = Elements.symbol(z: z) ?? "?"
        let mark = state == 0 ? "" : (state == 1 ? "m" : state == 2 ? "n" : "m\(state)")
        return "\(a)\(mark)\(sym)"
    }

    /// Decay constant λ = ln 2 / T½, s⁻¹ (0 for stable states).
    public var decayConstant: Double? {
        guard let t = halfLife else { return nil }
        return t == .infinity ? 0 : log(2) / t
    }
}

/// A decay mode with its branching as NUBASE gives it ("B-=100", "EC+B+=3.4 4", "A?").
public struct DecayMode: Hashable, Sendable {
    /// NUBASE code: B-, B+, EC, A, IT, SF, p, n, 2p, B-n…
    public let code: String
    /// Relation and value, e.g. "= 100", "~ 100", "< 0.1", or "?" when only observed.
    public let relation: String
    public let branch: Double?
    public let uncertainty: String?

    public init(raw: String) {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if let r = s.firstIndex(where: { "=<>~?".contains($0) }) {
            code = String(s[..<r])
            let rest = s[r...]
            let rel = String(rest.prefix { "=<>~?".contains($0) })
            relation = rel
            let fields = rest.dropFirst(rel.count).split(separator: " ")
            branch = fields.first.flatMap { Double($0.replacingOccurrences(of: "#", with: "")) }
            uncertainty = fields.count > 1 ? String(fields[1]) : nil
        } else {
            code = s; relation = ""; branch = nil; uncertainty = nil
        }
    }

    /// Typographic name: β⁻, β⁺, ε, α, IT, SF, β⁻n…
    public var name: String {
        var s = code
        for (a, b) in [("B-", "β⁻"), ("B+", "β⁺"), ("EC", "ε"), ("2B", "2β"), ("A", "α")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        return s
    }

    /// "β⁻ 100 %", "ε + β⁺ ≈ 100 %", "α ?".
    public var text: String {
        let rel: String = switch relation {
        case "=": ""
        case "~": "≈ "
        case "<": "< "
        case ">": "> "
        case "?": "?"
        default: relation + " "
        }
        guard let branch else { return "\(name) \(rel)".trimmingCharacters(in: .whitespaces) }
        let v = branch.formatted(.number.precision(.significantDigits(1...6)))
        return "\(name) \(rel)\(v) %"
    }
}

/// NUBASE2020 lookup (Kondev et al., Chin. Phys. C 45, 030001 (2021)).
public final class Nubase: Sendable {
    public let states: [NuclearState]
    private let index: [Int: [NuclearState]]

    init(states: [NuclearState]) {
        self.states = states
        index = Dictionary(grouping: states) { $0.z * 1000 + $0.a }
    }

    public static let nubase2020: Nubase = {
        guard let url = MassTable.resourceURL(name: "nubase2020", ext: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { fatalError("nubase2020.csv missing from NucPhysKit resources") }
        return Nubase(csv: text)
    }()

    /// Ground state and isomers of (Z, A), in NUBASE order.
    public func states(z: Int, a: Int) -> [NuclearState] { index[z * 1000 + a] ?? [] }

    public func groundState(z: Int, a: Int) -> NuclearState? { states(z: z, a: a).first { $0.state == 0 } }

    /// "60Co", "166mHo", "26mAl", "Co-60".
    public func state(named text: String) -> NuclearState? {
        var s = text.trimmingCharacters(in: .whitespaces)
        var level = 0
        // An "m" (or "m2", "n") between the mass number and the symbol marks an isomer.
        if let r = s.range(of: #"^(\d+)(m\d?|n)([A-Za-z]+)$"#, options: .regularExpression), r == s.startIndex..<s.endIndex {
            let digits = s.prefix { $0.isNumber }
            let rest = s.dropFirst(digits.count)
            if rest.hasPrefix("n") && Elements.z(forSymbol: String(rest)) == nil {
                level = 2; s = String(digits) + rest.dropFirst()
            } else if rest.hasPrefix("m") && Elements.z(forSymbol: String(rest)) == nil {
                let tail = rest.dropFirst()
                if let d = tail.first, d.isNumber { level = Int(String(d)) ?? 1; s = String(digits) + tail.dropFirst() }
                else { level = 1; s = String(digits) + tail }
            }
        }
        guard let (z, a) = NuclideNotation.parse(s) else { return nil }
        return states(z: z, a: a).first { $0.state == level }
    }

    convenience init(csv: String) {
        var list: [NuclearState] = []
        list.reserveCapacity(5700)
        for line in csv.split(whereSeparator: \.isNewline).dropFirst() {
            let f = Self.fields(String(line))
            guard f.count >= 11, let z = Int(f[0]), let a = Int(f[1]), let st = Int(f[2]) else { continue }
            let hl: Double? = f[5].isEmpty ? nil : (f[5] == "-1" ? .infinity : Double(f[5]))
            var jpi = f[8].split(separator: " ").first.map(String.init) ?? ""
            let estimated = jpi.contains("#")
            jpi = jpi.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "#", with: "")
            let modes = f[9].isEmpty ? [] : f[9].split(separator: ";").map { DecayMode(raw: String($0)) }
            list.append(NuclearState(
                z: z, a: a, state: st, excitation: Double(f[3]) ?? 0, excitationIsEstimated: f[4] == "1",
                halfLife: hl, halfLifeUncertainty: Double(f[6]), halfLifeText: f[7],
                spinParity: jpi, spinParityIsEstimated: estimated, decayModes: modes,
                abundance: Double(f[10])))
        }
        self.init(states: list)
    }

    /// Splits one CSV line, honouring double quotes.
    static func fields(_ line: String) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        for c in line {
            if c == "\"" { quoted.toggle() } else if c == "," && !quoted { out.append(cur); cur = "" } else { cur.append(c) }
        }
        out.append(cur)
        return out
    }
}

extension Nuclide {
    /// The NUBASE2020 ground state of this nuclide.
    public var nubase: NuclearState? { Nubase.nubase2020.groundState(z: z, a: a) }
}

/// Half-lives in readable units.
public enum HalfLifeFormat {
    public static let year = 365.2422 * 86400.0

    /// Picks y, d, h, min, s, ms, µs, ns, ps, fs, as for a value in seconds.
    public static func unit(for seconds: Double) -> (scale: Double, label: String) {
        let s = abs(seconds)
        let table: [(Double, String)] = [(1e9 * year, "Gy"), (1e6 * year, "My"), (1e3 * year, "ky"), (year, "y"),
                                         (86400, "d"), (3600, "h"), (60, "min"), (1, "s"), (1e-3, "ms"),
                                         (1e-6, "µs"), (1e-9, "ns"), (1e-12, "ps"), (1e-15, "fs"), (1e-18, "as")]
        return table.first { s >= $0.0 } ?? table.last!
    }
}
