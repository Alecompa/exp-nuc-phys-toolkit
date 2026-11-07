import Foundation

/// The projectile for a stopping calculation.
public struct StoppingIon: Hashable, Sendable {
    public let z: Int
    /// Mass in u.
    public let mass: Double

    public init(z: Int, mass: Double) {
        self.z = z
        self.mass = mass
    }

    /// SRIM's default: the most abundant isotope.
    public init(z: Int, data: SRIMData = .shared) {
        self.init(z: z, mass: data.element(z).isotopeMass)
    }

    /// The ion of a specific nuclide, with its AME2020 atomic mass.
    public init(nuclide: Nuclide) {
        self.init(z: nuclide.z, mass: nuclide.atomicMass / PhysicalConstants.atomicMassUnit)
    }
}

/// A homogeneous target layer: elements with stoichiometries, a density and a phase.
public struct StoppingTarget: Hashable, Sendable, Codable {
    public struct Component: Hashable, Sendable, Codable {
        public let z: Int
        public let stoichiometry: Double
        /// Mass in u (SRIM default: natural atomic weight).
        public let mass: Double

        public init(z: Int, stoichiometry: Double, mass: Double) {
            self.z = z
            self.stoichiometry = stoichiometry
            self.mass = mass
        }
    }

    public var name: String
    public var components: [Component]
    /// g/cm³
    public var density: Double
    public var isGas: Bool
    /// Bragg-rule (compound) correction factor; 1 = none.
    public var compoundCorrection: Double

    public init(name: String, components: [Component], density: Double, isGas: Bool = false, compoundCorrection: Double = 1) {
        self.name = name
        self.components = components.filter { $0.stoichiometry > 0 }
        self.density = density
        self.isGas = isGas
        self.compoundCorrection = compoundCorrection
    }

    /// A pure element at SRIM's default density (solid, or the gas at STP).
    public static func element(_ z: Int, gas: Bool? = nil, data: SRIMData = .shared) -> StoppingTarget {
        let e = data.element(z)
        let isGas = gas ?? (SRIMStopping.gasElements.contains(z))
        return StoppingTarget(name: Elements.name(z: z) ?? e.symbol,
                              components: [Component(z: z, stoichiometry: 1, mass: e.naturalMass)],
                              density: isGas ? e.gasDensity : e.density, isGas: isGas)
    }

    /// A material from SRIM's compound dictionary.
    public static func compound(_ c: SRIMCompound, data: SRIMData = .shared) -> StoppingTarget {
        StoppingTarget(name: c.displayName,
                       components: c.elements.map {
                           let z = Int($0[0])
                           return Component(z: z, stoichiometry: $0[1], mass: data.element(z).naturalMass)
                       },
                       density: c.density, isGas: c.gas)
    }

    /// Atom fractions (stoichiometries normalised to 1).
    public var fractions: [Double] {
        let total = components.reduce(0) { $0 + $1.stoichiometry }
        return components.map { $0.stoichiometry / total }
    }

    public var meanMass: Double { zip(components, fractions).reduce(0) { $0 + $1.0.mass * $1.1 } }
    public var meanZ: Double { zip(components, fractions).reduce(0) { $0 + Double($1.0.z) * $1.1 } }

    /// Atomic density, atoms/cm³ (SRIM's Avogadro constant 6.022·10²³).
    public var atomDensity: Double { 6.022e23 * density / meanMass }
    /// Atomic density, atoms/Å³.
    public var atomsPerA3: Double { 0.6022 * density / meanMass }

    /// Formula-like label, e.g. "H₂O" style is not attempted; "Si", "C 50 % · H 50 %".
    public var compositionLabel: String {
        if components.count == 1 { return Elements.symbol(z: components[0].z) ?? "?" }
        return zip(components, fractions).map {
            "\(Elements.symbol(z: $0.0.z) ?? "?") \(($0.1 * 100).formatted(.number.precision(.significantDigits(3))))%"
        }.joined(separator: " · ")
    }
}

/// SRIM's eight stopping units.
public enum StoppingUnit: Int, CaseIterable, Identifiable, Sendable, Codable {
    case eVPerAngstrom = 1, keVPerMicron, MeVPerMillimetre, keVPerMicrogramCm2, MeVPerMilligramCm2,
         keVPerMilligramCm2, eVPer1e15AtomsCm2, reduced

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .eVPerAngstrom: "eV/Å"
        case .keVPerMicron: "keV/µm"
        case .MeVPerMillimetre: "MeV/mm"
        case .keVPerMicrogramCm2: "keV/(µg/cm²)"
        case .MeVPerMilligramCm2: "MeV/(mg/cm²)"
        case .keVPerMilligramCm2: "keV/(mg/cm²)"
        case .eVPer1e15AtomsCm2: "eV/(10¹⁵ at/cm²)"
        case .reduced: "LSS reduced"
        }
    }

    /// Multiplies a stopping cross section in eV/(10¹⁵ atoms/cm²) to give this unit (SRIM's factors).
    public func factor(ion: StoppingIon, target: StoppingTarget) -> Double {
        let n = target.atomDensity, m = target.meanMass
        switch self {
        case .eVPerAngstrom: return 1e-23 * n
        case .keVPerMicron, .MeVPerMillimetre: return 1e-22 * n
        case .keVPerMicrogramCm2, .MeVPerMilligramCm2: return 0.60222 / m
        case .keVPerMilligramCm2: return 602.22 / m
        case .eVPer1e15AtomsCm2: return 1
        case .reduced:
            let z1 = Double(ion.z), mz = target.meanZ, m1 = ion.mass
            return (m1 + m) * (pow(z1, 0.6667) + pow(mz, 0.6667)).squareRoot() / (8.462 * mz * z1 * m1)
        }
    }
}

/// Units for a layer thickness.
public enum ThicknessUnit: String, CaseIterable, Identifiable, Sendable, Codable {
    case angstrom = "Å", nanometre = "nm", micrometre = "µm", millimetre = "mm",
         microgramCm2 = "µg/cm²", milligramCm2 = "mg/cm²", atoms1e15 = "10¹⁵ at/cm²"

    public var id: String { rawValue }

    /// Thickness in Å for a value in this unit.
    public func toAngstrom(_ value: Double, target: StoppingTarget) -> Double {
        switch self {
        case .angstrom: value
        case .nanometre: value * 10
        case .micrometre: value * 1e4
        case .millimetre: value * 1e7
        case .microgramCm2: value * 1e-6 / target.density * 1e8
        case .milligramCm2: value * 1e-3 / target.density * 1e8
        case .atoms1e15: value * 1e15 / (target.atomsPerA3 * 1e16)
        }
    }

    public func fromAngstrom(_ a: Double, target: StoppingTarget) -> Double {
        a / toAngstrom(1, target: target)
    }
}
