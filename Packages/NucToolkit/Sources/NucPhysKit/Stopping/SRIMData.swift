import Foundation

/// Per-element coefficients of SRIM-2013 (`SCOEF03.DAT`), Z = 1…92.
///
/// Column layout as recovered by LunaSRIM (github.com/skowrons94/LunaSRIM) from the SR module:
/// 3 most-abundant-isotope mass, 4 natural atomic weight, 5 solid density, 9 gas density,
/// 11–20 proton fit, 21–30 helium fit, 31–40 lithium fit, 41–53 heavy-ion polynomial (ion),
/// 54–66 heavy-ion polynomial (target), 67 I (solid), 68–69 I (gas: protons, other ions),
/// 70–80 and 81–88 shell corrections, 89–93 high-energy effective-charge parameters.
public struct SRIMElement: Sendable {
    public let z: Int
    public let symbol: String
    /// Mass of the most abundant isotope, u (SRIM's default ion mass).
    public let isotopeMass: Double
    /// Isotope-averaged atomic weight, u (SRIM's default target mass).
    public let naturalMass: Double
    /// Density of the solid, g/cm³.
    public let density: Double
    /// Density of the gas at STP, g/cm³.
    public let gasDensity: Double
    let proton: [Double]
    let helium: [Double]
    let lithium: [Double]
    let ionPolynomial: [Double]
    let targetPolynomial: [Double]
    let meanExcitationSolid: Double
    let meanExcitationGas: [Double]
    let shellC: [Double]
    let shellD: [Double]
    let highEnergyCharge: [Double]

    init(z: Int, symbol: String, columns c: [Double]) {
        // c[0] is column 2 of SCOEF03.DAT
        func col(_ k: Int) -> Double { c[k - 2] }
        func cols(_ r: ClosedRange<Int>) -> [Double] { Array(c[(r.lowerBound - 2)...(r.upperBound - 2)]) }
        self.z = z
        self.symbol = symbol
        isotopeMass = col(3)
        naturalMass = col(4)
        density = col(5)
        gasDensity = col(9)
        proton = cols(11...20)
        helium = cols(21...30)
        lithium = cols(31...40)
        ionPolynomial = cols(41...53)
        targetPolynomial = cols(54...66)
        meanExcitationSolid = col(67)
        meanExcitationGas = cols(68...69)
        shellC = cols(70...80)
        shellD = cols(81...88)
        highEnergyCharge = cols(89...93)
    }
}

/// An entry of SRIM's compound dictionary (`Compound.dat`).
public struct SRIMCompound: Sendable, Hashable, Identifiable, Codable {
    public let category: String
    public let title: String
    public let name: String
    /// g/cm³
    public let density: Double
    public let gas: Bool
    /// (Z, atom fraction), fractions normalised to 1.
    public let elements: [[Double]]

    public var id: String { category + "/" + name }

    /// Name without SRIM's underscores, e.g. "Water Liquid (ICRU-276)".
    public var displayName: String { name.replacingOccurrences(of: "_", with: " ") }

    /// The chemical-formula-like composition, e.g. "H 66.7 % · O 33.3 %".
    public var compositionSummary: String {
        elements.map { e in
            let z = Int(e[0])
            return "\(Elements.symbol(z: z) ?? "?") \((e[1] * 100).formatted(.number.precision(.significantDigits(3))))%"
        }.joined(separator: " · ")
    }
}

/// The SRIM-2013 tables bundled with NucPhysKit (converted by `Tools/convert_srim.py`).
public final class SRIMData: Sendable {
    public let elements: [SRIMElement]          // index z − 1
    public let compounds: [SRIMCompound]
    private let nuclearPairs: [Int: [Double]]   // key 100·min(Z) + max(Z)

    public static let shared: SRIMData = {
        guard let scoef = MassTable.resourceURL(name: "srim_scoef", ext: "csv"),
              let snuc = MassTable.resourceURL(name: "srim_snuc", ext: "csv"),
              let comp = MassTable.resourceURL(name: "srim_compounds", ext: "json")
        else { fatalError("SRIM data missing from NucPhysKit resources") }
        do {
            return try SRIMData(scoef: String(contentsOf: scoef, encoding: .utf8),
                                snuc: String(contentsOf: snuc, encoding: .utf8),
                                compounds: Data(contentsOf: comp))
        } catch {
            fatalError("SRIM data unreadable: \(error)")
        }
    }()

    init(scoef: String, snuc: String, compounds: Data) throws {
        var els: [SRIMElement] = []
        for line in scoef.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let f = line.split(separator: ",")
            guard f.count == 94, let z = Int(f[0]) else { continue }
            els.append(SRIMElement(z: z, symbol: String(f[1]), columns: f[2...].map { Double($0) ?? 0 }))
        }
        precondition(els.count == 92 && els.enumerated().allSatisfy { $0.element.z == $0.offset + 1 })
        elements = els

        var pairs: [Int: [Double]] = [:]
        for line in snuc.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let f = line.split(separator: ",")
            guard f.count == 6, let a = Int(f[0]), let b = Int(f[1]) else { continue }
            pairs[100 * min(a, b) + max(a, b)] = f[2...].map { Double($0) ?? 0 }
        }
        nuclearPairs = pairs
        self.compounds = try JSONDecoder().decode([SRIMCompound].self, from: compounds)
    }

    public func element(_ z: Int) -> SRIMElement {
        precondition((1...92).contains(z), "SRIM covers Z = 1…92")
        return elements[z - 1]
    }

    func nuclearCoefficients(_ z1: Int, _ z2: Int) -> [Double]? {
        nuclearPairs[100 * min(z1, z2) + max(z1, z2)]
    }
}
