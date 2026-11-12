import Foundation

/// Beam current, particle rate, integrated charge and beam power.
public enum Beam {
    public static let elementaryCharge = 1.602_176_634e-19

    /// Particles per second for an electrical current (A) of ions in charge state q.
    public static func particlesPerSecond(current: Double, chargeState q: Int) -> Double {
        current / (Double(max(q, 1)) * elementaryCharge)
    }

    /// Electrical current (A) of a particle rate in charge state q.
    public static func current(particlesPerSecond pps: Double, chargeState q: Int) -> Double {
        pps * Double(max(q, 1)) * elementaryCharge
    }

    /// Particles carried by an integrated charge (C).
    public static func particles(charge: Double, chargeState q: Int) -> Double {
        charge / (Double(max(q, 1)) * elementaryCharge)
    }

    /// Beam power on target, W, for a particle rate and kinetic energy (keV).
    public static func power(particlesPerSecond pps: Double, energy keV: Double) -> Double {
        pps * keV * 1e3 * elementaryCharge
    }
}

/// Counting statistics for a peak on a background.
public enum CountingStatistics {
    /// Measuring time (s) for a relative statistical uncertainty `u` of the net signal, with signal rate `s` and
    /// background rate `b` (counts/s in the peak region). The background is known as well as from an equal-length
    /// measurement when `backgroundFromEqualTime` (σ² = S + 2B), or exactly otherwise (σ² = S + B).
    public static func time(signal s: Double, background b: Double, relativeUncertainty u: Double,
                            backgroundFromEqualTime: Bool = true) -> Double {
        guard s > 0, u > 0 else { return .infinity }
        let k = backgroundFromEqualTime ? 2.0 : 1.0
        return (s + k * b) / (s * s * u * u)
    }

    /// Relative uncertainty of the net signal after time t (s).
    public static func relativeUncertainty(signal s: Double, background b: Double, time t: Double,
                                           backgroundFromEqualTime: Bool = true) -> Double {
        guard s > 0, t > 0 else { return .infinity }
        let k = backgroundFromEqualTime ? 2.0 : 1.0
        return ((s + k * b) * t).squareRoot() / (s * t)
    }

    /// Currie's detection limit L_D = 2.71 + 4.65 √B (counts) for a background of B counts.
    public static func detectionLimit(backgroundCounts b: Double) -> Double { 2.71 + 4.65 * b.squareRoot() }
}

extension ChargedChannel {
    /// Yield (reactions per projectile) of a thin target: σ N_t, σ in b and N_t in nuclei/cm².
    public static func thinTargetYield(crossSection barn: Double, arealDensity n: Double) -> Double {
        barn * 1e-24 * n
    }

    /// Yield of a target of finite thickness from an S factor: Y = ∫ σ(E)/ε(E) dE over the laboratory energies
    /// from `exitEnergy` to `entranceEnergy` (keV), with ε the laboratory stopping cross section per active
    /// nucleus (eV cm², a function of the laboratory energy). σ includes electron screening U_e (eV).
    public func targetYield(sFactor model: SFactorModel, entranceEnergy e1: Double, exitEnergy e0: Double,
                            screening ue: Double = 0, steps: Int = 200,
                            stopping eps: (Double) -> Double) -> Double {
        guard e1.isFinite, e0.isFinite, e1 > e0, e0 >= 0, steps > 0 else { return 0 }
        let n = steps % 2 == 0 ? steps : steps + 1
        let h = (e1 - e0) / Double(n)
        var sum = 0.0
        for i in 0...n {
            let eLab = max(e0 + Double(i) * h, 1e-3)
            let ecm = cmEnergy(lab: eLab)
            let sigma = crossSection(sFactor: model.s(at: ecm), energy: ecm) * (ue > 0 ? screeningFactor(energy: ecm, potential: ue) : 1)
            let w: Double = (i == 0 || i == n) ? 1 : (i % 2 == 1 ? 4 : 2)
            let s = eps(eLab)
            sum += s > 0 ? w * sigma * 1e-24 / s : 0
        }
        return sum * h * 1e3 / 3        // dE in eV
    }

    /// Yield-weighted mean centre-of-mass energy in the same target (the "effective energy").
    public func effectiveEnergy(sFactor model: SFactorModel, entranceEnergy e1: Double, exitEnergy e0: Double,
                                screening ue: Double = 0, steps: Int = 200,
                                stopping eps: (Double) -> Double) -> Double? {
        guard e1.isFinite, e0.isFinite, e1 > e0, e0 >= 0, steps > 0 else { return nil }
        var num = 0.0, den = 0.0
        let h = (e1 - e0) / Double(steps)
        for i in 0..<steps {
            let eLab = e0 + (Double(i) + 0.5) * h
            let ecm = cmEnergy(lab: eLab)
            let sigma = crossSection(sFactor: model.s(at: ecm), energy: ecm) * (ue > 0 ? screeningFactor(energy: ecm, potential: ue) : 1)
            let s = eps(eLab)
            guard s > 0 else { continue }
            num += ecm * sigma / s; den += sigma / s
        }
        return den > 0 ? num / den : nil
    }
}
