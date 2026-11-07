import Foundation

/// SRIM-2013 stopping powers of an ion in one element, ported from LunaSRIM's `stopping.py`
/// (J. Skowronski, MIT licence), which reconstructs SRModule.exe / TRIM.exe.
///
/// Energies in keV (or keV/u where stated); stopping cross sections in eV/(10¹⁵ atoms/cm²).
/// Equation numbers refer to LunaSRIM's docs/physics.md.
public enum SRIMStopping {
    /// Noble gases: no phase correction.
    static let nobleGases: Set<Int> = [2, 10, 18, 36, 54, 86]
    /// Elements that are gaseous in their natural state.
    static let gasElements: Set<Int> = [1, 2, 7, 8, 9, 10, 17, 18, 35, 36, 53, 54, 85, 86]
    static let phaseFactorValue = 0.92

    /// True for elements SRIM treats as gaseous in their natural state.
    public static func isNaturalGas(_ z: Int) -> Bool { gasElements.contains(z) }

    public enum StoppingError: Error, Equatable {
        /// SRIM's phase correction overflows above ≈ 5.9 GeV/u (VB run-time error 6).
        case energyTooHigh
    }

    // MARK: Electronic stopping

    private static func polynomial(_ c: [Double], _ x: Double) -> Double {
        var s = 0.0, p = 1.0
        for v in c { s += v * p; p *= x }
        return s
    }

    /// The ten-parameter SRIM fit, Eq. (3).
    private static func fit(_ c: [Double], _ e: Double) -> Double {
        let low = c[0] * pow(e, c[1]) + c[2] * pow(e, c[3]) + c[8] * e.squareRoot()
        let high = (c[4] / pow(e, c[5])) * (log(c[6] / e + c[7] * e) + c[9] / pow(e, 0.2))
        return low * high / (low + high)
    }

    /// Bethe formula with shell, Barkas and Bloch terms, Eqs. (4)–(6). `e` in keV/u.
    static func bethe(z1: Int, target t: SRIMElement, e: Double, gas: Bool) -> Double {
        let z1d = Double(z1), z2 = Double(t.z)
        let beta2 = 1 - 1 / pow(1 + e / 931_494, 2)
        let lx = log(e / 1000)
        let shellD = gas ? 0 : polynomial(t.shellD, lx)
        let shellC = polynomial(t.shellC, lx)
        let meanI: Double, q: Double
        if gas {
            meanI = z1 == 1 ? t.meanExcitationGas[0] : t.meanExcitationGas[1]
            q = 1.35 / pow(e, 0.4)
        } else {
            meanI = t.meanExcitationSolid
            q = 1.5 / pow(e, 0.4) + 45_000 / (z2 * pow(e, 1.6))
        }
        let barkas = (z1d * (0.001 * e) * q) / (0.001 * e + q)
        let y = pow(z1d / 137.036, 2) / beta2
        let bloch = -y * (1.20206 - y * (1.042 - 0.8549 * y + 0.343 * y * y))
        let l = log(1_022_000 * beta2 / (1 - beta2)) - beta2 - shellD - shellC - log(meanI) + barkas + bloch
        return z1d * z1d * z2 / (beta2 * 1961.16) * l
    }

    /// H, He, Li ions: fit between 2 keV/u and `emax`, Bethe above 1.2·emax, linear in between.
    private static func lightIon(_ coef: [Double], z1: Int, target t: SRIMElement, e: Double, emax: Double, gas: Bool) -> Double {
        let emin = 2.0, ehigh = emax * 1.2
        if e > ehigh { return bethe(z1: z1, target: t, e: e, gas: gas) }
        let s = fit(coef, min(max(e, emin), emax))
        if e > emax {
            let sb = bethe(z1: z1, target: t, e: ehigh, gas: gas)
            return s + (sb - s) * (e - emax) / (ehigh - emax)
        }
        if e < emin { return s * (e / emin).squareRoot() }
        return s
    }

    /// High-energy effective charge of heavy ions, Eq. (8).
    private static func highEnergyCharge(_ hi: [Double], _ e: Double) -> Double {
        let d = log10(e) - hi[1]
        let w = d >= 0 ? hi[3] : hi[2]
        return hi[0] + (1 - hi[0]) / (exp(-d / w) + 1) + hi[4] * exp(-abs(1.3 + hi[1] - log10(e)))
    }

    /// Electronic stopping of ion `z1` in pure element `z2`, without phase correction. `ePerU` in keV/u.
    public static func electronicElement(z1: Int, z2: Int, ePerU e: Double, gas: Bool = false,
                                         data: SRIMData = .shared) -> Double {
        let t = data.element(z2)
        if e > 1e7 { return 0 }
        switch z1 {
        case 1: return lightIon(t.proton, z1: 1, target: t, e: e, emax: 1000, gas: gas)
        case 2: return lightIon(t.helium, z1: 2, target: t, e: e, emax: 2000, gas: gas)
        case 3: return lightIon(t.lithium, z1: 3, target: t, e: e, emax: 2000, gas: gas)
        default:
            // Heavy ions: helium stopping scaled with ion and target polynomials in ln E, Eq. (7).
            let emin = 2.0, emax = 30_000.0
            let ec = min(max(e, emin), emax)
            let lne = log(ec)
            let ion = data.element(z1)
            let s = lightIon(t.helium, z1: 2, target: t, e: ec, emax: 2000, gas: gas)
                * polynomial(ion.ionPolynomial, lne) * Double(z1 * z1) / 4 * polynomial(t.targetPolynomial, lne)
            if e < emin { return s * (e / emin).squareRoot() }
            if e > emax {
                let hi = highEnergyCharge(ion.highEnergyCharge, e) * bethe(z1: 2, target: t, e: e, gas: gas)
                let lo = highEnergyCharge(ion.highEnergyCharge, emax) * bethe(z1: 2, target: t, e: emax, gas: gas)
                return s * hi / lo
            }
            return s
        }
    }

    /// SRIM's gas/solid phase factor (0.92 for a gaseous element in a solid, 1/0.92 the other way).
    static func phaseFactor(z2: Int, gas: Bool) -> Double {
        if nobleGases.contains(z2) { return 1 }
        let natural = gasElements.contains(z2)
        if natural == gas { return 1 }
        return natural ? phaseFactorValue : 1 / phaseFactorValue
    }

    /// Correction factor fully applied at low velocity, fading out at high velocity, Eq. (9).
    static func fade(_ factor: Double, ePerU: Double, z1: Int) throws -> Double {
        let c = z1 == 1 ? 7.0 : 4.0
        let x = 1.48 * ((ePerU / 25).squareRoot() - c)
        if x > 709.782712893384 { throw StoppingError.energyTooHigh }
        if x > 700 { return 1 }
        return 1 + (factor - 1) / (1 + exp(x))
    }

    /// Electronic stopping of an ion (z1, m1 in u, energy in keV) in element z2 including the phase
    /// correction and the per-element part of the compound correction.
    public static func electronic(z1: Int, m1: Double, z2: Int, energy: Double, gas: Bool = false,
                                  correction: Double = 1, data: SRIMData = .shared) throws -> Double {
        let e = energy / m1
        let s = electronicElement(z1: z1, z2: z2, ePerU: e, gas: gas, data: data)
        let corr = correction <= 0 ? 1 : correction
        return s * (try fade(phaseFactor(z2: z2, gas: gas) * corr, ePerU: e, z1: z1))
    }

    // MARK: Nuclear stopping

    /// ZBL reduced energy, Eq. (11). Energy in keV.
    public static func reducedEnergy(z1: Int, m1: Double, z2: Int, m2: Double, energy: Double) -> Double {
        energy * 32.53 * m2 / (Double(z1 * z2) * (m1 + m2) * (pow(Double(z1), 0.23) + pow(Double(z2), 0.23)))
    }

    private static func nuclearPrefactor(z1: Int, m1: Double, z2: Int, m2: Double) -> Double {
        8.462 * Double(z1 * z2) * m1 / ((m1 + m2) * (pow(Double(z1), 0.23) + pow(Double(z2), 0.23)))
    }

    /// Nuclear stopping with SRIM-2013's pair coefficients (`SNUC03.dat`), Eqs. (12)–(13).
    public static func nuclear(z1: Int, m1: Double, z2: Int, m2: Double, energy: Double,
                               data: SRIMData = .shared) -> Double {
        let eps = reducedEnergy(z1: z1, m1: m1, z2: z2, m2: m2, energy: energy)
        let sn: Double
        if eps > 30 {
            sn = log(eps) / (2 * eps)
        } else {
            let c = data.nuclearCoefficients(z1, z2) ?? [1.1383, 0.01321, 0.21226, 0.19593]
            sn = 0.5 * log(1 + c[0] * eps) / (eps + c[1] * pow(eps, c[2]) + c[3] * eps.squareRoot())
        }
        return sn * nuclearPrefactor(z1: z1, m1: m1, z2: z2, m2: m2)
    }

    /// ZBL universal nuclear stopping.
    public static func universalNuclear(z1: Int, m1: Double, z2: Int, m2: Double, energy: Double) -> Double {
        let eps = reducedEnergy(z1: z1, m1: m1, z2: z2, m2: m2, energy: energy)
        let sn = eps > 30
            ? log(eps) / (2 * eps)
            : log(1 + 1.1383 * eps) / (2 * (eps + 0.01321 * pow(eps, 0.21226) + 0.19593 * eps.squareRoot()))
        return sn * nuclearPrefactor(z1: z1, m1: m1, z2: z2, m2: m2)
    }
}
