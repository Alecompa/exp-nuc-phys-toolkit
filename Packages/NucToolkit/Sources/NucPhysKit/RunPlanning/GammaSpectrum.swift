import Foundation

/// NIST total photon attenuation, 1 keV–20 MeV, Z=1–92.
/// Log-log interpolation never bridges a duplicate-energy absorption edge.
public enum PhotonAttenuation {
    private static let tables: [String: [[Double]]] = {
        guard let url = Bundle.module.url(forResource: "photon_attenuation", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let tables = try? JSONDecoder().decode([String: [[Double]]].self, from: data) else { return [:] }
        return tables
    }()

    public static func massCoefficient(z: Int, energy: Double) throws -> Double {
        guard energy.isFinite, (1...20000).contains(energy), let rows = tables[String(z)] else {
            throw SpectrumError.attenuationRange
        }
        // Last row at or below E selects the high-energy side at an exact edge.
        let i = rows.lastIndex(where: { $0[0] <= energy })!
        let lo = rows[i]
        if lo[0] == energy || i == rows.count - 1 { return lo[1] }
        let hi = rows[i + 1]
        let f = log(energy / lo[0]) / log(hi[0] / lo[0])
        return exp(log(lo[1]) + f * log(hi[1] / lo[1]))
    }

    /// Mixture rule uses mass fractions, not atom fractions. Elemental tables assume natural isotopes.
    public static func massCoefficient(material: StoppingTarget, energy: Double) throws -> Double {
        guard !material.components.isEmpty, material.components.allSatisfy({
            $0.mass.isFinite && $0.mass > 0 && $0.stoichiometry.isFinite && $0.stoichiometry > 0
        }) else { throw SpectrumError.invalidMaterial }
        let mass = material.components.reduce(0) { $0 + $1.mass * $1.stoichiometry }
        guard mass.isFinite else { throw SpectrumError.invalidMaterial }
        return try material.components.reduce(0) { sum, c in
            sum + c.mass * c.stoichiometry / mass * (try massCoefficient(z: c.z, energy: energy))
        }
    }
}

public enum SpectrumError: Error, LocalizedError {
    case attenuationRange, invalidMaterial, invalidInput
    public var errorDescription: String? {
        switch self {
        case .attenuationRange: "Foil attenuation requires elements Z = 1–92 and gamma energies from 1 keV to 20 MeV."
        case .invalidMaterial: "Foils need a valid composition, positive density and nonnegative thickness."
        case .invalidInput: "Use finite, nonnegative counts and background, positive resolution, 1–20000 keV gamma energies, and 128–8192 channels."
        }
    }
}

public struct DetectorFoil: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var material: StoppingTarget
    /// Normal thickness in Å; angle is the photon direction relative to the foil normal.
    public var thickness: Double
    public var angle: Double
    public init(id: UUID = UUID(), material: StoppingTarget = .element(13), thickness: Double = 100000, angle: Double = 0) {
        self.id = id; self.material = material; self.thickness = thickness; self.angle = angle
    }
    public func transmission(at energy: Double) throws -> Double {
        guard thickness.isFinite, thickness >= 0, material.density.isFinite, material.density > 0,
              angle.isFinite, (0...89).contains(angle) else { throw SpectrumError.invalidMaterial }
        let mu = try PhotonAttenuation.massCoefficient(material: material, energy: energy)
        return exp(-mu * material.density * thickness * 1e-8 / cos(angle * .pi / 180))
    }
}

public struct SpectrumLine: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var energy: Double
    /// Expected photopeak area without foils, after geometry/efficiency/live time.
    public var counts: Double
    public var enabled: Bool
    public init(id: UUID = UUID(), name: String = "Custom gamma", energy: Double = 1000, counts: Double = 1000, enabled: Bool = true) {
        self.id = id; self.name = name; self.energy = energy; self.counts = counts; self.enabled = enabled
    }
}

public struct SpectrumSetup: Hashable, Codable, Sendable {
    public var lines: [SpectrumLine] = []
    public var foils: [DetectorFoil] = []
    public var maximumEnergy: Double = 3000
    public var channels: Int = 4096
    /// Integrated single-scatter continuum / photopeak area; an empirical input, not a material prediction.
    public var continuumRatio: Double = 2
    /// Flat recorded background, counts/keV; not attenuated by front foils.
    public var background: Double = 0
    /// Single- and double-escape peaks (and an optional 511 keV line) above the pair threshold.
    public var escape = EscapeModel()
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case lines, foils, maximumEnergy, channels, continuumRatio, background, escape
    }

    /// Fields missing from older saved setups keep their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lines = try c.decodeIfPresent([SpectrumLine].self, forKey: .lines) ?? []
        foils = try c.decodeIfPresent([DetectorFoil].self, forKey: .foils) ?? []
        maximumEnergy = try c.decodeIfPresent(Double.self, forKey: .maximumEnergy) ?? 3000
        channels = try c.decodeIfPresent(Int.self, forKey: .channels) ?? 4096
        continuumRatio = try c.decodeIfPresent(Double.self, forKey: .continuumRatio) ?? 2
        background = try c.decodeIfPresent(Double.self, forKey: .background) ?? 0
        escape = try c.decodeIfPresent(EscapeModel.self, forKey: .escape) ?? EscapeModel()
    }
}

/// Detector crystal, for the energy dependence of pair production.
public enum DetectorCrystal: String, Hashable, Codable, CaseIterable, Sendable, Identifiable {
    case hpge, nai, labr3, bgo, csi
    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .hpge: "HPGe"
        case .nai: "NaI(Tl)"
        case .labr3: "LaBr₃(Ce)"
        case .bgo: "BGO"
        case .csi: "CsI(Tl)"
        }
    }

    /// Mass fractions by Z.
    var composition: [(z: Int, fraction: Double)] {
        func mix(_ atoms: [(Int, Double, Double)]) -> [(z: Int, fraction: Double)] {     // (Z, count, atomic mass)
            let total = atoms.reduce(0) { $0 + $1.1 * $1.2 }
            return atoms.map { (z: $0.0, fraction: $0.1 * $0.2 / total) }
        }
        switch self {
        case .hpge: return [(32, 1)]
        case .nai: return mix([(11, 1, 22.990), (53, 1, 126.904)])
        case .labr3: return mix([(57, 1, 138.905), (35, 3, 79.904)])
        case .bgo: return mix([(83, 4, 208.980), (32, 3, 72.630), (8, 12, 15.999)])
        case .csi: return mix([(55, 1, 132.905), (53, 1, 126.904)])
        }
    }

    /// Typical single/double escape-to-photopeak ratios at 6 MeV for a mid-size crystal (rough planning defaults).
    public var typicalEscape: (single: Double, double: Double) {
        switch self {
        case .hpge: (0.8, 0.5)
        case .nai: (0.6, 0.25)
        case .labr3: (0.6, 0.3)
        case .bgo: (0.25, 0.08)
        case .csi: (0.5, 0.2)
        }
    }

    /// The crystal of a resolution preset, judged from its name.
    public static func matching(_ presetName: String) -> DetectorCrystal? {
        let n = presetName.lowercased()
        if n.contains("ge") && !n.contains("bgo") { return .hpge }
        if n.contains("nai") { return .nai }
        if n.contains("labr") { return .labr3 }
        if n.contains("bgo") { return .bgo }
        if n.contains("csi") { return .csi }
        return nil
    }
}

/// NIST XCOM pair production (nuclear + electron field) and total attenuation, 1.022–20 MeV.
public enum PairProduction {
    private static let tables: [String: [[Double]]] = {
        guard let url = Bundle.module.url(forResource: "pair_production", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let tables = try? JSONDecoder().decode([String: [[Double]]].self, from: data) else { return [:] }
        return tables
    }()

    /// Pair-production share of the total attenuation, κ/μ, in a crystal (0 below 1022 keV).
    public static func fraction(_ crystal: DetectorCrystal, energy: Double) -> Double {
        guard energy > 1022 else { return 0 }
        var pair = 0.0, total = 0.0
        for (z, w) in crystal.composition {
            guard let rows = tables[String(z)], let first = rows.first, let last = rows.last else { return 0 }
            let e = min(max(energy, first[0]), last[0])
            let i = min(rows.count - 2, rows.lastIndex(where: { $0[0] <= e }) ?? 0)
            let f = (e - rows[i][0]) / (rows[i + 1][0] - rows[i][0])
            pair += w * (rows[i][1] + f * (rows[i + 1][1] - rows[i][1]))
            total += w * (rows[i][2] + f * (rows[i + 1][2] - rows[i][2]))
        }
        return total > 0 ? pair / total : 0
    }
}

/// Escape peaks scaled from ratios at a reference energy by the crystal's pair-production share.
public struct EscapeModel: Hashable, Codable, Sendable {
    public static let referenceEnergy = 6000.0
    public var enabled = true
    public var crystal = DetectorCrystal.hpge
    /// Single- and double-escape area / photopeak area at 6 MeV.
    public var singleAtReference = 0.8
    public var doubleAtReference = 0.5
    /// Area of the 511 keV annihilation line per single-escape count (annihilation in the surroundings); 0 = off.
    public var annihilation = 0.0
    public init() {}

    public mutating func useTypical(for crystal: DetectorCrystal) {
        self.crystal = crystal
        (singleAtReference, doubleAtReference) = crystal.typicalEscape
    }

    /// Escape / photopeak area ratios at `energy` keV.
    public func ratios(at energy: Double) -> (single: Double, double: Double) {
        guard enabled, energy > 1022 else { return (0, 0) }
        let reference = PairProduction.fraction(crystal, energy: Self.referenceEnergy)
        guard reference > 0 else { return (0, 0) }
        let scale = PairProduction.fraction(crystal, energy: energy) / reference
        return (min(20, singleAtReference * scale), min(20, doubleAtReference * scale))
    }
}

public struct SpectrumBin: Identifiable, Sendable {
    public var id: Int
    public var energy: Double
    public var photopeak: Double
    public var compton: Double
    public var background: Double
    /// Single and double escape peaks and the 511 keV line.
    public var escape: Double = 0
    public var total: Double { photopeak + compton + background + escape }
}

/// Deterministic expected spectrum, not a detector transport Monte Carlo.
public enum GammaSpectrum {
    public static func comptonEdge(energy: Double) -> Double {
        energy * (2 * energy / 510.99895) / (1 + 2 * energy / 510.99895)
    }

    public static func simulate(_ setup: SpectrumSetup, resolution: ResolutionModel) throws -> [SpectrumBin] {
        guard setup.maximumEnergy.isFinite, (1...20000).contains(setup.maximumEnergy),
              (128...8192).contains(setup.channels), setup.background.isFinite, setup.background >= 0,
              setup.continuumRatio.isFinite, (0...100).contains(setup.continuumRatio),
              [setup.escape.singleAtReference, setup.escape.doubleAtReference, setup.escape.annihilation]
                .allSatisfy({ $0.isFinite && (0...20).contains($0) }) else { throw SpectrumError.invalidInput }
        let width = setup.maximumEnergy / Double(setup.channels)
        var peak = [Double](repeating: 0, count: setup.channels)
        var continuum = peak
        var escapes = peak
        for line in setup.lines where line.enabled {
            try Task.checkCancellation()
            guard line.energy.isFinite, (1...20000).contains(line.energy), line.counts.isFinite,
                  (0...1e12).contains(line.counts) else { throw SpectrumError.invalidInput }
            let area = try setup.foils.reduce(line.counts) { $0 * (try $1.transmission(at: line.energy)) }
            try deposit(energy: line.energy, area: area, width: width, resolution: resolution, into: &peak)
            let (single, double) = setup.escape.ratios(at: line.energy)
            if single > 0 || double > 0, area > 0 {
                try deposit(energy: line.energy - 510.99895, area: area * single, width: width, resolution: resolution, into: &escapes)
                try deposit(energy: line.energy - 1021.9979, area: area * double, width: width, resolution: resolution, into: &escapes)
                if setup.escape.annihilation > 0 {
                    try deposit(energy: 510.99895, area: area * single * setup.escape.annihilation,
                                width: width, resolution: resolution, into: &escapes)
                }
            }
            guard setup.continuumRatio > 0, area > 0 else { continue }
            let edge = comptonEdge(energy: line.energy)
            // Midpoint integration in deposited energy. dσ/dT ∝ k + 1/k − sin²θ;
            // the angular Jacobian cancels the k² in dσ/dΩ.
            let samples = min(8192, max(512, Int(ceil(edge / width))))
            let step = edge / Double(samples)
            var weights = [Double]()
            for j in 0..<samples {
                let t = (Double(j) + 0.5) * step
                let k = 1 - t / line.energy
                let cosine = 1 - 510.99895 * (1 / (line.energy - t) - 1 / line.energy)
                weights.append(k + 1 / k - (1 - cosine * cosine))
            }
            let norm = weights.reduce(0, +)
            for j in 0..<samples {
                if j.isMultiple(of: 64) { try Task.checkCancellation() }
                try deposit(energy: (Double(j) + 0.5) * step,
                            area: area * setup.continuumRatio * weights[j] / norm,
                            width: width, resolution: resolution, into: &continuum)
            }
        }
        return (0..<setup.channels).map {
            SpectrumBin(id: $0, energy: (Double($0) + 0.5) * width,
                        photopeak: peak[$0], compton: continuum[$0], background: setup.background * width, escape: escapes[$0])
        }
    }

    /// Integrate the Gaussian across channel boundaries, including sub-channel narrow peaks.
    /// Out-of-window counts are lost, never renormalized back into the displayed range.
    private static func deposit(energy: Double, area: Double, width: Double, resolution: ResolutionModel,
                                into bins: inout [Double]) throws {
        let sigma = resolution.fwhm(at: energy) / (2 * sqrt(2 * log(2.0)))
        guard sigma.isFinite, sigma > 0, sigma < 1e6 else { throw SpectrumError.invalidInput }
        let lo = max(0, Int(floor((energy - 6 * sigma) / width)))
        let hi = min(bins.count - 1, Int(floor((energy + 6 * sigma) / width)))
        guard lo <= hi else { return }
        let scale = sqrt(2.0) * sigma
        for i in lo...hi {
            let left = (Double(i) * width - energy) / scale
            let right = (Double(i + 1) * width - energy) / scale
            bins[i] += area * 0.5 * (erf(right) - erf(left))
        }
    }

    public static func csv(_ bins: [SpectrumBin]) -> String {
        "energy_keV,total_counts,photopeak_counts,compton_counts,background_counts,escape_counts\n" + bins.map {
            "\($0.energy),\($0.total),\($0.photopeak),\($0.compton),\($0.background),\($0.escape)"
        }.joined(separator: "\n")
    }
}
