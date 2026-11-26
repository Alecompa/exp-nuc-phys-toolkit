import Foundation
import Testing
@testable import NucPhysKit

/// Deterministic noise of MeasuredSpectrumTests (seeded LCG, Box–Muller), repeated here for the shared reference.
private struct ReferenceNoise {
    var state: UInt64
    mutating func uniform() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return (Double(state >> 11) + 0.5) / Double(1 << 53)
    }
    mutating func poisson(_ mean: Double) -> Double {
        guard mean > 0 else { return 0 }
        let z = (-2 * log(uniform())).squareRoot() * cos(2 * .pi * uniform())
        return max(0, (mean + z * mean.squareRoot()).rounded())
    }
}

/// The synthetic HPGe spectrum of MeasuredSpectrumTests: E = 2 keV + 0.5 keV/ch · ch, FWHM(E) = √(1 + 0.002 E) keV.
private func referenceSynthetic(lines: [(Double, Double)], channels: Int = 8192, gain: Double = 0.5, offset: Double = 2,
                                seed: UInt64 = 7) -> [Double] {
    var noise = ReferenceNoise(state: seed)
    return (0..<channels).map { ch in
        let e = offset + gain * Double(ch)
        var mean = 200 * exp(-e / 800) + 5
        for (energy, area) in lines {
            let s = (1 + 0.002 * energy).squareRoot() / 2.3548 / gain
            let x = (Double(ch) - (energy - offset) / gain) / s
            mean += area / (s * (2 * .pi).squareRoot()) * exp(-0.5 * x * x)
        }
        return noise.poisson(mean)
    }
}

/// Detector and spectrum physics shared with the Kotlin port: `Shared/reference_spectra.json`.
/// Regenerate with `GAMOW_WRITE_REFERENCE=1 ./Tools/test.sh --filter ReferenceSpectra`.
@Suite("Shared reference values: spectra")
struct ReferenceSpectraTests {
    typealias Case = ReferenceValuesTests.Case
    static let fileURL = ReferenceValuesTests.fileURL.deletingLastPathComponent().appendingPathComponent("reference_spectra.json")

    static func list(_ xs: [Double]) -> String { xs.map { "\($0)" }.joined(separator: ",") }
    static func target(_ spec: String) throws -> StoppingTarget { try ReferenceStoppingTests.target(spec) }

    static let materials = [
        "element|1", "element|6", "element|13", "element|29", "element|32", "element|73", "element|82",
        "compound|Plastics / Polymers/Mylar (ICRU-222)", "compound|Nuclear Physics Materials/Water_Liquid (ICRU-276)",
        "compound|Numbered Compounds/Havar (ICRU-470)", "formula|Ta2O5|8.2|0|1", "formula|[13C]C|2|0|1",
    ]
    static let gammaEnergies: [Double] = [1, 1.5, 1.559599, 1.5596, 5, 10, 30, 59.5409, 88, 100, 122.06, 511, 661.657,
                                          1000, 1332.492, 2614.511, 6128.63, 10000, 15000, 20000]

    // MARK: Spectrum summaries

    /// Sums, moments and selected channels; channels in far tails (below 1e-6 of the maximum) are left out because
    /// erf differences there depend on the last bits of the math library.
    static func summarize(_ bins: [SpectrumBin], lines: [Double], values v: inout [String: Double]) {
        let n = bins.count
        v["n"] = Double(n)
        let width = bins[0].energy * 2
        v["width"] = width
        let total = bins.reduce(0) { $0 + $1.total }
        v["sumT"] = total
        v["sumP"] = bins.reduce(0) { $0 + $1.photopeak }
        v["sumC"] = bins.reduce(0) { $0 + $1.compton }
        v["sumB"] = bins.reduce(0) { $0 + $1.background }
        v["sumE"] = bins.reduce(0) { $0 + $1.escape }
        if total > 0 {
            let mean = bins.reduce(0) { $0 + $1.energy * $1.total } / total
            v["centroid"] = mean
            v["variance"] = bins.reduce(0) { $0 + pow($1.energy - mean, 2) * $1.total } / total
        }
        let maxT = bins.map(\.total).max() ?? 0
        var chans = Set<Int>(stride(from: 0, to: n, by: max(1, n / 16)))
        for e in lines {
            for x in [e, e - 510.99895, e - 1021.9979, 510.99895, GammaSpectrum.comptonEdge(energy: e) * 0.3,
                      GammaSpectrum.comptonEdge(energy: e) * 0.9] where x > 0 {
                let c = Int(x / width)
                for d in [-30, -10, -3, -1, 0, 1, 2, 10, 30] { chans.insert(c + d) }
            }
        }
        for c in chans.sorted() where c >= 0 && c < n {
            let b = bins[c]
            for (k, x) in [("t", b.total), ("p", b.photopeak), ("c", b.compton), ("e", b.escape), ("b", b.background)]
            where x == 0 || x >= 1e-6 * maxT {
                v["c\(c).\(k)"] = x
            }
        }
    }

    static func spectrumCases() throws -> [Case] {
        var out: [Case] = []
        let hpge = ResolutionModel.presets[0].model
        let mylar = try target("compound|Plastics / Polymers/Mylar (ICRU-222)")

        var s1 = SpectrumSetup()
        s1.lines = [SpectrumLine(energy: 1000, counts: 10000), SpectrumLine(energy: 1332.5, counts: 5000),
                    SpectrumLine(energy: 6128.63, counts: 20000, dopplerHalfWidth: 25),
                    SpectrumLine(energy: 300, counts: 100000, enabled: false),
                    SpectrumLine(energy: 4438.94, counts: 8000, dopplerHalfWidth: 40)]
        s1.foils = [DetectorFoil(material: .element(13), thickness: 1e6), DetectorFoil(material: mylar, thickness: 5e5, angle: 30)]
        s1.maximumEnergy = 8000; s1.channels = 4096; s1.continuumRatio = 2; s1.background = 0.5
        s1.escape.annihilation = 0.3

        var s2 = s1
        s2.escape.useTypical(for: .bgo)
        s2.maximumEnergy = 7000; s2.channels = 1024; s2.continuumRatio = 1.2; s2.background = 0
        s2.foils = []

        var s3 = SpectrumSetup()
        s3.backgrounds = BackgroundLibrary.all.enumerated().map { BackgroundEntry(id: $0.element.id, counts: 1000 + 10 * Double($0.offset)) }
        s3.geometry.angle = 90; s3.geometry.halfOpening = 10
        s3.lines = s3.backgroundLines(beamEnergy: 400)
        s3.maximumEnergy = 8000; s3.channels = 2048; s3.continuumRatio = 1.5
        s3.escape.useTypical(for: .labr3)

        var s4 = SpectrumSetup()
        s4.lines = [SpectrumLine(energy: 661.657, counts: 1000)]
        s4.maximumEnergy = 2000; s4.channels = 128; s4.continuumRatio = 0; s4.background = 1.25

        var s5 = SpectrumSetup()
        s5.lines = [SpectrumLine(energy: 121.78, counts: 6000), SpectrumLine(energy: 1173.228, counts: 2000),
                    SpectrumLine(energy: 2614.511, counts: 1500)]
        s5.continuumRatio = 0; s5.escape.enabled = false

        let laBr = ResolutionModel.presets.first { $0.name.hasPrefix("LaBr") }!.model
        let naI = ResolutionModel.presets.first { $0.name.hasPrefix("NaI") }!.model
        let setups: [(String, SpectrumSetup, String, ResolutionModel)] = [
            ("s1", s1, "hpge", hpge), ("s2", s2, "nai", naI), ("s3", s3, "labr", laBr), ("s4", s4, "hpge", hpge),
            ("s5", s5, "hpge", hpge),
        ]
        for (id, setup, resName, res) in setups {
            let bins = try GammaSpectrum.simulate(setup, resolution: res)
            var v: [String: Double] = [:]
            summarize(bins, lines: setup.lines.filter(\.enabled).map(\.energy), values: &v)
            let w = bins[1].energy - bins[0].energy
            for (i, (lo, hi)) in [(990.0, 1010.0), (5600, 5640), (0, 8000), (500.3, 521.7), (4300, 4600)].enumerated() {
                let r = SpectrumRegion.integrate(bins, binWidth: w, lower: lo, upper: hi)
                v["roi\(i).p"] = r.photopeak; v["roi\(i).c"] = r.compton; v["roi\(i).b"] = r.background; v["roi\(i).e"] = r.escape
            }
            var inputs = ["setup": id, "resolution": resName]
            if id == "s5" {
                inputs["envelope"] = SpectrumPlotSampling.envelope(bins, budget: 400).map { "\($0.id)" }.joined(separator: ",")
            }
            if id == "s4" { inputs["csv"] = GammaSpectrum.csv(bins) }
            if id == "s3" {
                inputs["lines"] = setup.lines.map(\.name).joined(separator: "|")
                for (i, l) in setup.lines.enumerated() { v["line\(i).e"] = l.energy; v["line\(i).n"] = l.counts; v["line\(i).h"] = l.dopplerHalfWidth }
            }
            out.append(Case(name: "spectrum", inputs: inputs, values: v))
        }
        // Invalid inputs.
        var bad = s4; bad.lines[0].energy = .nan
        var badFoil = s4; badFoil.foils = [DetectorFoil(angle: 90)]
        var badChannels = s4; badChannels.channels = 0
        var badEscape = s4; badEscape.escape.annihilation = 30
        for (id, setup) in [("nan", bad), ("foil90", badFoil), ("channels0", badChannels), ("escape30", badEscape)] {
            let thrown = (try? GammaSpectrum.simulate(setup, resolution: hpge)) == nil
            out.append(Case(name: "spectrum-error", inputs: ["setup": id], values: ["error": thrown ? 1 : 0]))
        }
        return out
    }

    // MARK: Cases

    static func compute() throws -> [Case] {
        var out: [Case] = []

        // Photon attenuation and foils.
        for z in [1, 6, 8, 13, 26, 29, 32, 53, 73, 82, 83, 92] {
            var v: [String: Double] = [:]
            for (i, e) in gammaEnergies.enumerated() { v["mu\(i)"] = try PhotonAttenuation.massCoefficient(z: z, energy: e) }
            out.append(Case(name: "attenuation", inputs: ["z": "\(z)", "energies": list(gammaEnergies)], values: v))
        }
        for (z, e) in [(93, 100.0), (13, 20001), (13, 0.5), (0, 100)] {
            let thrown = (try? PhotonAttenuation.massCoefficient(z: z, energy: e)) == nil
            out.append(Case(name: "attenuation-error", inputs: ["z": "\(z)", "energy": "\(e)"], values: ["error": thrown ? 1 : 0]))
        }
        let foilEnergies: [Double] = [10, 30, 122, 661.657, 1332.492, 6000]
        for spec in materials {
            let m = try target(spec)
            var v: [String: Double] = [:]
            for (i, e) in foilEnergies.enumerated() { v["mu\(i)"] = try PhotonAttenuation.massCoefficient(material: m, energy: e) }
            for (j, (t, a)) in [(1e5, 0.0), (1e6, 30), (5e6, 60), (0, 0), (2e7, 89)].enumerated() {
                let foil = DetectorFoil(material: m, thickness: t, angle: a)
                for (i, e) in foilEnergies.enumerated() { v["T\(j).\(i)"] = try foil.transmission(at: e) }
            }
            out.append(Case(name: "foil", inputs: ["material": spec, "energies": list(foilEnergies)], values: v))
        }
        for (id, foil) in [("angle90", DetectorFoil(angle: 90)), ("negative", DetectorFoil(thickness: -1)),
                           ("nan", DetectorFoil(thickness: .nan))] {
            let thrown = (try? foil.transmission(at: 1000)) == nil
            out.append(Case(name: "foil-error", inputs: ["foil": id], values: ["error": thrown ? 1 : 0]))
        }

        // Pair production and escape ratios.
        let pairEnergies: [Double] = [1000, 1022, 1022.5, 1100, 1500, 2000, 3000, 4438.94, 6000, 6128.63, 10000, 15000, 20000, 25000]
        for crystal in DetectorCrystal.allCases {
            var v: [String: Double] = ["typS": crystal.typicalEscape.single, "typD": crystal.typicalEscape.double]
            var typical = EscapeModel(); typical.useTypical(for: crystal)
            var custom = EscapeModel(); custom.crystal = crystal; custom.singleAtReference = 15; custom.doubleAtReference = 30
            var off = typical; off.enabled = false
            for (i, e) in pairEnergies.enumerated() {
                v["f\(i)"] = PairProduction.fraction(crystal, energy: e)
                let r = typical.ratios(at: e), c = custom.ratios(at: e), o = off.ratios(at: e)
                v["s\(i)"] = r.single; v["d\(i)"] = r.double; v["cs\(i)"] = c.single; v["cd\(i)"] = c.double
                v["os\(i)"] = o.single; v["od\(i)"] = o.double
            }
            out.append(Case(name: "pair", inputs: ["crystal": crystal.rawValue, "name": crystal.name, "energies": list(pairEnergies)],
                            values: v))
        }
        let names = ResolutionModel.presets.map(\.name) + ["CsI(Tl) array", "BGO shield", "Ge clover", "unknown", "LABR3 big"]
        out.append(Case(name: "crystal-match", inputs: ["names": names.joined(separator: "|"),
                                                        "crystals": names.map { DetectorCrystal.matching($0)?.rawValue ?? "none" }.joined(separator: "|")],
                        values: ["n": Double(names.count)]))

        // Resolution.
        let resEnergies: [Double] = [-5, 0, 1, 59.5409, 122.06, 661.657, 1332.492, 6000, 15000]
        var models = ResolutionModel.presets.map { ($0.name, $0.model) }
        models.append(("custom", ResolutionModel(kind: .semiconductor, noise: 2, fano: 0.13, pairEnergy: 3e-3, collection: 1e-3)))
        models.append(("custom-scint", ResolutionModel(kind: .scintillator, resolutionAt662: 0.035)))
        for (i, (name, m)) in models.enumerated() {
            var v: [String: Double] = [:]
            for (j, e) in resEnergies.enumerated() { v["fwhm\(j)"] = m.fwhm(at: e) }
            out.append(Case(name: "resolution", inputs: ["index": "\(i)", "name": name, "energies": list(resEnergies)], values: v))
        }

        // Efficiency curves.
        let effEnergies: [Double] = [50, 122, 300, 1000, 3000, 8000]
        var weighted = EfficiencyCurve.example
        for i in weighted.points.indices { weighted.points[i].relativeUncertainty = 0.01 + 0.005 * Double(i) }
        var curves: [(String, EfficiencyCurve)] = (0...5).map { order in
            var c = EfficiencyCurve.example; c.order = order; return ("example-\(order)", c)
        }
        curves.append(("weighted", weighted))
        curves.append(("few", EfficiencyCurve(points: Array(EfficiencyCurve.example.points.prefix(3)), order: 3)))
        curves.append(("bad-points", EfficiencyCurve(points: EfficiencyCurve.example.points + [
            .init(energy: -5, efficiency: 0.1), .init(energy: 500, efficiency: 0), .init(energy: 800, efficiency: 0.0065, relativeUncertainty: 0)], order: 2)))
        for (id, curve) in curves {
            var v: [String: Double] = [:]
            if let fit = curve.fit() {
                for (i, c) in fit.coefficients.enumerated() { v["a\(i)"] = c }
                v["chi2"] = fit.chiSquared; v["dof"] = Double(fit.degreesOfFreedom)
                if let r = fit.reducedChiSquared { v["reduced"] = r }
                for (i, e) in effEnergies.enumerated() { v["eff\(i)"] = fit.efficiency(at: e) }
            } else {
                v["nil"] = 1
            }
            out.append(Case(name: "efficiency", inputs: ["curve": id, "energies": list(effEnergies)], values: v))
        }
        let a3: [[Double]] = [[4, -2, 1], [-2, 4, -2], [1, -2, 3]], b3: [Double] = [11, -16, 17]
        let x3 = EfficiencyCurve.solve(a3, b3)!
        out.append(Case(name: "solve", inputs: ["system": "3x3"], values: ["x0": x3[0], "x1": x3[1], "x2": x3[2]]))
        out.append(Case(name: "solve", inputs: ["system": "singular"],
                        values: ["nil": EfficiencyCurve.solve([[1, 2], [2, 4]], [1, 2]) == nil ? 1 : 0]))

        // Geometry and Doppler.
        var gv: [String: Double] = [:]
        for (i, (r, d)) in [(1.0, 0.0), (0.01, 10), (2.5, 5), (4, 1)].enumerated() {
            gv["omega\(i)"] = Geometry.diskSolidAngle(radius: r, distance: d)
            gv["half\(i)"] = Geometry.halfOpeningAngle(radius: r, distance: d)
        }
        for (i, (e0, beta, theta, open)) in [(1000.0, 0.01, 0.0, 0.2), (6128.63, 0.006, 0.96, 0.17), (4438.94, 0.03, 2.4, 0.5),
                                              (511.0, 0.002, .pi / 2, 0.0)].enumerated() {
            gv["E\(i)"] = GammaDoppler.energy(e0, beta: beta, angle: theta)
            let r = GammaDoppler.range(e0, beta: beta, angle: theta, halfOpening: open)
            gv["lo\(i)"] = r.lowerBound; gv["hi\(i)"] = r.upperBound
            gv["mean\(i)"] = GammaDoppler.meanOverCone(e0, beta: beta, angle: theta, halfOpening: open)
            gv["mean20_\(i)"] = GammaDoppler.meanOverCone(e0, beta: beta, angle: theta, halfOpening: open, samples: 20)
        }
        gv["recoil"] = GammaDoppler.recoilCorrected(transition: 1779, mass: 28 * 931494.0)
        out.append(Case(name: "doppler", inputs: [:], values: gv))

        out += try spectrumCases()
        out += try inBeamCases()
        out += try particleCases()
        out += try cascadeCases()
        out += try measuredCases()
        return out
    }

    // MARK: In-beam γ rays and backgrounds

    static func lineValues(_ l: InBeamLine, _ p: String, into v: inout [String: Double]) {
        v[p + "rest"] = l.restEnergy; v[p + "shift"] = l.shiftedEnergy; v[p + "half"] = l.halfWidth
        v[p + "frac"] = l.fractionInFlight; v[p + "int"] = l.intensity; v[p + "mean"] = l.meanEnergy
    }

    static func geometries() -> [(String, GammaGeometry)] {
        var out: [(String, GammaGeometry)] = [("default", GammaGeometry())]
        for (angle, open) in [(0.0, 0.0), (0, 15), (90, 0), (135, 15), (180, 5)] {
            var g = GammaGeometry(); g.angle = angle; g.halfOpening = open
            out.append(("a\(angle)o\(open)", g))
        }
        var gas = GammaGeometry(); gas.angle = 90; gas.recoilsStop = false
        out.append(("gas", gas))
        var fast = GammaGeometry(); fast.angle = 135; fast.stoppingTime = 0.2e-12; fast.halfOpening = 5
        out.append(("fast", fast))
        return out
    }

    static func geometryInputs(_ g: GammaGeometry) -> [String: String] {
        ["angle": "\(g.angle)", "open": "\(g.halfOpening)", "stop": g.recoilsStop ? "1" : "0", "tstop": "\(g.stoppingTime)"]
    }

    static func inBeamCases() throws -> [Case] {
        var out: [Case] = []
        let captures: [(String, Double)] = [("d(p,g)3He", 0), ("12C(p,g)13N", 0), ("14N(p,g)15O", 6176.3), ("3He(a,g)7Be", 429.08),
                                            ("27Al(p,g)28Si", 1779.03), ("7Li(p,a)4He", 0), ("4He(a,g)8Be", 0)]
        for (notation, final) in captures {
            let r = try Reaction(notation: notation)
            for e in [100.0, 400, 2000] {
                for (gid, g) in geometries() {
                    var v: [String: Double] = [:]
                    var inputs = geometryInputs(g)
                    inputs["reaction"] = notation; inputs["beam"] = "\(e)"; inputs["final"] = "\(final)"; inputs["geometry"] = gid
                    if let l = InBeamGamma.primary(r, beamEnergy: e, finalLevel: final, geometry: g) {
                        lineValues(l, "", into: &v); inputs["label"] = l.label
                    } else { v["nil"] = 1 }
                    out.append(Case(name: "primary", inputs: inputs, values: v))
                }
            }
        }
        let ln2 = log(2.0)
        let levels: [(String, Double, Double, Double?, Double, Double?, Double, String?)] = [
            ("15N(p,a)12C", 400, 4439.82, 4438.94, 0, 61e-15, 1, nil),
            ("19F(p,a)16O", 340, 6129.89, 6128.63, 0, 18.4e-12 / ln2, 1, nil),
            ("27Al(p,p)27Al", 2000, 843.76, nil, 0, 35e-12 / ln2, 0.7, nil),
            ("27Al(p,p)27Al", 2000, 1014.56, nil, 843.76, nil, 1, "custom label"),
            ("12C(a,a)12C", 3000, 4439.82, 4438.94, 0, 61e-15, 1, nil),
            ("12C(a,a)12C", 8000, 4439.82, 4438.94, 0, 61e-15, 1, nil),
            ("23Na(p,g)24Mg", 300, 1368.667, 1368.625, 0, 1.36e-12 / ln2, 1, nil),
            ("7Li(p,p)7Li", 1500, 477.612, nil, 0, 0, 1, nil),
        ]
        for (notation, e, level, transition, final, tau, intensity, label) in levels {
            let r = try Reaction(notation: notation)
            for (gid, g) in geometries() {
                var v: [String: Double] = [:]
                var inputs = geometryInputs(g)
                inputs["reaction"] = notation; inputs["beam"] = "\(e)"; inputs["level"] = "\(level)"
                inputs["transition"] = transition.map { "\($0)" } ?? ""; inputs["final"] = "\(final)"
                inputs["tau"] = tau.map { "\($0)" } ?? ""; inputs["intensity"] = "\(intensity)"; inputs["custom"] = label ?? ""
                inputs["geometry"] = gid
                if let l = InBeamGamma.residualLevel(r, beamEnergy: e, level: level, transition: transition, finalLevel: final,
                                                     meanLife: tau, intensity: intensity, geometry: g, label: label) {
                    lineValues(l, "", into: &v); inputs["label"] = l.label
                    let sl = l.spectrumLines(counts: 1000)
                    v["nsl"] = Double(sl.count)
                    for (i, s) in sl.enumerated() { v["sl\(i).e"] = s.energy; v["sl\(i).n"] = s.counts; v["sl\(i).h"] = s.dopplerHalfWidth }
                    inputs["slnames"] = sl.map(\.name).joined(separator: "|")
                } else { v["nil"] = 1 }
                out.append(Case(name: "level", inputs: inputs, values: v))
            }
        }
        // Library lines at two beam energies, and whether each source applies to p and α beams.
        let p = MassTable.ame2020.nuclide(named: "p")!, alpha = MassTable.ame2020.nuclide(named: "a")!
        for source in BackgroundLibrary.all {
            for e in [400.0, 8000] {
                for (gid, g) in geometries() where gid == "default" || gid == "a0.0o15.0" || gid == "gas" {
                    let lines = source.lines(beamEnergy: e, geometry: g)
                    var v: [String: Double] = ["n": Double(lines.count),
                                               "appliesP": source.applies(projectile: p, beamEnergy: e) ? 1 : 0,
                                               "appliesA": source.applies(projectile: alpha, beamEnergy: e) ? 1 : 0]
                    for (i, l) in lines.enumerated() { lineValues(l, "l\(i).", into: &v) }
                    var inputs = geometryInputs(g)
                    inputs["source"] = source.id; inputs["beam"] = "\(e)"; inputs["geometry"] = gid
                    inputs["labels"] = lines.map(\.label).joined(separator: "|")
                    inputs["ids"] = lines.map(\.id).joined(separator: "|")
                    out.append(Case(name: "background", inputs: inputs, values: v))
                }
            }
        }
        for e in [400.0, 8000] {
            var setup = SpectrumSetup()
            setup.backgrounds = BackgroundLibrary.all.enumerated().map {
                BackgroundEntry(id: $0.element.id, counts: 1000 + 10 * Double($0.offset), enabled: $0.offset != 3)
            } + [BackgroundEntry(id: "unknown")]
            setup.geometry.angle = 120
            let lines = setup.backgroundLines(beamEnergy: e)
            var v: [String: Double] = ["n": Double(lines.count)]
            for (i, l) in lines.enumerated() { v["l\(i).e"] = l.energy; v["l\(i).n"] = l.counts; v["l\(i).h"] = l.dopplerHalfWidth }
            out.append(Case(name: "background-lines", inputs: ["beam": "\(e)", "names": lines.map(\.name).joined(separator: "|")], values: v))
        }
        return out
    }

    // MARK: Particle spectra

    static func particleCases() throws -> [Case] {
        var out: [Case] = []
        let mylar = try target("compound|Plastics / Polymers/Mylar (ICRU-222)")
        func setup(angle: Double = 135, resolution: Double = 15, open: Double = 2, foils: [DetectorFoil] = [], elastic: Bool = true) -> ParticleDetectorSetup {
            var s = ParticleDetectorSetup()
            s.angle = angle; s.resolution = resolution; s.halfOpening = open; s.foils = foils; s.showElastic = elastic
            return s
        }
        let al15 = DetectorFoil(material: .element(13), thickness: 1.5e5)
        let cases: [(String, String, Double, Double, String?, ParticleDetectorSetup)] = [
            ("li-noelastic", "7Li(p,a)4He", 1400, 0, "element|3", setup(elastic: false)),
            ("li", "7Li(p,a)4He", 1400, 0, "element|3", setup()),
            ("li-al", "7Li(p,a)4He", 1400, 0, "element|3", setup(foils: [al15])),
            ("li-two-foils", "7Li(p,a)4He", 1000, 0, "formula|LiF|2.6|0|1",
             setup(angle: 150, foils: [DetectorFoil(material: mylar, thickness: 2e4, angle: 20), DetectorFoil(material: .element(13), thickness: 0), al15])),
            ("cu-15", "63Cu(p,g)64Zn", 2000, 0, "element|29", setup()),
            ("cu-2", "63Cu(p,g)64Zn", 2000, 0, "element|29", setup(resolution: 2)),
            ("ta2o5", "18O(p,a)15N", 800, 0, "formula|Ta2O5|8.2|0|1", setup(angle: 160, foils: [DetectorFoil(material: mylar, thickness: 1e4)])),
            ("ta2o5-thick", "18O(p,a)15N", 800, 0, "formula|Ta2O5|8.2|0|1", setup(angle: 160, foils: [DetectorFoil(material: mylar, thickness: 1e6)])),
            ("c13-mix", "13C(p,g)14N", 1000, 0, "formula|[13C]C|2|0|1", setup(angle: 150, resolution: 1, open: 0)),
            ("au", "197Au(a,g)201Tl", 2000, 0, "element|79", setup(angle: 170)),
            ("heavy-on-h", "p(12C,g)13N", 12000, 0, "element|1", setup(angle: 3, open: 0)),
            ("capture-c", "12C(p,g)13N", 400, 0, "element|6", setup()),
            ("neutron", "7Li(p,n)7Be", 2500, 0, "element|3", setup(angle: 30, foils: [al15])),
            ("inelastic", "27Al(p,p)27Al", 3000, 843.76, "element|13", setup(angle: 90)),
            ("mylar-target", "15N(p,a)12C", 1200, 4439.82, "compound|Plastics / Polymers/Mylar (ICRU-222)", setup(angle: 120)),
            ("no-material", "7Li(p,a)4He", 1400, 0, nil, setup()),
            ("bad-angle", "7Li(p,a)4He", 1400, 0, "element|3", setup(angle: 180)),
        ]
        for (id, notation, e, ex, material, s) in cases {
            let r = try Reaction(notation: notation)
            let groups = ParticleSpectrum.groups(reaction: r, beamEnergy: e, residualExcitation: ex,
                                                 material: try material.map { try target($0) }, setup: s)
            var v: [String: Double] = ["n": Double(groups.count)]
            for (i, g) in groups.enumerated() {
                v["emitted\(i)"] = g.emitted; v["fwhm\(i)"] = g.fwhm; v["neutral\(i)"] = g.neutral ? 1 : 0
                if let d = g.detected { v["detected\(i)"] = d }
                if let st = g.stoppedIn { v["stopped\(i)"] = Double(st) }
                if let ru = g.rutherford { v["ruth\(i)"] = ru }
            }
            out.append(Case(name: "particle", inputs: [
                "case": id, "reaction": notation, "beam": "\(e)", "excitation": "\(ex)", "material": material ?? "",
                "ids": groups.map(\.id).joined(separator: "|"), "origins": groups.map(\.origin).joined(separator: "|"),
                "particles": groups.map(\.particle).joined(separator: "|"),
                "kinds": groups.map { $0.kind == .reaction ? "reaction" : "elastic" }.joined(separator: "|"),
            ], values: v))
        }
        for z in [1, 3, 6, 8, 29, 43, 50, 73] {
            let iso = ParticleSpectrum.naturalIsotopes(z: z)
            var v: [String: Double] = ["n": Double(iso.count)]
            for (i, (n, ab)) in iso.enumerated() { v["a\(i)"] = Double(n.a); v["ab\(i)"] = ab }
            out.append(Case(name: "isotopes", inputs: ["z": "\(z)"], values: v))
        }
        return out
    }

    // MARK: Cascades

    static let toyScheme = LevelScheme(
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
        reference: "test", retrieved: Date(timeIntervalSince1970: 0))

    static func fixture(_ n: String) throws -> String {
        try String(contentsOf: Bundle.module.url(forResource: n, withExtension: "csv")!, encoding: .utf8)
    }

    static func cascadeValues(_ r: GammaCascade.Result, taus: [Double: Double], into v: inout [String: Double]) -> String {
        v["n"] = Double(r.lines.count); v["unresolved"] = r.unresolved; v["without"] = Double(r.withoutIntensity)
        if let s = r.startLevel { v["start"] = s }
        for (i, l) in r.lines.enumerated() {
            v["e\(i)"] = l.energy; v["i\(i)"] = l.intensity; v["from\(i)"] = l.initialLevel; v["to\(i)"] = l.finalLevel
        }
        let times = GammaCascade.meanDecayTimes(r.lines) { taus[$0] }
        let keys = times.keys.sorted(by: >)
        for (i, k) in keys.enumerated() { v["t\(i)"] = times[k]! }
        return list(keys)
    }

    static func cascadeCases() throws -> [Case] {
        var out: [Case] = []
        var gammas = toyScheme.gammas
        gammas.append(GammaTransition(initialLevel: 3000, finalLevel: 1500, initialSpinParity: "2+", finalSpinParity: "",
                                      energy: 1500, energyUncertainty: nil, relativeIntensity: 100, multipolarity: ""))
        gammas.append(GammaTransition(initialLevel: 3000, finalLevel: 500, initialSpinParity: "2+", finalSpinParity: "",
                                      energy: 2500, energyUncertainty: nil, relativeIntensity: nil, multipolarity: ""))
        let missing = LevelScheme(levels: toyScheme.levels, gammas: gammas, reference: "test", retrieved: Date(timeIntervalSince1970: 0))
        var noIntensity = toyScheme.gammas.map {
            GammaTransition(initialLevel: $0.initialLevel, finalLevel: $0.finalLevel, initialSpinParity: "", finalSpinParity: "",
                            energy: $0.energy, energyUncertainty: nil, relativeIntensity: nil, multipolarity: "")
        }
        noIntensity.append(GammaTransition(initialLevel: 2000, finalLevel: 1000, initialSpinParity: "", finalSpinParity: "",
                                           energy: 1000, energyUncertainty: nil, relativeIntensity: 0, multipolarity: ""))
        let equal = LevelScheme(levels: toyScheme.levels, gammas: noIntensity, reference: "test", retrieved: Date(timeIntervalSince1970: 0))
        let toyTaus: [Double: Double] = [3000: 10e-12, 1000: 50e-15, 2000: 1e-12]
        for (id, scheme) in [("toy", toyScheme), ("missing", missing), ("equal", equal)] {
            for ex in [3001.0, 3000, 2000, 1500, 1000, 0, 3007] {
                var v: [String: Double] = [:]
                let keys = cascadeValues(GammaCascade.from(excitation: ex, scheme: scheme), taus: toyTaus, into: &v)
                out.append(Case(name: "cascade", inputs: ["scheme": id, "excitation": "\(ex)", "timeLevels": keys], values: v))
            }
            var v: [String: Double] = [:]
            let keys = cascadeValues(GammaCascade.from(excitation: 3003, scheme: scheme, tolerance: 5), taus: toyTaus, into: &v)
            out.append(Case(name: "cascade", inputs: ["scheme": id, "excitation": "3003.0", "tolerance": "5.0", "timeLevels": keys], values: v))
        }
        let si = try LiveChartClient.parse(levels: try fixture("livechart_28si_levels"), gammas: try fixture("livechart_28si_gammas"),
                                           retrieved: Date(timeIntervalSince1970: 0))
        var lv: [String: Double] = ["levels": Double(si.levels.count), "gammas": Double(si.gammas.count)]
        for (i, l) in si.levels.prefix(12).enumerated() {
            lv["E\(i)"] = l.energy; lv["idx\(i)"] = Double(l.index)
            if let u = l.energyUncertainty { lv["dE\(i)"] = u }
            if let t = l.halfLifeSeconds { lv["T\(i)"] = t }
        }
        for (i, g) in si.gammas.prefix(12).enumerated() {
            lv["g\(i)"] = g.energy; lv["gi\(i)"] = g.initialLevel; lv["gf\(i)"] = g.finalLevel
            if let u = g.energyUncertainty { lv["gu\(i)"] = u }
            if let r = g.relativeIntensity { lv["gr\(i)"] = r }
        }
        out.append(Case(name: "livechart", inputs: [
            "reference": si.reference, "jp": si.levels.prefix(12).map(\.spinParity).joined(separator: "|"),
            "halfLives": si.levels.prefix(12).map(\.halfLife).joined(separator: "|"),
            "multipolarities": si.gammas.prefix(12).map(\.multipolarity).joined(separator: "|"),
            "gjp": si.gammas.prefix(12).map { $0.initialSpinParity + ">" + $0.finalSpinParity }.joined(separator: "|"),
        ], values: lv))
        let siTaus = Dictionary(si.levels.compactMap { l in l.halfLifeSeconds.map { (l.energy, $0 / log(2.0)) } }, uniquingKeysWith: { a, _ in a })
        for ex in [1779.03, 4618.0, 6276.2, 6878.79, 7416.26, 8258.74, 9381.55, 10000, 11000] {
            var v: [String: Double] = [:]
            let keys = cascadeValues(GammaCascade.from(excitation: ex, scheme: si), taus: siTaus, into: &v)
            out.append(Case(name: "cascade", inputs: ["scheme": "28Si", "excitation": "\(ex)", "timeLevels": keys], values: v))
        }
        return out
    }

    // MARK: Measured spectra

    static let europiumCobalt: [(Double, Double)] = [(121.78, 60000), (244.70, 15000), (344.28, 40000), (778.90, 12000), (964.08, 12000),
                                                     (1085.84, 8000), (1112.08, 11000), (1408.01, 16000), (1173.228, 20000), (1332.492, 20000)]

    static func peakValues(_ peaks: [FoundPeak], into v: inout [String: Double]) {
        v["peaks"] = Double(peaks.count)
        for (i, p) in peaks.enumerated() {
            v["p\(i).c"] = p.centroid; v["p\(i).dc"] = p.centroidUncertainty; v["p\(i).w"] = p.fwhm
            v["p\(i).a"] = p.area; v["p\(i).da"] = p.areaUncertainty; v["p\(i).s"] = p.significance
        }
    }

    static func measuredCases() throws -> [Case] {
        var out: [Case] = []
        let cobalt = referenceSynthetic(lines: [(1173.228, 20000), (1332.492, 20000)])
        let eu = referenceSynthetic(lines: europiumCobalt)
        let eu2 = referenceSynthetic(lines: europiumCobalt, channels: 4096, gain: 0.75, offset: -5, seed: 13)
        for (id, counts, fwhm, threshold) in [("cobalt", cobalt, 4.0, 5.0), ("eu", eu, 4.0, 5.0), ("eu-default", eu, 4.0, 4.0),
                                               ("eu2", eu2, 3.0, 5.0), ("eu-wide", eu, 9.0, 5.0)] {
            var v: [String: Double] = ["sum": counts.reduce(0, +),
                                       "moment": counts.enumerated().reduce(0) { $0 + Double($1.offset) * $1.element },
                                       "channels": Double(counts.count)]
            peakValues(PeakSearch.find(counts, fwhm: fwhm, threshold: threshold), into: &v)
            out.append(Case(name: "peaks", inputs: ["spectrum": id, "fwhm": "\(fwhm)", "threshold": "\(threshold)"], values: v))
        }
        for iterations in [0, 4, 10, 40] {
            let bg = PeakSearch.snipBackground(eu, iterations: iterations)
            var v: [String: Double] = ["sum": bg.reduce(0, +)]
            for c in [0, 3, 100, 240, 500, 1000, 2660, 4000, 8000, 8191] { v["c\(c)"] = bg[c] }
            out.append(Case(name: "snip", inputs: ["spectrum": "eu", "iterations": "\(iterations)"], values: v))
        }
        out.append(Case(name: "peaks-short", inputs: [:], values: [
            "flat17": Double(PeakSearch.find([Double](repeating: 5, count: 17), fwhm: 6).count),
            "wide": Double(PeakSearch.find([Double](repeating: 5, count: 1024), fwhm: 500).count),
            "snip2": PeakSearch.snipBackground([3, 4], iterations: 5).reduce(0, +)]))

        let euSource = CalibrationSources.source(named: "152Eu")!, coSource = CalibrationSources.source(named: "60Co")!
        let refLines = AutoCalibration.lines(sources: [euSource, coSource])
        var lv: [String: Double] = ["n": Double(refLines.count)]
        for (i, l) in refLines.enumerated() { lv["e\(i)"] = l.energy; lv["w\(i)"] = l.weight }
        out.append(Case(name: "calibration-lines", inputs: ["labels": refLines.map(\.label).joined(separator: "|"),
                                                            "ids": refLines.map(\.id).joined(separator: "|")], values: lv))
        let euPeaks = PeakSearch.find(eu, fwhm: 4, threshold: 5)
        let eu2Peaks = PeakSearch.find(eu2, fwhm: 3, threshold: 5)
        let variants: [(String, [FoundPeak], Bool, ClosedRange<Double>, Double, Double?)] = [
            ("linear", euPeaks, false, 0.01...100, 100, nil),
            ("quadratic", euPeaks, true, 0.01...100, 100, nil),
            ("tolerance", euPeaks, false, 0.01...100, 100, 1.5),
            ("narrow", euPeaks, false, 0.4...0.6, 10, nil),
            ("eu2", eu2Peaks, false, 0.01...100, 100, nil),
            ("excluded", euPeaks, false, 1...2, 100, nil),
            ("one-peak", Array(euPeaks.prefix(1)), false, 0.01...100, 100, nil),
        ]
        for (id, peaks, quadratic, range, offset, tol) in variants {
            var v: [String: Double] = [:]
            if let r = AutoCalibration.calibrate(peaks: peaks, lines: refLines, quadratic: quadratic, gainRange: range,
                                                 maxOffset: offset, tolerance: tol) {
                for (i, c) in r.calibration.coefficients.enumerated() { v["k\(i)"] = c }
                v["gain"] = r.calibration.gain; v["rms"] = r.rms; v["matches"] = Double(r.matches.count)
                for (i, m) in r.matches.enumerated() {
                    v["m\(i).line"] = m.line.energy; v["m\(i).peak"] = m.peak.centroid; v["m\(i).fit"] = m.fitted; v["m\(i).res"] = m.residual
                }
            } else { v["nil"] = 1 }
            out.append(Case(name: "autocal", inputs: ["variant": id], values: v))
        }
        let cal = EnergyCalibration(coefficients: [1.5, 0.4, 2e-6])
        var cv: [String: Double] = [:]
        for (i, e) in [0.0, 100, 1332.492, 3000, 10000].enumerated() {
            cv["ch\(i)"] = cal.channel(energy: e); cv["lin\(i)"] = EnergyCalibration(coefficients: [-3, 0.25]).channel(energy: e)
            cv["flat\(i)"] = EnergyCalibration(coefficients: [5]).channel(energy: e)
        }
        for (i, c) in [0.0, 1, 2500.5, 8191].enumerated() { cv["E\(i)"] = cal.energy(channel: c) }
        let pts = [100.0, 1000, 2500, 4000, 6000].map { (channel: $0, energy: cal.energy(channel: $0) + 0.01 * sin($0), sigma: 0.1 + $0 / 1e5) }
        for order in 1...3 {
            if let c = AutoCalibration.fit(pts, order: order) { for (i, x) in c.enumerated() { cv["fit\(order).\(i)"] = x } }
        }
        cv["fitNil"] = AutoCalibration.fit(Array(pts.prefix(2)), order: 2) == nil ? 1 : 0
        out.append(Case(name: "calibration", inputs: [:], values: cv))

        // File parsing.
        let spe = "$SPEC_ID:\ntest\n$MEAS_TIM:\n100 120\n$DATA:\n0 4\n1\n2\n30\n2\n1\n$ENER_FIT:\n0.5 0.25\n"
        let mca = "$SPEC_ID:\nx\n$MCA_CAL:\n3\n1.25 0.5 1E-6 keV\n$DATA:\n0 3\n10\n20\n30\n40\n$MEAS_TIM:\n50.5\n"
        let samples: [(String, String)] = [
            ("a.Spe", spe), ("crlf.Spe", spe.replacingOccurrences(of: "\n", with: "\r\n")), ("mca.spe", mca),
            ("baddata.spe", "$DATA:\n5 2\n1\n"), ("short.spe", "$DATA:\n0 5\n1\n2\n"),
            ("zero-gain.spe", "$ENER_FIT:\n1 0\n$DATA:\n0 1\n4\n5\n"),
            ("b.csv", "channel,counts\n0,5\n1,6\n2,7\n"), ("c.txt", "# keV counts\n10.0 1\n10.5 2\n11.0 3\n"),
            ("d.txt", "hello"), ("e.txt", "Live time: 100\nchannel counts\n0 4\n1 5\n2 6\n3 7\n"),
            ("f.txt", "12.5 3\n12.0 2\n11.5 1\n"), ("g.txt", "1\n2\n3\n4;5\n\n# x\n7\n"),
            ("h.csv", "1,10\n2,20\n3,30\n"), ("i.txt", "5\t1\t9\n6\t2\t9\n7\t3\t9\n"), ("j.txt", "1e2 3\n1.5e2 4\n2e2 5\n"),
            ("k.txt", "1f 2\n3 4d\n5 6\n"), ("l.txt", "-1 3\n0 4\n1 5\n"), ("m.txt", ""),
        ]
        func parseCase(_ name: String, _ data: Data, _ inputs: [String: String]) -> Case {
            var v: [String: Double] = [:]
            do {
                let s = try MeasuredSpectrum.read(data, name: name)
                v["n"] = Double(s.counts.count)
                for (i, c) in s.counts.prefix(12).enumerated() { v["c\(i)"] = c }
                if let t = s.liveTime { v["live"] = t }
                if let t = s.realTime { v["real"] = t }
                for (i, c) in (s.fileCalibration?.coefficients ?? []).enumerated() { v["k\(i)"] = c }
            } catch MeasuredSpectrum.ImportError.empty {
                v["error"] = 1
            } catch {
                v["error"] = 2
            }
            return Case(name: "parse", inputs: inputs, values: v)
        }
        for (name, text) in samples { out.append(parseCase(name, Data(text.utf8), ["name": name, "text": text])) }
        // Latin-1 header (µ = 0xB5 is not valid UTF-8).
        var latin = Data("# 10 ".utf8); latin.append(0xB5); latin.append(contentsOf: Data("s\n0 8\n1 9\n".utf8))
        out.append(parseCase("latin.txt", latin, ["name": "latin.txt", "hex": latin.map { String(format: "%02x", $0) }.joined()]))
        func chn(_ n: Int, header: Int16 = -1, truncate: Int = 0) -> Data {
            var d = Data()
            func put16(_ v: Int16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
            func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
            put16(header); put16(1); put16(1); put16(0)
            put32(6000); put32(5000)
            d.append(contentsOf: [UInt8](repeating: 0x30, count: 12))
            put16(0); put16(Int16(n))
            for i in 0..<n { put32(UInt32(7 + i * 1_000_003)) }
            return d.prefix(d.count - truncate)
        }
        for (id, d) in [("x.Chn", chn(3)), ("big.chn", chn(12)), ("bad.chn", chn(3, header: 0)), ("cut.chn", chn(3, truncate: 4)),
                        ("tiny.chn", Data([0xFF, 0xFF]))] {
            out.append(parseCase(id, d, ["name": id, "hex": d.map { String(format: "%02x", $0) }.joined()]))
        }
        return out
    }

    @Test func swiftReproducesSharedFile() throws {
        let cases = try Self.compute()
        if ProcessInfo.processInfo.environment["GAMOW_WRITE_REFERENCE"] == "1" {
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(cases).write(to: Self.fileURL)
        }
        let stored = try JSONDecoder().decode([Case].self, from: Data(contentsOf: Self.fileURL))
        #expect(stored.count == cases.count)
        #expect(stored == cases)
    }
}
