import Foundation

/// Atomic mass evaluation lookup. `MassTable.ame2020` is loaded lazily from the bundled CSV.
public final class MassTable: Sendable {
    public let name: String
    public let nuclides: [Nuclide]
    private let index: [Int: Nuclide]

    public init(name: String, nuclides: [Nuclide]) {
        self.name = name
        self.nuclides = nuclides
        self.index = Dictionary(nuclides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// AME2020 (Wang et al., Chin. Phys. C 45, 030003, 2021).
    public static let ame2020: MassTable = {
        guard let url = resourceURL(name: "ame2020", ext: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { fatalError("ame2020.csv missing from NucPhysKit resources") }
        return MassTable(name: "AME2020", csv: text)
    }()

    /// Locates a bundled data file: the SwiftPM resource bundle when built as a package,
    /// otherwise the main bundle or `NUCPHYSKIT_RESOURCES` (used by `Tools/test.sh`).
    static func resourceURL(name: String, ext: String) -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: ext) { return url }
        #endif
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        if let dir = ProcessInfo.processInfo.environment["NUCPHYSKIT_RESOURCES"] {
            return URL(fileURLWithPath: dir).appendingPathComponent("\(name).\(ext)")
        }
        return nil
    }

    /// Parses `Z,A,symbol,mass_excess_keV,unc_keV,estimated` rows (header line skipped).
    public convenience init(name: String, csv: String) {
        var list: [Nuclide] = []
        list.reserveCapacity(3600)
        for line in csv.split(whereSeparator: \.isNewline).dropFirst() {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 6, let z = Int(f[0]), let a = Int(f[1]),
                  let dm = Double(f[3]), let du = Double(f[4]) else { continue }
            list.append(Nuclide(z: z, a: a, massExcess: dm, massExcessUncertainty: du, isEstimated: f[5] == "1"))
        }
        self.init(name: name, nuclides: list)
    }

    public func nuclide(z: Int, a: Int) -> Nuclide? { index[z * 1000 + a] }

    /// All tabulated isotopes of an element, ordered by A.
    public func isotopes(z: Int) -> [Nuclide] {
        nuclides.filter { $0.z == z }.sorted { $0.a < $1.a }
    }

    /// Parses notation such as "12C", "C12", "c-12", "3He", "p", "d", "t", "a", "α", "n".
    public func nuclide(named text: String) -> Nuclide? {
        guard let (z, a) = NuclideNotation.parse(text) else { return nil }
        return nuclide(z: z, a: a)
    }
}

public enum NuclideNotation {
    /// Single-letter light-ion names. Matched case-sensitively: "H" (hydrogen), "N" (nitrogen) or "P"
    /// (phosphorus) without a mass number are not silently read as ³He, a neutron or a proton.
    private static let letters: [String: (Int, Int)] = [
        "n": (0, 1), "p": (1, 1), "d": (1, 2), "t": (1, 3), "a": (2, 4), "h": (2, 3), "α": (2, 4),
    ]
    /// Spelled-out names, matched case-insensitively.
    private static let words: [String: (Int, Int)] = [
        "alpha": (2, 4), "proton": (1, 1), "neutron": (0, 1), "deuteron": (1, 2), "triton": (1, 3),
        "helion": (2, 3),
    ]
    private static let superscripts: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
    ]

    /// Returns (Z, A) for a nuclide string, or nil. Photons are not nuclides; see `ReactionParticle`.
    /// Accepts "12C", "C12", "c-12", "¹²C", "p", "α", "alpha", "proton".
    public static func parse(_ raw: String) -> (z: Int, a: Int)? {
        let s = String(raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .map { superscripts[$0] ?? $0 })
        guard !s.isEmpty else { return nil }
        if let alias = letters[s] ?? words[s.lowercased()] { return alias }
        // "12C" style
        let leadingDigits = s.prefix { $0.isNumber }
        if !leadingDigits.isEmpty {
            let sym = String(s.dropFirst(leadingDigits.count))
            guard let a = Int(leadingDigits), let z = Elements.z(forSymbol: sym), a >= max(z, 1) else { return nil }
            return (z, a)
        }
        // "C12" style
        let letters = s.prefix { $0.isLetter }
        let digits = s.dropFirst(letters.count)
        guard !letters.isEmpty, !digits.isEmpty, digits.allSatisfy(\.isNumber),
              let a = Int(digits), let z = Elements.z(forSymbol: String(letters)), a >= max(z, 1) else { return nil }
        return (z, a)
    }
}
