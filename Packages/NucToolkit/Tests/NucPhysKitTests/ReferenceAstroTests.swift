import Foundation
import Testing
@testable import NucPhysKit

/// Astrophysics and run-planning reference values shared with the Kotlin port: `Shared/reference_astro.json`.
/// Reaction rates (S-factor models and narrow resonances), penetrabilities and shift factors, Rutherford
/// scattering, counting statistics, beam arithmetic, target yields through SRIM targets and resonance yields.
/// Same mechanism as `ReferenceValuesTests`; the Kotlin test `ReferenceAstroTest` reads the same file.
/// Regenerate after a deliberate change with `GAMOW_WRITE_REFERENCE=1 ./Tools/test.sh --filter ReferenceAstro`.
@Suite("Shared astro reference values")
struct ReferenceAstroTests {
    struct Case: Codable, Equatable {
        var name: String
        var inputs: [String: String]
        var values: [String: Double]
    }

    static let fileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Shared/reference_astro.json")

    /// "poly|s0|s1|s2" or "table|<text for parseTable>".
    static func model(_ spec: String) throws -> SFactorModel {
        let p = spec.split(separator: "|", maxSplits: 1).map(String.init)
        if p[0] == "table" { return SFactorModel(kind: .table, table: try SFactorModel.parseTable(p[1])) }
        let q = spec.split(separator: "|").map { Double($0) ?? 0 }
        return SFactorModel(kind: .polynomial, s0: q[1], s1: q[2], s2: q[3])
    }

    /// "E:ωγ;E:ωγ" (keV c.m., eV).
    static func resonances(_ spec: String) -> [NarrowResonance] {
        spec.split(separator: ";").map {
            let q = $0.split(separator: ":").map { Double($0)! }
            return NarrowResonance(energy: q[0], strength: q[1])
        }
    }

    /// "element|Z", "formula|text|density|gas|correction", "gas|text|mbar|K".
    static func target(_ spec: String) throws -> StoppingTarget {
        let p = spec.split(separator: "|").map(String.init)
        switch p[0] {
        case "element": return .element(Int(p[1])!)
        case "formula":
            var t = StoppingTarget.formula(try ChemicalFormula(p[1]), density: Double(p[2])!, gas: p[3] == "1")
            t.compoundCorrection = Double(p[4])!
            return t
        case "gas":
            var t = StoppingTarget.formula(try ChemicalFormula(p[1]), density: 1, gas: true)
            t.density = GasTarget.density(of: t, pressure: Double(p[2])!, temperature: Double(p[3])!,
                                          atomsPerMolecule: GasTarget.defaultAtomsPerMolecule(t))
            return t
        default: fatalError(spec)
        }
    }

    static func channel(_ reaction: String, _ side: String) throws -> ChargedChannel {
        let r = try Reaction(notation: reaction)
        return side == "exit" ? ChargedChannel.exit(r)! : ChargedChannel.entrance(r)
    }

    static let tableA = "E_keV, S_keVb\n20, 1.62\n50, 1.58\n100 1.52\n# comment line\n200\t1.49\n400; 1.75 # rising\n1000, 2.4"
    static let tableB = "# 12C(a,g) toy table\n300 120\n1000 95\n1500 0\n2000 -5\n2500 80"

    static func compute() throws -> [Case] {
        var out: [Case] = []

        // Reaction rates on the standard grid, S-factor models and narrow resonances.
        let rates: [(String, String, String)] = [
            ("12C(p,g)13N", "poly|1.5|0.002|0", "421:0.0067;1558:0.25"),
            ("12C(p,g)13N", "table|" + tableA, "421:0.0067"),
            ("14N(p,g)15O", "poly|1.6|-0.002|1e-5", "259:0.0131;985:0.35"),
            ("3He(a,g)7Be", "poly|0.56|-3.6e-4|3e-7", "1500:1e-3"),
            ("12C(a,g)16O", "poly|170|0|0", "2400:0.1"),
            ("12C(a,g)16O", "table|" + tableB, "2400:0.1;3200:2"),
        ]
        for (n, m, res) in rates {
            let c = ChargedChannel.entrance(try Reaction(notation: n))
            let model = try model(m)
            var v: [String: Double] = [:]
            for (i, t9) in ChargedChannel.rateGrid.enumerated() {
                v["r\(i)"] = c.rate(sFactor: model, t9: t9)
                for (k, r) in resonances(res).enumerated() { v["nr\(k).\(i)"] = c.narrowResonanceRate(r, t9: t9) }
            }
            v["r1000pts.T9=0.05"] = c.rate(sFactor: model, t9: 0.05, points: 1001)
            v["grid"] = Double(ChargedChannel.rateGrid.count)
            out.append(Case(name: "rate", inputs: ["reaction": n, "model": m, "resonances": res], values: v))
        }

        // S-factor models: evaluation, range, table text and parse errors.
        for m in ["poly|1.5|0.002|0", "poly|1.6|-0.002|1e-5", "poly|-1|0.001|0", "table|" + tableA, "table|" + tableB] {
            let model = try model(m)
            var v: [String: Double] = ["points": Double(model.table.count),
                                       "lo": model.tableRange?.lowerBound ?? -1, "hi": model.tableRange?.upperBound ?? -1]
            for (i, e) in [0.0, 5, 20, 35, 100, 150, 400, 999, 1250, 1750, 2200, 5000].enumerated() { v["s\(i)"] = model.s(at: e) }
            out.append(Case(name: "sfactor", inputs: ["model": m, "text": model.tableText], values: v))
        }
        for text in ["1 2\n3", "E S\n1 2", "E S\nfoo bar\n1 2\n3 4", "# only a comment\n1,2", "1e-3,4.5\r\n2.5E+2;1.0e1\n0.5 7",
                     "+1 2\n.5 3.\n1. -2", "1 2 3\n4 5 6", "1d 2\n3 4"] {
            var message = "ok"
            var tableText = ""
            do { tableText = SFactorModel(kind: .table, table: try SFactorModel.parseTable(text)).tableText }
            catch let e as SFactorModel.ParseError { message = e.errorDescription ?? "?" }
            out.append(Case(name: "sfactor-parse", inputs: ["text": text, "error": message, "tableText": tableText], values: [:]))
        }

        // Penetrabilities and shift factors, l = 0...3, incl. deep sub-barrier and neutral channels.
        let channels: [(String, String)] = [("12C(p,g)13N", "entrance"), ("3He(a,g)7Be", "entrance"), ("12C(a,g)16O", "entrance"),
                                            ("12C(12C,a)20Ne", "entrance"), ("13C(a,n)16O", "exit"), ("7Li(p,a)4He", "exit")]
        for (n, side) in channels {
            let c = try channel(n, side)
            for l in 0...3 {
                for e in [10.0, 300, 3000] {
                    for a in [4.0, 6.5] {
                        let p = c.penetrability(l: l, energy: e, radius: a)
                        out.append(Case(name: "penetrability",
                                        inputs: ["reaction": n, "side": side, "l": "\(l)", "energy": "\(e)", "radius": "\(a)"],
                                        values: ["P": p.penetrability, "lnP": p.lnP, "shift": p.shift, "rho": p.rho, "eta": p.eta]))
                    }
                }
            }
        }
        for (l, eta, rho) in [(0, 0.0, 0.5), (2, 0.0, 0.1), (1, 5.0, 2.0), (0, 20.0, 1.0), (3, 0.5, 30.0)] {
            let p = CoulombFunctions.penetrability(l: l, eta: eta, rho: rho)
            out.append(Case(name: "coulomb", inputs: ["l": "\(l)", "eta": "\(eta)", "rho": "\(rho)"],
                            values: ["P": p.penetrability, "lnP": p.lnP, "shift": p.shift]))
        }

        // Rutherford scattering, incl. a heavy projectile (two branches) and equal masses.
        let ruth: [(Int, Int, Int, Int, Double, [Double])] = [
            (1, 1, 6, 12, 1000, [10, 30, 90, 150, 170]), (6, 12, 1, 1, 12000, [1, 3, 4.5, 6]),
            (2, 4, 79, 197, 5000, [20, 90, 160]), (2, 4, 2, 4, 2000, [30, 60]), (8, 16, 2, 4, 20000, [5, 14]),
        ]
        for (z1, a1, z2, a2, e, angles) in ruth {
            let t = MassTable.ame2020
            let rs = RutherfordScattering(projectile: t.nuclide(z: z1, a: a1)!, target: t.nuclide(z: z2, a: a2)!, beamEnergy: e)
            for angle in angles {
                let pts = rs.at(labAngle: angle * .pi / 180)
                var v: [String: Double] = ["branches": Double(pts.count), "ecm": rs.kinematics.centerOfMassEnergy,
                                           "cm90": rs.crossSectionCM(thetaCM: .pi / 2)]
                for (i, p) in pts.enumerated() {
                    v["th\(i)"] = p.thetaCM; v["e\(i)"] = p.energy; v["cm\(i)"] = p.crossSectionCM; v["lab\(i)"] = p.crossSectionLab
                }
                out.append(Case(name: "rutherford", inputs: ["projectile": "\(z1)|\(a1)", "target": "\(z2)|\(a2)",
                                                             "energy": "\(e)", "angle": "\(angle)"], values: v))
            }
        }

        // Counting statistics and Currie limits, both background assumptions.
        for (s, b, u, t, bc) in [(1.0, 0.1, 0.05, 3600.0, 100.0), (0.01, 0.05, 0.1, 86400, 4), (5e-4, 2e-3, 0.3, 1e6, 0),
                                 (100, 0, 0.01, 10, 1e4)] {
            var v: [String: Double] = [:]
            for eq in [true, false] {
                let k = eq ? "eq" : "known"
                v["time.\(k)"] = CountingStatistics.time(signal: s, background: b, relativeUncertainty: u, backgroundFromEqualTime: eq)
                v["unc.\(k)"] = CountingStatistics.relativeUncertainty(signal: s, background: b, time: t, backgroundFromEqualTime: eq)
                v["ld.\(k)"] = CountingStatistics.detectionLimit(backgroundCounts: bc, backgroundFromEqualTime: eq)
            }
            out.append(Case(name: "counting", inputs: ["s": "\(s)", "b": "\(b)", "u": "\(u)", "t": "\(t)", "bc": "\(bc)"], values: v))
        }

        // Beam arithmetic.
        for (i, q, charge, e) in [(100e-6, 1, 0.36, 400.0), (50e-6, 2, 1.0, 1200), (1e-9, 0, 1e-3, 30_000)] {
            let pps = Beam.particlesPerSecond(current: i, chargeState: q)
            out.append(Case(name: "beam", inputs: ["current": "\(i)", "q": "\(q)", "charge": "\(charge)", "energy": "\(e)"], values: [
                "pps": pps, "current": Beam.current(particlesPerSecond: pps, chargeState: q),
                "particles": Beam.particles(charge: charge, chargeState: q), "power": Beam.power(particlesPerSecond: pps, energy: e)]))
        }

        // Target yields from an S-factor model through SRIM targets: thin and thick layers, effective energies,
        // thick-target resonance yields. ε = stopping per active nucleus (eV cm²).
        let setups: [(String, String, Double, String, Double, Double, Double, String)] = [
            ("12C(p,g)13N", "element|6", 0.9893, "poly|1.5|0.002|0", 400, 300, 100, "421:0.0067"),
            ("14N(p,g)15O", "formula|TiN|5.22|0|0.97", 0.99636, "poly|1.6|-0.002|1e-5", 380, 500, 80, "259:0.0131"),
            ("12C(p,g)13N", "formula|C10H8O4|1.39|0|1", 0.9893, "table|" + tableA, 250, 50, 30, "421:0.0067"),
            ("3He(a,g)7Be", "gas|He|1|293.15", 1, "poly|0.56|-3.6e-4|3e-7", 1000, 1e9, 200, "1500:1e-3"),
        ]
        for (n, tspec, abundance, m, e1, thick, eThickExit, res) in setups {
            let r = try Reaction(notation: n)
            let c = ChargedChannel.entrance(r)
            let target = try target(tspec)
            let calc = StoppingCalculator(ion: StoppingIon(nuclide: r.projectile), target: target)
            let f = target.activeFraction(z: r.target.z, a: r.target.a, abundance: abundance)
            let eps: (Double) -> Double = { e in (try? calc.stopping(at: e)).map { $0.total * 1e-15 / f } ?? 0 }
            let model = try model(m)
            let loss = try calc.energyLoss(energy: e1, thickness: thick)
            let nt = target.activeArealDensity(z: r.target.z, a: r.target.a, abundance: abundance, thickness: thick, angle: 0) ?? -1
            var v: [String: Double] = ["f": f, "eps": eps(e1), "thinExit": loss.energyOut, "nt": nt]
            for ue in [0.0, 300] {
                let k = ue > 0 ? ".ue" : ""
                v["thinYield\(k)"] = c.targetYield(sFactor: model, entranceEnergy: e1, exitEnergy: loss.energyOut, screening: ue, stopping: eps)
                v["thinEff\(k)"] = c.effectiveEnergy(sFactor: model, entranceEnergy: e1, exitEnergy: loss.energyOut, screening: ue,
                                                     stopping: eps) ?? -1
                v["thickYield\(k)"] = c.targetYield(sFactor: model, entranceEnergy: e1, exitEnergy: eThickExit, screening: ue, stopping: eps)
                v["thickEff\(k)"] = c.effectiveEnergy(sFactor: model, entranceEnergy: e1, exitEnergy: eThickExit, screening: ue,
                                                      stopping: eps) ?? -1
            }
            v["thickYield.odd51"] = c.targetYield(sFactor: model, entranceEnergy: e1, exitEnergy: eThickExit, steps: 51, stopping: eps)
            v["thickEff.50"] = c.effectiveEnergy(sFactor: model, entranceEnergy: e1, exitEnergy: eThickExit, steps: 50, stopping: eps) ?? -1
            let emean = c.cmEnergy(lab: loss.meanEnergy)
            v["thinSimple"] = ChargedChannel.thinTargetYield(crossSection: c.crossSection(sFactor: model.s(at: emean), energy: emean),
                                                             arealDensity: nt)
            for (k, rr) in resonances(res).enumerated() {
                let eLab = c.labEnergy(cm: rr.energy)
                let y = c.thickTargetYield(resonanceEnergy: rr.energy, strength: rr.strength, effectiveStopping: eps(eLab))
                v["res\(k).elab"] = eLab
                v["res\(k).eps"] = eps(eLab)
                v["res\(k).lambda2"] = c.deBroglieHalfSquared(energy: rr.energy)
                v["res\(k).yield"] = y
                v["res\(k).wg"] = c.resonanceStrength(resonanceEnergy: rr.energy, yield: 2 * y, effectiveStopping: eps(eLab))
            }
            out.append(Case(name: "targetyield", inputs: ["reaction": n, "target": tspec, "abundance": "\(abundance)", "model": m,
                                                          "entrance": "\(e1)", "thickness": "\(thick)", "thickExit": "\(eThickExit)",
                                                          "resonances": res], values: v))
        }
        // Degenerate target-yield inputs.
        let c12 = ChargedChannel.entrance(try Reaction(notation: "12C(p,g)13N"))
        let flat = SFactorModel(kind: .polynomial, s0: 1.5)
        out.append(Case(name: "yield-edges", inputs: [:], values: [
            "reversed": c12.targetYield(sFactor: flat, entranceEnergy: 100, exitEnergy: 200) { _ in 1e-14 },
            "noStopping": c12.targetYield(sFactor: flat, entranceEnergy: 200, exitEnergy: 100) { _ in 0 },
            "noEff": c12.effectiveEnergy(sFactor: flat, entranceEnergy: 200, exitEnergy: 100) { _ in 0 } ?? -1,
            "constEps": c12.targetYield(sFactor: flat, entranceEnergy: 200, exitEnergy: 0) { _ in 1e-14 },
            "constEff": c12.effectiveEnergy(sFactor: flat, entranceEnergy: 200, exitEnergy: 0) { _ in 1e-14 } ?? -1,
        ]))

        // Resonance strengths from spins and widths.
        for (j, j1, j2, ga, gb, g) in [(1.5, 0.5, 0.0, 1.0, 0.5, 1.5), (2.0, 0.0, 0.0, 3e-3, 2e-3, 0.1), (0.5, 0.5, 1.0, 1.0, 1.0, 0)] {
            let w = NarrowResonance.spinFactor(j: j, j1: j1, j2: j2)
            out.append(Case(name: "strength", inputs: ["j": "\(j)", "j1": "\(j1)", "j2": "\(j2)", "ga": "\(ga)", "gb": "\(gb)", "g": "\(g)"],
                            values: ["omega": w, "wg": NarrowResonance.strength(omega: w, gammaA: ga, gammaB: gb, total: g)]))
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
        for (a, b) in zip(stored, cases) {
            #expect(a.name == b.name && a.inputs == b.inputs)
            #expect(Set(a.values.keys) == Set(b.values.keys), "\(a.name) \(a.inputs)")
            for (k, v) in a.values {
                let w = b.values[k] ?? .nan
                #expect(v == w || abs(v - w) <= 1e-9 * max(1, abs(v)), "\(a.name) \(a.inputs) \(k): \(v) vs \(w)")
            }
        }
    }
}
