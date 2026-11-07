import Foundation
import Testing
@testable import NucPhysKit

private let table = MassTable.ame2020

@Suite("Mass table")
struct MassTableTests {
    @Test func loadsAME2020() {
        #expect(table.nuclides.count > 3500)
        let c12 = table.nuclide(z: 6, a: 12)
        #expect(c12?.massExcess == 0)
        #expect(table.nuclide(named: "13N")?.massExcess == 5345.481)
    }

    @Test(arguments: [
        ("12C", 6, 12), ("C12", 6, 12), ("c-12", 6, 12), ("3He", 2, 3), ("he3", 2, 3),
        ("p", 1, 1), ("d", 1, 2), ("t", 1, 3), ("a", 2, 4), ("α", 2, 4), ("n", 0, 1), ("26Al", 13, 26),
    ])
    func parsesNotation(text: String, z: Int, a: Int) throws {
        let parsed = try #require(NuclideNotation.parse(text))
        #expect(parsed.z == z && parsed.a == a)
    }

    @Test func nitrogenIsNotTheNeutron() {
        #expect(NuclideNotation.parse("14N")! == (7, 14))
        #expect(NuclideNotation.parse("N14")! == (7, 14))
        #expect(NuclideNotation.parse("1n")! == (0, 1))
    }

    @Test func rejectsNonsense() {
        #expect(NuclideNotation.parse("12Xx") == nil)
        #expect(NuclideNotation.parse("") == nil)
        #expect(NuclideNotation.parse("1C") == nil) // A < Z
    }

    @Test func bindingEnergyPerNucleonOf56Fe() throws {
        let fe = try #require(table.nuclide(named: "56Fe"))
        #expect(abs(fe.bindingEnergyPerNucleon - 8790.36) < 0.1) // AME2020: 8790.3563 keV
    }
}

@Suite("Q values (AME2020)")
struct QValueTests {
    @Test(arguments: [
        ("12C(p,g)13N", 1943.49),
        ("d(p,g)3He", 5493.475),
        ("3He(a,g)7Be", 1587.137),
        ("7Li(p,n)7Be", -1644.24),
        ("14N(p,g)15O", 7296.8),
        ("12C(a,g)16O", 7161.92),
        ("13C(a,n)16O", 2215.6),
    ])
    func qValue(notation: String, expected: Double) throws {
        let r = try Reaction(notation: notation)
        #expect(abs(r.qValue - expected) < 0.6, "\(notation): \(r.qValue)")
    }

    @Test func infersResidual() throws {
        let r = try Reaction(notation: "25Mg(p,γ)")
        #expect(r.residual.z == 13 && r.residual.a == 26)
        #expect(r.label == "²⁵Mg(p,γ)²⁶Al")
        #expect(r.plainLabel == "25Mg(p,g)26Al")
    }

    @Test func rejectsNonConserving() {
        #expect(throws: ReactionError.notConserved) { try Reaction(notation: "12C(p,g)14N") }
        #expect(throws: ReactionError.malformed) { try Reaction(notation: "12C p g") }
    }

    @Test func lithiumThreshold() throws {
        // E_th = −Q (m1+m2+m3+m4) / (2 m2) = 1880.35 (non-relativistic part) + Q²/(2 m2) ≈ 1880.56 keV
        let r = try Reaction(notation: "7Li(p,n)7Be")
        let m1 = r.projectile.kinematicMass, m2 = r.target.kinematicMass
        let expected = -r.qValue * (m1 + m2) / m2 + r.qValue * r.qValue / (2 * m2)
        #expect(abs(r.threshold() - expected) < 1e-6)
        #expect(abs(r.threshold() - 1880.56) < 0.05, "\(r.threshold())")
        #expect(try Reaction(notation: "12C(p,g)").threshold() == 0)
    }

    @Test func uncertaintyIsQuadrature() throws {
        let r = try Reaction(notation: "12C(p,g)13N")
        #expect(abs(r.qValueUncertainty - 0.27) < 0.001)
    }
}

@Suite("Two-body kinematics")
struct KinematicsTests {
    /// Momentum and energy must be conserved for every solution.
    @Test(arguments: ["12C(p,p)12C", "7Li(p,n)7Be", "12C(a,g)16O", "1H(12C,12C)1H", "2H(16O,p)17O"])
    func conservation(notation: String) throws {
        let r = try Reaction(notation: notation)
        let k = TwoBodyKinematics(reaction: r, beamEnergy: 5000)
        let eTot = 5000 + k.m1 + k.m2
        let p1 = (5000 * (5000 + 2 * k.m1)).squareRoot()
        for sol in k.curve(samples: 37) {
            let p4 = sol.residualMomentum
            let pz = sol.ejectileMomentum * cos(sol.ejectileAngle) + p4 * cos(sol.residualAngle)
            let px = sol.ejectileMomentum * sin(sol.ejectileAngle) - p4 * sin(sol.residualAngle)
            let e = sol.ejectileEnergy + k.m3 + sol.residualEnergy + k.m4
            #expect(abs(e - eTot) < 1e-3)
            #expect(abs(pz - p1) < 1e-3)
            #expect(abs(px) < 1e-3)
        }
    }

    @Test func elasticEqualMassNonRelativistic() throws {
        // p + p elastic at 1 MeV: E3 = E1 cos²θ, θcm = 2θ
        let r = try Reaction(notation: "p(p,p)")
        let k = TwoBodyKinematics(reaction: r, beamEnergy: 1000)
        let sol = try #require(k.solutions(labAngle: 30.0.radians).first)
        #expect(abs(sol.ejectileEnergy - 750) < 0.5)
        #expect(abs(sol.thetaCM.degrees - 60) < 0.05)
    }

    @Test func inverseKinematicsHasTwoBranches() throws {
        // 12C on a hydrogen target: carbon ejectile limited to θmax ≈ asin(m_p/m_C) = 4.816°
        let r = try Reaction(notation: "1H(12C,12C)1H")
        let k = TwoBodyKinematics(reaction: r, beamEnergy: 24000)
        let maxAngle = try #require(k.maxEjectileAngle)
        #expect(abs(maxAngle.degrees - 4.816) < 0.005)
        #expect(k.solutions(labAngle: 3.0.radians).count == 2)
        #expect(k.solutions(labAngle: 6.0.radians).isEmpty)
    }

    @Test func jacobianMatchesFiniteDifference() throws {
        let r = try Reaction(notation: "2H(16O,p)17O")
        let k = TwoBodyKinematics(reaction: r, beamEnergy: 50000)
        for cm in stride(from: 10.0, through: 170.0, by: 20.0) {
            let h = 1e-4
            let s = try #require(k.solution(cmAngle: cm.radians))
            let a = try #require(k.solution(cmAngle: cm.radians - h))
            let b = try #require(k.solution(cmAngle: cm.radians + h))
            let numeric = abs((cos(b.thetaCM) - cos(a.thetaCM)) / (cos(b.ejectileAngle) - cos(a.ejectileAngle)))
            #expect(abs(s.jacobian / numeric - 1) < 1e-4, "θcm=\(cm)")
        }
    }

    @Test func captureGammaDopplerShift() throws {
        // Capture γ: E_γ(θ) = E_γ0 · sqrt(1-β²)/(1-β cosθ) relative to the CM energy
        let r = try Reaction(notation: "12C(p,g)13N")
        let k = TwoBodyKinematics(reaction: r, beamEnergy: 400)
        let at0 = try #require(k.solutions(labAngle: 0).first)
        let at90 = try #require(k.solutions(labAngle: .pi / 2).first)
        let at180 = try #require(k.solutions(labAngle: .pi).first)
        #expect(at0.ejectileEnergy > at90.ejectileEnergy && at90.ejectileEnergy > at180.ejectileEnergy)
        let e0 = k.pStar
        #expect(abs(at0.ejectileEnergy - e0 / (k.gamma * (1 - k.beta))) < 1e-6)
        // E_γ ≈ Q + E_cm for capture to the ground state (minus tiny recoil)
        #expect(abs(e0 - (r.qValue + k.centerOfMassEnergy)) < 1)
    }

    @Test func compoundExcitation() throws {
        // 25Mg(p,γ)26Al at E_p = 317 keV → E_x ≈ S_p + E_cm = 6306.3 + 304.7 ≈ 6611 keV
        let r = try Reaction(notation: "25Mg(p,g)")
        let ex = try #require(r.compoundExcitation(beamEnergy: 317))
        #expect(abs(ex - (r.qValue + 317 * 25 / 26.0)) < 2)
    }
}

@Test func elasticScatteringHasExactZeroQ() throws {
    let r = try Reaction(notation: "1H(12C,12C)")
    #expect(r.qValue == 0)
    #expect(r.qValueUncertainty == 0)
}
