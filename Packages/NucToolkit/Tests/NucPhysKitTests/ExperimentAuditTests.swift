import Foundation
import Testing
@testable import NucPhysKit

@Suite("Experiment calculation cross-checks")
struct ExperimentAuditTests {
    @Test func enrichedAndMixedIsotopeTargets() throws {
        let enriched = StoppingTarget.formula(try ChemicalFormula("Ta2[17O]5"), density: 8.2)
        #expect(abs(enriched.activeFraction(z: 8, a: 17, abundance: 0.01) - 5.0 / 7) < 1e-12)
        #expect(enriched.activeFraction(z: 8, a: 16, abundance: 1) == 0)
        let mixed = StoppingTarget.formula(try ChemicalFormula("[16O][17O]O2"), density: 1)
        #expect(abs(mixed.activeFraction(z: 8, a: 17, abundance: 0.1) - 0.3) < 1e-12)
        #expect(mixed.formulaText().contains("[16O]"))
        let decoded = try JSONDecoder().decode(StoppingTarget.self, from: JSONEncoder().encode(mixed))
        #expect(decoded == mixed)
        // Old untagged records still decode. Natural oxygen uses the supplied isotope abundance.
        let legacy = Data("{\"z\":8,\"stoichiometry\":1,\"mass\":15.999}".utf8)
        let component = try JSONDecoder().decode(StoppingTarget.Component.self, from: legacy)
        #expect(component.massNumber == nil && component.isotopeMassNumber == nil)
    }

    @Test func tiltedThinTargetAndDimensionalCrossChecks() throws {
        let target = StoppingTarget.formula(try ChemicalFormula("[12C]"), density: 2)
        let normal = try #require(target.activeArealDensity(z: 6, a: 12, abundance: 1, thickness: 1000, angle: 0))
        let tilted = try #require(target.activeArealDensity(z: 6, a: 12, abundance: 1, thickness: 1000, angle: 60))
        #expect(abs(tilted / normal - 2) < 1e-12)
        #expect(abs(normal / (2e-5 / 12 * 6.022e23) - 1) < 1e-6)
        let y = ChargedChannel.thinTargetYield(crossSection: 0.1, arealDensity: normal)
        #expect(abs(y / normal - 1e-25) < 1e-38)
        // 1 µA of q=2 ions at 1000 keV deposits 0.5 W if all energy is absorbed.
        let rate = Beam.particlesPerSecond(current: 1e-6, chargeState: 2)
        #expect(abs(Beam.power(particlesPerSecond: rate, energy: 1000) - 0.5) < 1e-12)
        #expect(target.activeArealDensity(z: 6, a: 12, abundance: 1, thickness: 1000, angle: 90) == nil)
        // Independent compound table, not a re-sum of the elemental inputs:
        // https://physics.nist.gov/PhysRefData/XrayMassCoef/ComTab/water.html
        let water = StoppingTarget.formula(try ChemicalFormula("H2O"), density: 1)
        #expect(abs(try PhotonAttenuation.massCoefficient(material: water, energy: 1000) - 0.07072) < 0.00005)
    }

    @Test func comptonAgainstIndependentAngularQuadrature() throws {
        // Reference: Python midpoint integration over 10^6 uniform cos(theta) intervals,
        // weighting k²(k+1/k−sin²theta). Production integrates in deposited energy instead.
        let references = [(100.0, 0.11768590492544741), (300.0, 0.336624955465574), (600.0, 0.6535815585810707)]
        var setup = SpectrumSetup()
        setup.lines = [.init(energy: 1000, counts: 1000)]
        setup.maximumEnergy = 1200; setup.channels = 8192; setup.continuumRatio = 1
        let narrow = ResolutionModel(kind: .semiconductor, noise: 0.001, fano: 0, collection: 0)
        let bins = try GammaSpectrum.simulate(setup, resolution: narrow)
        for (cut, fraction) in references {
            let area = SpectrumRegion.integrate(bins, binWidth: 1200.0 / 8192, lower: 0, upper: cut)
            #expect(abs(area.compton / 1000 - fraction) < 0.0003)
        }
    }

    @Test func roiPartialChannelsAndCountingStatistics() {
        let bins = [SpectrumBin(id: 0, energy: 0.5, photopeak: 10, compton: 2, background: 4),
                    SpectrumBin(id: 1, energy: 1.5, photopeak: 20, compton: 6, background: 8)]
        let roi = SpectrumRegion.integrate(bins, binWidth: 1, lower: 0.5, upper: 1.25)
        #expect(roi.photopeak == 10 && roi.compton == 2.5 && roi.background == 4)
        #expect(SpectrumRegion.integrate(bins, binWidth: 1, lower: 2, upper: 1).total == 0)
        let t = CountingStatistics.time(signal: 2, background: 3, relativeUncertainty: 0.1)
        #expect(abs(t - 200) < 1e-10)
        #expect(abs(CountingStatistics.relativeUncertainty(signal: 2, background: 3, time: t) - 0.1) < 1e-12)
    }

    @Test func yieldIntegrationRejectsInvalidStepCounts() throws {
        let channel = ChargedChannel.entrance(try Reaction(notation: "12C(p,g)"))
        #expect(channel.targetYield(sFactor: .init(s0: 1), entranceEnergy: 400, exitEnergy: 300, steps: 0, stopping: { _ in 1 }) == 0)
        #expect(channel.effectiveEnergy(sFactor: .init(s0: 1), entranceEnergy: 400, exitEnergy: 300, steps: -1, stopping: { _ in 1 }) == nil)
    }

    @Test func plotEnvelopePreservesNarrowPeaks() {
        let bins = (0..<8192).map { i in
            SpectrumBin(id: i, energy: Double(i), photopeak: i == 2345 ? 1000 : 0,
                        compton: i == 6511 ? 200 : 1, background: 0)
        }
        let plot = SpectrumPlotSampling.envelope(bins)
        #expect(plot.count <= 1200)
        #expect(plot.contains { $0.id == 2345 && $0.photopeak == 1000 })
        #expect(plot.contains { $0.id == 6511 && $0.compton == 200 })
        #expect(plot.first?.id == 0 && plot.last?.id == 8191)
        #expect(zip(plot, plot.dropFirst()).allSatisfy { $0.energy < $1.energy })
    }
}
