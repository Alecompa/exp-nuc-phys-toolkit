import Foundation
import Testing
@testable import NucPhysKit

private func close(_ x: Double, _ y: Double, rel: Double) -> Bool { abs(x - y) <= rel * abs(y) }

@Suite("NUBASE2020 and decay data")
struct NuclearDataTests {
    let nubase = Nubase.nubase2020

    @Test func halfLivesSpinsAndAbundances() throws {
        let co = try #require(nubase.state(named: "60Co"))
        #expect(close(co.halfLife!, 5.2714 * HalfLifeFormat.year, rel: 1e-6))
        #expect(co.spinParity == "5+")
        #expect(co.decayModes.first?.name == "β⁻")
        let al = try #require(nubase.groundState(z: 13, a: 27))
        #expect(al.isStable && al.abundance == 100)
        let alm = try #require(nubase.state(named: "26mAl"))
        #expect(close(alm.excitation, 228.306, rel: 1e-6) && alm.label == "²⁶ᵐAl")
        #expect(nubase.state(named: "54Mn")?.state == 0)          // "Mn" is not an isomer mark
        let ho = try #require(nubase.state(named: "166mHo"))
        #expect(ho.state == 1 && ho.halfLife! > 1000 * HalfLifeFormat.year)
        #expect(nubase.states.count > 5000)
    }

    @Test func decayModeParsing() {
        let m = DecayMode(raw: "EC+B+=3.4 4")
        #expect(m.code == "EC+B+" && m.branch == 3.4 && m.uncertainty == "4")
        #expect(m.name == "ε+β⁺")
        #expect(DecayMode(raw: "IT~100").text == "IT ≈ 100 %")
    }

    @Test func exponentialDecay() {
        let t = 100.0
        #expect(close(RadioactiveDecay.activity(initial: 1000, elapsed: t, halfLife: t), 500, rel: 1e-12))
        #expect(close(RadioactiveDecay.time(toFraction: 0.25, halfLife: t), 200, rel: 1e-12))
        let n = RadioactiveDecay.atoms(activity: 1000, halfLife: t)
        #expect(close(RadioactiveDecay.activity(atoms: n, halfLife: t), 1000, rel: 1e-12))
        // All decays of a source: A₀/λ.
        #expect(close(RadioactiveDecay.decays(initial: 1000, from: 0, to: 1e6, halfLife: t), n, rel: 1e-9))
    }

    @Test func calibrationSourcesAndKerma() throws {
        let cs = try #require(CalibrationSources.source(named: "137Cs"))
        let line = try #require(cs.lines.first { abs($0.energy - 661.657) < 0.01 })
        #expect(close(line.intensity, 85.1, rel: 1e-3))
        // Air-kerma rate constants (µGy m² MBq⁻¹ h⁻¹): ¹³⁷Cs 0.077, ⁶⁰Co 0.306 (e.g. Ninkovic et al., HPJ 2005).
        #expect(close(AirKerma.rateConstant(lines: cs.lines), 0.077, rel: 0.03))
        let co = try #require(CalibrationSources.source(named: "60Co"))
        #expect(close(AirKerma.rateConstant(lines: co.lines), 0.306, rel: 0.03))
        #expect(CalibrationSources.all.count >= 18)
        #expect(close(AirKerma.massEnergyAbsorption(energy: 1000), 0.02789, rel: 1e-9))
    }

    @Test func liveChartParsing() throws {
        func fixture(_ n: String) throws -> String {
            try String(contentsOf: Bundle.module.url(forResource: n, withExtension: "csv")!, encoding: .utf8)
        }
        let s = try LiveChartClient.parse(levels: try fixture("livechart_28si_levels"), gammas: try fixture("livechart_28si_gammas"))
        #expect(s.levels.count > 200)
        #expect(s.levels[1].energy == 1779.03 && s.levels[1].spinParity == "2+")
        #expect(s.gammas.contains { $0.energy == 1778.969 && $0.multipolarity == "E2" })
        #expect(s.reference.contains("Basunia"))
        #expect(LiveChartClient.apiName(z: 14, a: 28) == "28si")
    }
}

@Suite("Run planning and detectors")
struct RunPlanningTests {
    @Test func beamUnits() {
        #expect(close(Beam.particlesPerSecond(current: 1e-6, chargeState: 1), 6.241_509_074e12, rel: 1e-9))
        #expect(close(Beam.particles(charge: 1, chargeState: 2), 3.120_754_537e18, rel: 1e-9))
        #expect(close(Beam.power(particlesPerSecond: 6.241_509_074e12, energy: 400), 0.4, rel: 1e-9))   // 1 µA × 400 kV
    }

    @Test func countingTime() {
        #expect(close(CountingStatistics.time(signal: 1, background: 0, relativeUncertainty: 0.01), 1e4, rel: 1e-12))
        let t = CountingStatistics.time(signal: 0.1, background: 0.5, relativeUncertainty: 0.05)
        #expect(close(CountingStatistics.relativeUncertainty(signal: 0.1, background: 0.5, time: t), 0.05, rel: 1e-12))
    }

    @Test func thickTargetYieldReducesToThinTarget() {
        let c = ChargedChannel(projectile: MassTable.ame2020.nuclide(named: "p")!, target: MassTable.ame2020.nuclide(named: "14N")!)
        let model = SFactorModel(s0: 1.6)
        let eps = 1e-14                            // eV cm² per nucleus, constant
        let e1 = 400.0, de = 0.5
        let y = c.targetYield(sFactor: model, entranceEnergy: e1, exitEnergy: e1 - de) { _ in eps }
        let emid = c.cmEnergy(lab: e1 - de / 2)
        let thin = ChargedChannel.thinTargetYield(crossSection: c.crossSection(sFactor: 1.6, energy: emid), arealDensity: de * 1e3 / eps)
        #expect(close(y, thin, rel: 1e-4))
        let eff = c.effectiveEnergy(sFactor: model, entranceEnergy: e1, exitEnergy: e1 - 40) { _ in eps }!
        #expect(eff > c.cmEnergy(lab: e1 - 20) && eff < c.cmEnergy(lab: e1))   // weighted towards the higher energy
    }

    @Test func resolutionPresets() {
        let hpge = ResolutionModel.presets[0].model
        #expect(abs(hpge.fwhm(at: 1332.5) - 1.9) < 0.1)
        #expect(abs(hpge.fwhm(at: 122) - 1.0) < 0.1)
        let nai = ResolutionModel.presets.first { $0.name.hasPrefix("NaI") }!.model
        #expect(close(nai.fwhm(at: 662), 46.34, rel: 1e-9))
    }

    @Test func efficiencyFitRecoversPolynomial() throws {
        let truth = [-5.2, -0.71, -0.05, 0.012]
        let pts = [80.0, 122, 344, 662, 1000, 1332, 2000, 3500, 6000].map { e -> EfficiencyCurve.Point in
            let x = log(e / 1000)
            return .init(energy: e, efficiency: exp(truth.enumerated().reduce(0) { $0 + $1.element * pow(x, Double($1.offset)) }))
        }
        let fit = try #require(EfficiencyCurve(points: pts, order: 3).fit())
        for (a, b) in zip(fit.coefficients, truth) { #expect(abs(a - b) < 1e-8) }
        #expect(fit.chiSquared < 1e-12 && fit.degreesOfFreedom == 5)
        #expect(EfficiencyCurve(points: Array(pts.prefix(3)), order: 3).fit() == nil)
    }

    @Test func dopplerAndGeometry() {
        let beta = 0.01
        #expect(close(GammaDoppler.energy(1000, beta: beta, angle: 0), 1000 * (1 - beta * beta).squareRoot() / (1 - beta), rel: 1e-12))
        let r = GammaDoppler.range(1000, beta: beta, angle: .pi / 2, halfOpening: 0.2)
        #expect(r.contains(GammaDoppler.energy(1000, beta: beta, angle: .pi / 2)))
        #expect(close(GammaDoppler.meanOverCone(1000, beta: beta, angle: 0.5, halfOpening: 1e-4), GammaDoppler.energy(1000, beta: beta, angle: 0.5), rel: 1e-7))
        #expect(close(Geometry.diskSolidAngle(radius: 1, distance: 0), 2 * .pi, rel: 1e-12))
        #expect(close(Geometry.diskSolidAngle(radius: 0.01, distance: 10), .pi * 1e-4 / 100, rel: 1e-3))
        #expect(close(GammaDoppler.recoilCorrected(transition: 1779, mass: 28 * 931494.0), 1779 - 1779.0 * 1779 / (2 * 28 * 931494), rel: 1e-12))
    }
}
