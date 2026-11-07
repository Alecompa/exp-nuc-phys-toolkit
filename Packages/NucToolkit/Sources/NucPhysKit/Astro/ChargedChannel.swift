import Foundation

/// A two-body channel of charged particles (e.g. p + ¹²C): Coulomb quantities, Gamow window,
/// penetrabilities and the Wigner limit. Energies in keV (centre of mass unless stated), lengths in fm,
/// masses in u (atomic masses, as is customary for reduced masses in astrophysics).
public struct ChargedChannel: Hashable, Sendable {
    public let z1: Int, z2: Int
    public let a1: Int, a2: Int
    /// Masses in u: particle 1 is the projectile, 2 the target (at rest in the laboratory).
    public let m1: Double, m2: Double
    public let label: String

    public init(projectile: Nuclide, target: Nuclide) {
        z1 = projectile.z; z2 = target.z
        a1 = projectile.a; a2 = target.a
        m1 = projectile.atomicMass / PhysicalConstants.atomicMassUnit
        m2 = target.atomicMass / PhysicalConstants.atomicMassUnit
        label = "\(projectile.label) + \(target.label)"
    }

    public init(z1: Int, a1: Int, m1: Double, z2: Int, a2: Int, m2: Double, label: String = "") {
        self.z1 = z1; self.z2 = z2; self.a1 = a1; self.a2 = a2; self.m1 = m1; self.m2 = m2
        self.label = label
    }

    /// The entrance channel projectile + target of `reaction`.
    public static func entrance(_ reaction: Reaction) -> ChargedChannel {
        ChargedChannel(projectile: reaction.projectile, target: reaction.target)
    }

    /// The exit channel ejectile + residual, or nil for a γ or neutron ejectile.
    public static func exit(_ reaction: Reaction) -> ChargedChannel? {
        guard let e = reaction.ejectile.nuclide else { return nil }
        return ChargedChannel(projectile: e, target: reaction.residual)
    }

    public var isCharged: Bool { z1 > 0 && z2 > 0 }

    /// Reduced mass, u.
    public var reducedMass: Double { m1 * m2 / (m1 + m2) }
    /// Reduced mass energy μc², keV.
    public var reducedMassEnergy: Double { reducedMass * PhysicalConstants.atomicMassUnit }

    // MARK: Energies

    /// Laboratory energy of the projectile for a centre-of-mass energy (non-relativistic, target at rest).
    public func labEnergy(cm: Double) -> Double { cm * (m1 + m2) / m2 }
    public func cmEnergy(lab: Double) -> Double { lab * m2 / (m1 + m2) }

    /// kT in keV for a temperature in GK.
    public static func kT(_ t9: Double) -> Double { 86.173_332_62 * t9 }

    // MARK: Coulomb

    /// Sommerfeld parameter η = Z₁Z₂e²/(ħv) at a centre-of-mass energy (keV).
    public func sommerfeld(_ e: Double) -> Double {
        Double(z1 * z2) * PhysicalConstants.fineStructure / (2 * e / reducedMassEnergy).squareRoot()
    }

    /// Gamow energy E_G = 2μc²(παZ₁Z₂)², keV, so that exp(−2πη) = exp(−√(E_G/E)).
    public var gamowEnergy: Double {
        2 * reducedMassEnergy * pow(Double.pi * PhysicalConstants.fineStructure * Double(z1 * z2), 2)
    }

    /// Gamow (tunnelling) factor exp(−2πη).
    public func gamowFactor(_ e: Double) -> Double { exp(-2 * .pi * sommerfeld(e)) }

    /// Wave number k, fm⁻¹.
    public func waveNumber(_ e: Double) -> Double {
        (2 * reducedMassEnergy * e).squareRoot() / PhysicalConstants.hbarC
    }

    /// Radius r₀(A₁^⅓ + A₂^⅓), fm.
    public func radius(r0: Double) -> Double { r0 * (pow(Double(a1), 1.0 / 3) + pow(Double(a2), 1.0 / 3)) }

    /// Coulomb barrier Z₁Z₂e²/R, keV.
    public func coulombBarrier(radius: Double) -> Double {
        Double(z1 * z2) * PhysicalConstants.coulombConstant / radius
    }

    // MARK: Gamow window

    public struct GamowWindow: Hashable, Sendable {
        /// Most effective energy E₀, keV (centre of mass).
        public let peak: Double
        /// 1/e full width Δ of the Gaussian approximation, keV.
        public let width: Double
        /// kT, keV.
        public let kT: Double
        /// τ = 3E₀/kT; the integrand at E₀ is exp(−τ).
        public var tau: Double { 3 * peak / kT }
        public var lower: Double { max(0, peak - width / 2) }
        public var upper: Double { peak + width / 2 }
    }

    /// Gamow peak E₀ = (√E_G · kT/2)^⅔ and width Δ = 4√(E₀kT/3) for a constant S factor.
    public func gamowWindow(t9: Double) -> GamowWindow {
        let kT = Self.kT(t9)
        let e0 = pow(gamowEnergy.squareRoot() * kT / 2, 2.0 / 3)
        return GamowWindow(peak: e0, width: 4 / 3.0.squareRoot() * (e0 * kT).squareRoot(), kT: kT)
    }

    /// The Gamow integrand exp(−E/kT − √(E_G/E)) (constant S), unnormalised.
    public func gamowIntegrand(_ e: Double, t9: Double) -> Double {
        guard e > 0 else { return 0 }
        return exp(-e / Self.kT(t9) - (gamowEnergy / e).squareRoot())
    }

    // MARK: Penetrability and widths

    /// Penetrability P_ℓ and shift S_ℓ at channel radius `radius` (fm) and energy `e` (keV).
    public func penetrability(l: Int, energy e: Double, radius: Double) -> CoulombFunctions.Result {
        let rho = waveNumber(e) * radius
        return CoulombFunctions.penetrability(l: l, eta: isCharged ? sommerfeld(e) : 0, rho: rho)
    }

    /// Wigner limit γ²_W = 3ħ²/(2μa²), keV (Teichmann–Wigner convention).
    public func wignerLimit(radius: Double) -> Double {
        3 * PhysicalConstants.hbarC * PhysicalConstants.hbarC / (2 * reducedMassEnergy * radius * radius)
    }
}

extension PhysicalConstants {
    /// e²/(4πε₀) = αħc, keV fm.
    public static var coulombConstant: Double { fineStructure * hbarC }
}
