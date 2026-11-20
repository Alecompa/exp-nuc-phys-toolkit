import Foundation
import Testing
@testable import NucPhysKit

@Suite("Particle spectrum")
struct ParticleSpectrumTests {
    let reaction = try! Reaction(notation: "7Li(p,a)4He")

    @Test func reactionGroupMatchesKinematics() throws {
        var setup = ParticleDetectorSetup()
        setup.angle = 135; setup.showElastic = false
        let groups = ParticleSpectrum.groups(reaction: reaction, beamEnergy: 1400, residualExcitation: 0,
                                             material: .element(3), setup: setup)
        let alpha = try #require(groups.first)
        let k = TwoBodyKinematics(reaction: reaction, beamEnergy: 1400)
        let expected = try #require(k.solutions(labAngle: 135 * .pi / 180).first).ejectileEnergy
        #expect(groups.count == 1)
        #expect(alpha.particle == "α")
        #expect(abs(alpha.emitted - expected) < 1e-6)
        #expect(alpha.detected == alpha.emitted)        // no foils
        #expect(alpha.fwhm > 15)                         // resolution plus kinematic spread over the opening
    }

    @Test func aluminiumFoilStopsElasticProtonsButPassesAlphas() throws {
        var setup = ParticleDetectorSetup()
        setup.angle = 135
        setup.foils = [DetectorFoil(material: .element(13), thickness: 1.5e5)]   // 15 µm Al
        let groups = ParticleSpectrum.groups(reaction: reaction, beamEnergy: 1400, residualExcitation: 0,
                                             material: .element(3), setup: setup)
        let alpha = try #require(groups.first { $0.kind == .reaction })
        let proton = try #require(groups.first { $0.kind == .elastic })
        #expect(proton.detected == nil && proton.stoppedIn == 0)
        let e = try #require(alpha.detected)
        #expect(e > 0 && e < alpha.emitted - 1000)
        #expect(alpha.fwhm > setup.resolution)          // foil straggling widens the peak
    }

    @Test func captureHasOnlyElasticGroups() {
        let capture = try! Reaction(notation: "12C(p,g)13N")
        let groups = ParticleSpectrum.groups(reaction: capture, beamEnergy: 400, residualExcitation: 0,
                                             material: .element(6), setup: ParticleDetectorSetup())
        #expect(groups.allSatisfy { $0.kind == .elastic })
        #expect(groups.count == 1)
    }

    @Test func naturalCopperIsAnAbundanceWeightedPair() throws {
        // p on natural Cu at 2000 keV, 135°: ⁶³Cu 1893.491 keV, ⁶⁵Cu 1896.684 keV (independent relativistic
        // two-body calculation, AME2020 masses); NUBASE2020 abundances 69.15 % / 30.85 %.
        var setup = ParticleDetectorSetup(); setup.angle = 135; setup.resolution = 15
        let capture = try Reaction(notation: "63Cu(p,g)64Zn")
        let groups = ParticleSpectrum.groups(reaction: capture, beamEnergy: 2000, residualExcitation: 0,
                                             material: .element(29), setup: setup)
        let cu = try #require(groups.first { $0.kind == .elastic })
        #expect(groups.filter { $0.kind == .elastic }.count == 1)      // 3.2 keV apart < FWHM/2: merged
        #expect(abs(cu.emitted - 1894.4761) < 2e-3)
        #expect(cu.origin == "elastic on Cu")
        // Resolved when the detector is good enough.
        setup.resolution = 2
        let split = ParticleSpectrum.groups(reaction: capture, beamEnergy: 2000, residualExcitation: 0,
                                            material: .element(29), setup: setup).filter { $0.kind == .elastic }
        #expect(split.count == 2)
        #expect(split.contains { abs($0.emitted - 1893.4910) < 2e-3 })
    }

    @Test func heavyBeamOnHydrogenKeepsBothBranches() throws {
        var setup = ParticleDetectorSetup(); setup.angle = 3; setup.halfOpening = 0
        let r = try Reaction(notation: "p(12C,g)13N")
        let elastic = ParticleSpectrum.groups(reaction: r, beamEnergy: 12000, residualExcitation: 0,
                                              material: .element(1), setup: setup).filter { $0.kind == .elastic }
        #expect(elastic.count == 2)                                   // fast and slow ¹²C below θ_max = 4.8°
        #expect(elastic.allSatisfy { ($0.rutherford ?? 0) > 0 })
    }

    @Test func elasticCarriesRutherfordCrossSection() throws {
        var setup = ParticleDetectorSetup(); setup.angle = 170
        let r = try Reaction(notation: "197Au(a,g)201Tl")
        let g = try #require(ParticleSpectrum.groups(reaction: r, beamEnergy: 2000, residualExcitation: 0,
                                                     material: .element(79), setup: setup).first { $0.kind == .elastic })
        let au = try #require(MassTable.ame2020.nuclide(named: "197Au"))
        let alpha = try #require(MassTable.ame2020.nuclide(named: "a"))
        let ref = try #require(RutherfordScattering(projectile: alpha, target: au, beamEnergy: 2000).at(labAngle: 170 * .pi / 180).first)
        #expect(abs((g.rutherford ?? 0) / ref.crossSectionLab - 1) < 1e-12)
    }

    @Test func enrichedIsotopeNextToNaturalElementKeepsItsShare() throws {
        // 1 ¹³C + 1 natural C: ¹³C share = 0.5 + 0.5 × natural ¹³C abundance.
        var setup = ParticleDetectorSetup(); setup.angle = 150; setup.resolution = 1; setup.halfOpening = 0
        let mix = StoppingTarget.formula(try ChemicalFormula("[13C]C"), density: 2)
        let r = try Reaction(notation: "13C(p,g)14N")
        let groups = ParticleSpectrum.groups(reaction: r, beamEnergy: 1000, residualExcitation: 0, material: mix, setup: setup)
            .filter { $0.kind == .elastic }
        #expect(groups.count == 2)
        let natural13 = try #require(Nubase.nubase2020.groundState(z: 6, a: 13)?.abundance) / 100
        let c13 = try #require(groups.first { $0.origin.contains("¹³C") })
        let c12 = try #require(groups.first { $0.origin.contains("¹²C") })
        // Same Rutherford dσ/dΩ up to kinematics; compare the abundance-weighted ratio within 2 %.
        let ratio = (c13.rutherford ?? 0) / (c12.rutherford ?? 1)
        #expect(abs(ratio / ((0.5 + 0.5 * natural13) / (0.5 * (1 - natural13))) - 1) < 0.02)
    }
}
