import Foundation

/// A ground-state nuclide with its AME2020 mass excess.
public struct Nuclide: Hashable, Sendable, Identifiable, Codable {
    public let z: Int
    public let a: Int
    /// Mass excess Δ = M_atomic − A·u, keV.
    public let massExcess: Double
    /// One-sigma uncertainty of the mass excess, keV.
    public let massExcessUncertainty: Double
    /// True when AME flags the value as estimated from systematics ('#').
    public let isEstimated: Bool

    public init(z: Int, a: Int, massExcess: Double, massExcessUncertainty: Double, isEstimated: Bool = false) {
        self.z = z
        self.a = a
        self.massExcess = massExcess
        self.massExcessUncertainty = massExcessUncertainty
        self.isEstimated = isEstimated
    }

    public var id: Int { z * 1000 + a }
    public var n: Int { a - z }
    public var symbol: String { Elements.symbol(z: z) ?? "?" }
    public var elementName: String { Elements.name(z: z) ?? "Unknown" }

    /// Neutral-atom mass, keV/c².
    public var atomicMass: Double { Double(a) * PhysicalConstants.atomicMassUnit + massExcess }

    /// Bare-nucleus mass, keV/c² (atomic mass minus electrons plus their binding energy).
    public var nuclearMass: Double {
        atomicMass - Double(z) * PhysicalConstants.electronMass + PhysicalConstants.electronBindingEnergy(z: z)
    }

    /// Ion mass used for kinematics, keV/c²: atomic mass minus Z electron masses.
    /// Electron binding is left out so that the kinematic Q value equals the AME Q value exactly
    /// (the standard convention of kinematics codes; the difference is ≲ keV even for heavy ions).
    public var kinematicMass: Double { atomicMass - Double(z) * PhysicalConstants.electronMass }

    /// Atomic mass in micro-u, as tabulated by AME.
    public var atomicMassMicroU: Double { atomicMass / PhysicalConstants.atomicMassUnit * 1e6 }

    /// Total binding energy, keV (from atomic masses, as AME defines it).
    public var bindingEnergy: Double {
        let hydrogenExcess = 7288.971064, neutronExcess = 8071.31806
        return Double(z) * hydrogenExcess + Double(n) * neutronExcess - massExcess
    }

    public var bindingEnergyPerNucleon: Double { a > 0 ? bindingEnergy / Double(a) : 0 }

    /// Plain ASCII label, e.g. "13N", "n", "4He".
    public var plainLabel: String { z == 0 && a == 1 ? "n" : "\(a)\(symbol)" }

    /// Label with superscript mass number, e.g. "¹³N".
    public var label: String { z == 0 && a == 1 ? "n" : "\(Superscript.digits(a))\(symbol)" }

    /// Conventional short name for light ions, used inside reaction notation: p, d, t, α…
    public var reactionLabel: String {
        switch (z, a) {
        case (0, 1): "n"
        case (1, 1): "p"
        case (1, 2): "d"
        case (1, 3): "t"
        case (2, 4): "α"
        default: label
        }
    }
}

public enum Superscript {
    private static let map: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻", "+": "⁺",
    ]

    public static func digits(_ value: Int) -> String {
        String(String(value).map { map[$0] ?? $0 })
    }

    public static func string(_ s: String) -> String {
        String(s.map { map[$0] ?? $0 })
    }
}
