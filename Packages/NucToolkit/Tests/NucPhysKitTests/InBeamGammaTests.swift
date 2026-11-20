import Foundation
import Testing
@testable import NucPhysKit

/// Reference values from an independent Python evaluation of the same relativistic formulas with the bundled
/// AME2020 masses (ion mass = atomic mass − Z mₑ): E*γ = (s − M₃²)/(2√s), E_lab = E*γ / [γ(1 − β cos θ)].
@Suite("In-beam γ rays: recoil, Doppler, contaminants")
struct InBeamGammaTests {
    @Test func capturePrimaryIncludesRecoilAndDoppler() throws {
        let r = try Reaction(notation: "d(p,g)3He")
        var geo = GammaGeometry()
        for (angle, expected) in [(0.0, 5810.48914), (90.0, 5753.91730), (55.0, 5786.23010)] {
            geo.angle = angle
            let line = try #require(InBeamGamma.primary(r, beamEnergy: 400, geometry: geo))
            #expect(abs(line.restEnergy - 5754.19004) < 1e-3)        // E_cm + Q − recoil (≈ 5.9 keV)
            #expect(abs(line.shiftedEnergy - expected) < 1e-3)
            #expect(line.fractionInFlight == 1)
        }
    }

    @Test func residualLevelBoxWidthFromRecoilVelocity() throws {
        // ¹⁵N(p,α)¹²C(4439.82) at Ep = 400 keV: β*₄ = 0.0063470, so the 4438.94 keV γ spreads by ±28.17 keV.
        let r = try Reaction(notation: "15N(p,a)12C")
        var geo = GammaGeometry(); geo.angle = 90
        let line = try #require(InBeamGamma.residualLevel(r, beamEnergy: 400, level: 4439.82, transition: 4438.94,
                                                          meanLife: 61e-15, geometry: geo))
        #expect(abs(line.halfWidth - 28.1738) < 1e-3)
        #expect(abs(line.shiftedEnergy - 4438.94) < 1e-6)              // cos 90° = 0
        #expect(line.fractionInFlight > 0.99)
    }

    @Test func longLivedLevelIsMostlyAtRest() {
        // ¹⁶O 6130 keV, T½ = 18.4 ps, recoil stopping time 0.5 ps.
        let f = GammaGeometry().fractionInFlight(meanLife: 18.4e-12 / log(2.0))
        #expect(abs(f - 0.0186592) < 1e-6)
        var gas = GammaGeometry(); gas.recoilsStop = false
        #expect(gas.fractionInFlight(meanLife: 1) == 1)
    }

    @Test func dopplerBoxKeepsAreaCentroidAndVariance() throws {
        let res = ResolutionModel.presets[0].model
        var bins = [Double](repeating: 0, count: 4000)
        let h = 30.0, e = 2000.0
        try GammaSpectrum.deposit(energy: e, area: 1000, width: 1, resolution: res, halfWidth: h, into: &bins)
        let total = bins.reduce(0, +)
        let mean = bins.enumerated().reduce(0) { $0 + (Double($1.offset) + 0.5) * $1.element } / total
        let variance = bins.enumerated().reduce(0) { $0 + pow(Double($1.offset) + 0.5 - mean, 2) * $1.element } / total
        let sigma = res.fwhm(at: e) / 2.3548200450309493
        #expect(abs(total - 1000) < 1e-6)
        #expect(abs(mean - e) < 1e-6)
        // Box variance h²/3 plus Gaussian σ² plus the channel width²/12.
        #expect(abs(variance - (h * h / 3 + sigma * sigma + 1.0 / 12)) < 1e-3)
    }

    @Test func libraryReactionsParseAndRespectThresholds() throws {
        for s in BackgroundLibrary.beamInduced { #expect(s.reaction != nil, "\(s.id)") }
        let p = try #require(MassTable.ame2020.nuclide(named: "p"))
        let alpha = try #require(MassTable.ame2020.nuclide(named: "a"))
        let f19 = try #require(BackgroundLibrary.source(id: "19F(p,ag)"))
        #expect(f19.applies(projectile: p, beamEnergy: 300))
        #expect(!f19.applies(projectile: alpha, beamEnergy: 300))
        // ¹²C(α,α′) to 4.44 MeV is closed at 3 MeV and open at 8 MeV.
        let c12 = try #require(BackgroundLibrary.source(id: "12C(a,a'g)"))
        #expect(!c12.applies(projectile: alpha, beamEnergy: 3000))
        #expect(c12.applies(projectile: alpha, beamEnergy: 8000))
    }

    @Test func oldSavedLinesDecodeWithoutDopplerWidth() throws {
        let json = #"{"id":"6F3A9A63-7C3B-4A41-9E36-0E1B5C1C2D11","name":"x","energy":1000,"counts":5,"enabled":true}"#
        let line = try JSONDecoder().decode(SpectrumLine.self, from: Data(json.utf8))
        #expect(line.dopplerHalfWidth == 0)
    }
}
