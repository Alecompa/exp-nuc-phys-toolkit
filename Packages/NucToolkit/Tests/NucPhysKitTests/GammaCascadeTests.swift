import Foundation
import Testing
@testable import NucPhysKit

@Suite("γ cascade")
struct GammaCascadeTests {
    /// Toy scheme: 3000 → 0 (25), 3000 → 1000 (75); 1000 → 0 (100); 2000 has no γ data.
    let scheme = LevelScheme(
        levels: [
            Level(index: 0, energy: 0, energyUncertainty: nil, spinParity: "0+", halfLife: "STABLE", halfLifeSeconds: nil),
            Level(index: 1, energy: 1000, energyUncertainty: nil, spinParity: "2+", halfLife: "", halfLifeSeconds: nil),
            Level(index: 2, energy: 2000, energyUncertainty: nil, spinParity: "4+", halfLife: "", halfLifeSeconds: nil),
            Level(index: 3, energy: 3000, energyUncertainty: nil, spinParity: "2+", halfLife: "", halfLifeSeconds: nil),
        ],
        gammas: [
            GammaTransition(initialLevel: 3000, finalLevel: 0, initialSpinParity: "2+", finalSpinParity: "0+",
                            energy: 3000, energyUncertainty: nil, relativeIntensity: 25, multipolarity: "E2"),
            GammaTransition(initialLevel: 3000, finalLevel: 1000, initialSpinParity: "2+", finalSpinParity: "2+",
                            energy: 2000, energyUncertainty: nil, relativeIntensity: 75, multipolarity: "M1"),
            GammaTransition(initialLevel: 1000, finalLevel: 0, initialSpinParity: "2+", finalSpinParity: "0+",
                            energy: 1000, energyUncertainty: nil, relativeIntensity: 100, multipolarity: "E2"),
        ],
        reference: "test", retrieved: Date())

    @Test func branchingFeedsLowerLevels() throws {
        let r = GammaCascade.from(excitation: 3001, scheme: scheme)
        #expect(r.startLevel == 3000)
        #expect(r.unresolved == 0)
        let byEnergy = Dictionary(uniqueKeysWithValues: r.lines.map { ($0.energy, $0.intensity) })
        #expect(abs(byEnergy[3000]! - 0.25) < 1e-12)
        #expect(abs(byEnergy[2000]! - 0.75) < 1e-12)
        #expect(abs(byEnergy[1000]! - 0.75) < 1e-12)
    }

    @Test func noMatchingLevelOrNoData() {
        #expect(GammaCascade.from(excitation: 1500, scheme: scheme).startLevel == nil)
        let r = GammaCascade.from(excitation: 2000, scheme: scheme)
        #expect(r.lines.isEmpty && r.unresolved == 1)
        #expect(GammaCascade.from(excitation: 0, scheme: scheme).lines.isEmpty)
    }

    @Test func missingFinalLevelIsReportedNotDropped() {
        // 3000 → 1500 (a level absent from the list) must show up as unresolved flux.
        var gammas = scheme.gammas
        gammas.append(GammaTransition(initialLevel: 3000, finalLevel: 1500, initialSpinParity: "2+", finalSpinParity: "",
                                      energy: 1500, energyUncertainty: nil, relativeIntensity: 100, multipolarity: ""))
        gammas.append(GammaTransition(initialLevel: 3000, finalLevel: 500, initialSpinParity: "2+", finalSpinParity: "",
                                      energy: 2500, energyUncertainty: nil, relativeIntensity: nil, multipolarity: ""))
        let s = LevelScheme(levels: scheme.levels, gammas: gammas, reference: "test", retrieved: Date())
        let r = GammaCascade.from(excitation: 3000, scheme: s)
        #expect(abs(r.unresolved - 0.5) < 1e-12)          // 100 of 25 + 75 + 100
        #expect(r.withoutIntensity == 1)
    }

    @Test func feedingDelaysShortLivedLevels() {
        // 3000 (τ = 10 ps) feeds 1000 (τ = 50 fs) with 75 %: the 1000 keV γ comes ≈ 10 ps after the reaction.
        let r = GammaCascade.from(excitation: 3000, scheme: scheme)
        let tau: [Double: Double] = [3000: 10e-12, 1000: 50e-15]
        let t = GammaCascade.meanDecayTimes(r.lines) { tau[$0] }
        #expect(abs(t[3000]! - 10e-12) < 1e-20)
        #expect(abs(t[1000]! - (10e-12 + 50e-15)) < 1e-20)
    }
}
