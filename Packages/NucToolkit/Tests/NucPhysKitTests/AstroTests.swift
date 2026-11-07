import Foundation
import Testing
@testable import NucPhysKit

private let table = MassTable.ame2020
private func channel(_ a: String, _ b: String) -> ChargedChannel {
    ChargedChannel(projectile: table.nuclide(named: a)!, target: table.nuclide(named: b)!)
}
private func close(_ x: Double, _ y: Double, rel: Double) -> Bool { abs(x - y) <= rel * abs(y) }

@Suite("Coulomb functions")
struct CoulombTests {
    /// Reference values from mpmath coulombf/coulombg (50 digits).
    @Test(arguments: [
        (0, 0.0, 1.0, 0.0, 0.0),
        (1, 0.0, 0.5, -2.30258509299405, -0.8),
        (0, 1.0, 1.0, -1.44125927703603, -0.592119994155462),
        (0, 5.0, 2.0, -12.8431267343313, -3.70170231063439),
        (2, 3.0, 1.5, -9.39901195189308, -3.18348617944423),
        (0, 20.0, 0.8, -101.452967751284, -5.36008211221574),
        (1, 40.0, 3.0, -187.300866632145, -15.0084101419594),
        (0, 2.0, 15.0, 2.55362787145246, -0.0896355670111964),
        (3, 0.5, 0.3, -15.4036821922585, -3.0318434547527),
    ])
    func matchesMpmath(l: Int, eta: Double, rho: Double, lnP: Double, shift: Double) {
        let r = CoulombFunctions.penetrability(l: l, eta: eta, rho: rho)
        #expect(abs(r.lnP - lnP) < 2e-4 * max(1, abs(lnP) / 10), "lnP \(r.lnP) vs \(lnP)")
        #expect(abs(r.shift - shift) < 2e-4 * max(1, abs(shift)), "S \(r.shift) vs \(shift)")
    }
}

@Suite("Nuclear astrophysics")
struct AstroTests {
    @Test func gamowPeakMatchesTextbookFormula() {
        let c = channel("p", "12C")
        let mu = c.reducedMass
        for t9 in [0.02, 0.1, 1.0] {
            let w = c.gamowWindow(t9: t9)
            let e0 = 122.0 * pow(36 * mu * t9 * t9, 1.0 / 3)              // keV
            let delta = 236.8 * pow(36 * mu * pow(t9, 5), 1.0 / 6)        // keV
            #expect(close(w.peak, e0, rel: 1e-3))
            #expect(close(w.width, delta, rel: 1e-3))
        }
    }

    @Test func constantSFactorRateMatchesAnalyticApproximation() {
        // Iliadis, Nuclear Physics of Stars, eq. 3.84 with S_eff = S₀(1 + 5/(12τ)).
        let c = channel("p", "12C")
        let mu = c.reducedMass
        let s0 = 1.5                                                     // keV b
        for t9 in [0.02, 0.05] {
            let tau = 4.2487 * pow(36 * mu / t9, 1.0 / 3)
            let seff = s0 * 1e-3 * (1 + 5 / (12 * tau))
            let expected = 4.3392e8 / 6 / mu * seff * tau * tau * exp(-tau)
            let rate = c.rate(sFactor: SFactorModel(s0: s0), t9: t9)
            #expect(close(rate, expected, rel: 1e-3), "T9=\(t9): \(rate) vs \(expected)")
        }
    }

    @Test func narrowResonanceRateMatchesNumericalConstant() {
        let c = channel("p", "27Al")
        let r = NarrowResonance(energy: 200, strength: 1)
        let t9 = 0.5, mu = c.reducedMass
        let expected = 1.5399e11 / pow(mu * t9, 1.5) * 1e-6 * exp(-11.605 * 0.2 / t9)
        #expect(close(c.narrowResonanceRate(r, t9: t9), expected, rel: 1e-3))
    }

    @Test func thickTargetYieldRoundTrips() {
        let c = channel("p", "27Al")
        let lam = c.deBroglieHalfSquared(energy: 1000)
        #expect(close(lam, 4.1255e-24 / (c.reducedMass * 1.0), rel: 1e-3))
        let y = c.thickTargetYield(resonanceEnergy: 300, strength: 0.01, effectiveStopping: 8e-14)
        #expect(close(c.resonanceStrength(resonanceEnergy: 300, yield: y, effectiveStopping: 8e-14), 0.01, rel: 1e-12))
    }

    @Test func sFactorAndScreening() {
        let c = channel("p", "12C")
        let sigma = c.crossSection(sFactor: 1.5, energy: 100)
        #expect(close(c.sFactor(crossSection: sigma, energy: 100), 1.5, rel: 1e-12))
        // f = exp(πη U_e/E): small for U_e ≪ E.
        let f = c.screeningFactor(energy: 100, potential: 350)
        #expect(close(f, exp(Double.pi * c.sommerfeld(100) * 0.35 / 100), rel: 1e-12))
        #expect(f > 1 && f < 1.05)
    }

    @Test func tableInterpolatesLogLinearly() throws {
        let points = try SFactorModel.parseTable("E,S\n100, 2\n# c\n300; 8\n200\t4")
        let m = SFactorModel(kind: .table, table: points)
        #expect(close(m.s(at: 150), 2 * 2.0.squareRoot(), rel: 1e-12))
        #expect(m.s(at: 10) == 2 && m.s(at: 1000) == 8)
        #expect(throws: SFactorModel.ParseError.self) { try SFactorModel.parseTable("1 2\nfoo bar") }
    }

    @Test func wignerLimitAndPenetrability() {
        let c = channel("p", "12C")
        // 3ħ²/(2μa²) for a = 4 fm.
        let expected = 3 * pow(197.3269804, 2) / (2 * c.reducedMassEnergy / 1000 * 16) * 1000
        #expect(close(c.wignerLimit(radius: 4), expected, rel: 1e-9))
        // Penetrability grows steeply with energy below the barrier.
        let p1 = c.penetrability(l: 0, energy: 100, radius: 4).penetrability
        let p2 = c.penetrability(l: 0, energy: 400, radius: 4).penetrability
        #expect(p2 > 10 * p1)
    }

    @Test func rutherfordEqualMassesNonRelativistic() {
        let p = table.nuclide(named: "p")!
        let r = RutherfordScattering(projectile: p, target: p, beamEnergy: 1000)
        let theta = 30.0 * .pi / 180
        let s = r.at(labAngle: theta)
        #expect(s.count == 1)
        #expect(close(s[0].thetaCM, 2 * theta, rel: 1e-3))
        #expect(close(s[0].crossSectionLab, 4 * cos(theta) * s[0].crossSectionCM, rel: 2e-3))
        // α + ¹⁹⁷Au at 90° CM, E_cm ≈ 1960 keV.
        let au = RutherfordScattering(projectile: table.nuclide(named: "4He")!, target: table.nuclide(named: "197Au")!, beamEnergy: 2000)
        let a = 158 * 1439.964 / (4 * au.kinematics.centerOfMassEnergy)
        #expect(close(au.crossSectionCM(thetaCM: .pi / 2), a * a * 4 * 1e-2, rel: 1e-5))
    }
}
