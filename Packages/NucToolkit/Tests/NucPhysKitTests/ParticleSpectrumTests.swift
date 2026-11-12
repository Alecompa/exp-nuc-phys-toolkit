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
}
