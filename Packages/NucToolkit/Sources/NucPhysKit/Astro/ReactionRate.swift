import Foundation

/// CGS constants for reaction rates.
enum CGS {
    static let avogadro = 6.022_140_76e23
    static let erg = 1.602_176_634e-9          // erg per keV
    static let atomicMassGram = 1.660_539_066_60e-24
    static let hbar = 1.054_571_817e-27        // erg s
    static let barn = 1e-24                     // cm²
}

// MARK: - S factor

/// Astrophysical S factor S(E) = σ(E) E exp(2πη), keV b, as a function of the centre-of-mass energy (keV).
public struct SFactorModel: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case polynomial, table
    }
    public struct Point: Hashable, Sendable, Codable {
        /// keV, centre of mass
        public var energy: Double
        /// keV b
        public var s: Double
        public init(energy: Double, s: Double) { self.energy = energy; self.s = s }
    }

    public var kind: Kind
    /// S(0), keV b
    public var s0: Double
    /// S'(0), b
    public var s1: Double
    /// S''(0)/2 is the quadratic coefficient: S = s0 + s1 E + s2 E²/2, s2 in b/keV
    public var s2: Double
    /// Sorted by energy.
    public var table: [Point]

    public init(kind: Kind = .polynomial, s0: Double = 1, s1: Double = 0, s2: Double = 0, table: [Point] = []) {
        self.kind = kind; self.s0 = s0; self.s1 = s1; self.s2 = s2
        self.table = table.sorted { $0.energy < $1.energy }
    }

    /// S(E), keV b. Tables interpolate linearly in ln S (linearly where S ≤ 0) and are held constant
    /// beyond their ends.
    public func s(at e: Double) -> Double {
        switch kind {
        case .polynomial:
            return max(0, s0 + s1 * e + 0.5 * s2 * e * e)
        case .table:
            guard let first = table.first, let last = table.last else { return 0 }
            if e <= first.energy { return first.s }
            if e >= last.energy { return last.s }
            var lo = 0, hi = table.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if table[mid].energy <= e { lo = mid } else { hi = mid }
            }
            let a = table[lo], b = table[hi]
            let t = (e - a.energy) / (b.energy - a.energy)
            if a.s > 0, b.s > 0 { return exp(log(a.s) + t * (log(b.s) - log(a.s))) }
            return a.s + t * (b.s - a.s)
        }
    }

    /// Energy range the model is defined on without extrapolation (nil for a polynomial).
    public var tableRange: ClosedRange<Double>? {
        guard kind == .table, let a = table.first?.energy, let b = table.last?.energy else { return nil }
        return a...b
    }

    public enum ParseError: Error, Equatable, LocalizedError {
        case tooFewPoints(Int)
        case badLine(Int)
        public var errorDescription: String? {
            switch self {
            case .tooFewPoints(let n): "Need at least 2 points (found \(n))."
            case .badLine(let n): "Line \(n) is not two numbers."
            }
        }
    }

    /// Parses "E S" rows (keV, keV b): separators comma, semicolon, tab or spaces; '#' starts a comment;
    /// a non-numeric first line is taken as a header.
    public static func parseTable(_ text: String) throws -> [Point] {
        var points: [Point] = []
        for (i, raw) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let fields = line.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\t" || $0 == " " })
            guard !fields.isEmpty else { continue }
            guard fields.count >= 2, let e = Double(fields[0]), let s = Double(fields[1]) else {
                if points.isEmpty && i == 0 { continue }     // header
                throw ParseError.badLine(i + 1)
            }
            points.append(Point(energy: e, s: s))
        }
        guard points.count >= 2 else { throw ParseError.tooFewPoints(points.count) }
        return points.sorted { $0.energy < $1.energy }
    }

    /// Two-column text of the table (keV, keV b).
    public var tableText: String {
        table.map { "\(Self.fmt($0.energy)), \(Self.fmt($0.s))" }.joined(separator: "\n")
    }

    private static func fmt(_ x: Double) -> String { String(format: "%.6g", x) }
}

extension ChargedChannel {
    /// σ(E) = S(E)/E · exp(−2πη), barn, for S in keV b and E in keV.
    public func crossSection(sFactor s: Double, energy e: Double) -> Double {
        s / e * gamowFactor(e)
    }

    /// S(E) = σ E exp(2πη), keV b.
    public func sFactor(crossSection sigma: Double, energy e: Double) -> Double {
        sigma * e * exp(2 * .pi * sommerfeld(e))
    }

    /// Electron-screening enhancement f = exp(πη U_e/E) (Assenbaum, Langanke & Rolfs), U_e in eV.
    public func screeningFactor(energy e: Double, potential ue: Double) -> Double {
        exp(.pi * sommerfeld(e) * ue / 1000 / e)
    }
}

// MARK: - Narrow resonances

/// A narrow resonance: energy (keV, centre of mass) and strength ωγ (eV).
public struct NarrowResonance: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var energy: Double
    public var strength: Double

    public init(id: UUID = UUID(), energy: Double, strength: Double) {
        self.id = id; self.energy = energy; self.strength = strength
    }

    /// ω = (2J+1)/((2j₁+1)(2j₂+1)) (× (1+δ₁₂) for identical particles, not included).
    public static func spinFactor(j: Double, j1: Double, j2: Double) -> Double {
        (2 * j + 1) / ((2 * j1 + 1) * (2 * j2 + 1))
    }

    /// ωγ = ω Γ_a Γ_b / Γ (any common width unit).
    public static func strength(omega: Double, gammaA: Double, gammaB: Double, total: Double) -> Double {
        total > 0 ? omega * gammaA * gammaB / total : 0
    }
}

extension ChargedChannel {
    /// λ²/2 with λ the centre-of-mass de Broglie wavelength h/p at `e` keV, cm².
    public func deBroglieHalfSquared(energy e: Double) -> Double {
        let lambdaFm = 2 * .pi * PhysicalConstants.hbarC / (2 * reducedMassEnergy * e).squareRoot()
        return pow(lambdaFm * 1e-13, 2) / 2
    }

    /// Maximum thick-target yield (reactions per projectile) of a narrow resonance:
    /// Y = (λ²/2) · (m₁+m₂)/m₂ · ωγ/ε_eff, with ε_eff the laboratory stopping cross section per active
    /// nucleus (eV cm²) at the resonance energy, ωγ in eV.
    public func thickTargetYield(resonanceEnergy e: Double, strength: Double, effectiveStopping eps: Double) -> Double {
        deBroglieHalfSquared(energy: e) * (m1 + m2) / m2 * strength / eps
    }

    /// ωγ (eV) from a measured maximum thick-target yield; inverse of `thickTargetYield`.
    public func resonanceStrength(resonanceEnergy e: Double, yield y: Double, effectiveStopping eps: Double) -> Double {
        y * eps / (deBroglieHalfSquared(energy: e) * (m1 + m2) / m2)
    }

    /// N_A⟨σv⟩ of a narrow resonance, cm³ mol⁻¹ s⁻¹:
    /// N_A (2π/(μkT))^{3/2} ħ² ωγ exp(−E_R/kT).
    public func narrowResonanceRate(_ r: NarrowResonance, t9: Double) -> Double {
        let kT = Self.kT(t9) * CGS.erg
        let mu = reducedMass * CGS.atomicMassGram
        let wg = r.strength * 1e-3 * CGS.erg
        let arg = r.energy / Self.kT(t9)
        guard arg < 700 else { return 0 }
        return CGS.avogadro * pow(2 * .pi / (mu * kT), 1.5) * CGS.hbar * CGS.hbar * wg * exp(-arg)
    }
}

// MARK: - Non-resonant rate

extension ChargedChannel {
    /// N_A⟨σv⟩ (cm³ mol⁻¹ s⁻¹) from an S factor by numerical integration:
    /// N_A √(8/(πμ)) (kT)^{−3/2} ∫ S(E) exp(−2πη − E/kT) dE, Simpson's rule in ln E.
    public func rate(sFactor model: SFactorModel, t9: Double, points: Int = 2000) -> Double {
        let kT = Self.kT(t9)
        let w = gamowWindow(t9: t9)
        let lo = max(w.peak / 200, 1e-6)
        let hi = max(w.peak + 12 * w.width, w.peak + 60 * kT)
        let a = log(lo), b = log(hi)
        let n = points % 2 == 0 ? points : points + 1
        let h = (b - a) / Double(n)
        let sqrtEG = gamowEnergy.squareRoot()
        var sum = 0.0
        for i in 0...n {
            let e = exp(a + Double(i) * h)
            let x = -sqrtEG / e.squareRoot() - e / kT
            let fx = x < -700 ? 0 : model.s(at: e) * exp(x) * e       // dE = E d(ln E)
            let wgt: Double = (i == 0 || i == n) ? 1 : (i % 2 == 1 ? 4 : 2)
            sum += wgt * fx
        }
        let integral = sum * h / 3                                // keV² b
        let mu = reducedMass * CGS.atomicMassGram
        let kTerg = kT * CGS.erg
        return CGS.avogadro * (8 / (.pi * mu)).squareRoot() * pow(kTerg, -1.5)
            * integral * CGS.erg * CGS.erg * CGS.barn
    }

    /// The standard temperature grid of rate tables (REACLIB/STARLIB-like), GK.
    public static let rateGrid: [Double] = [0.001, 0.002, 0.003, 0.004, 0.005, 0.006, 0.007, 0.008, 0.009,
        0.01, 0.011, 0.012, 0.013, 0.014, 0.015, 0.016, 0.018, 0.02, 0.025, 0.03, 0.04, 0.05, 0.06, 0.07,
        0.08, 0.09, 0.1, 0.11, 0.12, 0.13, 0.14, 0.15, 0.16, 0.18, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5,
        0.6, 0.7, 0.8, 0.9, 1, 1.25, 1.5, 1.75, 2, 2.5, 3, 3.5, 4, 5, 6, 7, 8, 9, 10]
}

// MARK: - Rutherford scattering

/// Elastic Coulomb (Rutherford) scattering of the projectile on the target, relativistic kinematics.
public struct RutherfordScattering: Sendable {
    public let kinematics: TwoBodyKinematics
    public let z1: Int, z2: Int

    public init(projectile: Nuclide, target: Nuclide, beamEnergy: Double) {
        z1 = projectile.z; z2 = target.z
        kinematics = TwoBodyKinematics(m1: projectile.kinematicMass, m2: target.kinematicMass,
                                       m3: projectile.kinematicMass, m4: target.kinematicMass, beamEnergy: beamEnergy)
    }

    public struct Point: Hashable, Sendable {
        public let thetaCM: Double
        public let energy: Double
        /// b/sr
        public let crossSectionCM: Double
        /// b/sr
        public let crossSectionLab: Double
    }

    /// dσ/dΩ in the centre of mass, b/sr: (Z₁Z₂e²/(4E))² / sin⁴(θ/2).
    public func crossSectionCM(thetaCM: Double) -> Double {
        let a = Double(z1 * z2) * PhysicalConstants.coulombConstant / (4 * kinematics.centerOfMassEnergy)  // fm
        return a * a / pow(sin(thetaCM / 2), 4) * 1e-2
    }

    /// The scattered projectile at laboratory angle `theta` (radians); two solutions when it is heavier
    /// than the target.
    public func at(labAngle theta: Double) -> [Point] {
        // Equal masses give a degenerate second branch at θ* = π with zero energy.
        kinematics.solutions(labAngle: theta).filter { $0.ejectileEnergy > 1e-6 * kinematics.beamEnergy }.map { s in
            let cm = crossSectionCM(thetaCM: s.thetaCM)
            return Point(thetaCM: s.thetaCM, energy: s.ejectileEnergy, crossSectionCM: cm, crossSectionLab: cm * s.jacobian)
        }
    }
}
