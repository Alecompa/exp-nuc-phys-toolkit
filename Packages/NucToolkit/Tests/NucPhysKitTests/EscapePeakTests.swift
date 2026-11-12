import Foundation
import Testing
@testable import NucPhysKit

@Suite("Escape peaks")
struct EscapePeakTests {
    @Test func pairFractionFromXCOM() {
        #expect(PairProduction.fraction(.hpge, energy: 1000) == 0)
        let ge6 = PairProduction.fraction(.hpge, energy: 6000)
        #expect(abs(ge6 - 0.371) < 0.01)
        #expect(PairProduction.fraction(.bgo, energy: 6000) > ge6)    // higher Z
        #expect(PairProduction.fraction(.hpge, energy: 10000) > ge6)
    }

    @Test func ratiosScaleFromReference() {
        let m = EscapeModel()
        let r6 = m.ratios(at: 6000)
        #expect(abs(r6.single - 0.8) < 1e-9 && abs(r6.double - 0.5) < 1e-9)
        #expect(m.ratios(at: 1000) == (0, 0))
        let r3 = m.ratios(at: 3000)
        #expect(r3.single < 0.4 && r3.single > 0.15)
        var off = m; off.enabled = false
        #expect(off.ratios(at: 6000) == (0, 0))
    }

    @Test func escapePeaksAtExpectedEnergies() throws {
        var setup = SpectrumSetup()
        setup.maximumEnergy = 7000
        setup.continuumRatio = 0
        setup.lines = [.init(energy: 6000, counts: 10000)]
        setup.escape.annihilation = 1
        let bins = try GammaSpectrum.simulate(setup, resolution: .init(kind: .semiconductor, noise: 0.9, collection: 5e-4))
        let w = bins[1].energy - bins[0].energy
        func area(_ lo: Double, _ hi: Double) -> Double { SpectrumRegion.integrate(bins, binWidth: w, lower: lo, upper: hi).escape }
        #expect(abs(area(5470, 5510) - 8000) < 200)    // single escape
        #expect(abs(area(4958, 4998) - 5000) < 150)    // double escape
        #expect(abs(area(500, 522) - 8000) < 200)      // 511 keV
        #expect(abs(bins.reduce(0) { $0 + $1.photopeak } - 10000) < 50)

        setup.lines = [.init(energy: 900, counts: 10000)]
        let low = try GammaSpectrum.simulate(setup, resolution: .init(kind: .semiconductor, noise: 0.9, collection: 5e-4))
        #expect(low.allSatisfy { $0.escape == 0 })
    }

    @Test func oldSetupDecodesWithDefaults() throws {
        let json = #"{"lines":[],"foils":[],"maximumEnergy":5000,"channels":2048,"continuumRatio":1.5,"background":0}"#
        let s = try JSONDecoder().decode(SpectrumSetup.self, from: Data(json.utf8))
        #expect(s.maximumEnergy == 5000 && s.channels == 2048 && s.escape == EscapeModel())
        let round = try JSONDecoder().decode(SpectrumSetup.self, from: JSONEncoder().encode(s))
        #expect(round == s)
    }
}
