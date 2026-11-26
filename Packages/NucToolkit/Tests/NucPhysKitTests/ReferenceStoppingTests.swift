import Foundation
import Testing
@testable import NucPhysKit

/// SRIM-2013 stopping reference values shared with the Kotlin port: `Shared/reference_stopping.json`.
/// Same mechanism as `ReferenceValuesTests`: this suite checks the Swift code against the file, the Kotlin test
/// `ReferenceStoppingTest` reads the same file. Regenerate after a deliberate change with
/// `GAMOW_WRITE_REFERENCE=1 ./Tools/test.sh --filter ReferenceStopping`.
@Suite("Shared stopping reference values")
struct ReferenceStoppingTests {
    struct Case: Codable, Equatable {
        var name: String
        var inputs: [String: String]
        var values: [String: Double]
    }

    static let fileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Shared/reference_stopping.json")

    /// "srim|Z" (SRIM's most abundant isotope) or "ame|Z|A" (AME2020 atomic mass).
    static func ion(_ spec: String) -> StoppingIon {
        let p = spec.split(separator: "|").map(String.init)
        if p[0] == "ame" { return StoppingIon(nuclide: MassTable.ame2020.nuclide(z: Int(p[1])!, a: Int(p[2])!)!) }
        return StoppingIon(z: Int(p[1])!)
    }

    /// "element|Z", "elementgas|Z|0/1", "compound|<id>", "formula|text|density|gas|correction", "gas|text|mbar|K".
    static func target(_ spec: String) throws -> StoppingTarget {
        let p = spec.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        switch p[0] {
        case "element": return .element(Int(p[1])!)
        case "elementgas": return .element(Int(p[1])!, gas: p[2] == "1")
        case "compound": return .compound(SRIMData.shared.compounds.first { $0.id == p[1] }!)
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

    /// Composition labels use the current locale's decimal separator; the file stores them with ".".
    static func dot(_ s: String) -> String { s.replacingOccurrences(of: ",", with: ".") }

    static let ions = ["srim|1", "srim|2", "srim|6", "srim|8", "ame|2|4"]
    static let targets = [
        "element|1", "element|6", "element|13", "element|14", "element|29", "element|73", "element|79",
        "elementgas|7|0", "elementgas|29|1",
        "compound|Numbered Compounds/Tantalum pentoxide  (ICRU-620)",
        "compound|Nuclear Physics Materials/Water_Liquid (ICRU-276)",
        "compound|Plastics / Polymers/Kapton Polyimide Film (ICRU-179)",
        "compound|Plastics / Polymers/Mylar (ICRU-222)",
        "compound|Nuclear Physics Materials/Air, Dry (ICRU-104)",
        "compound|Liquids / Gases/Nitrogen",
        "formula|Ta2O5|8.2|0|1", "formula|TiN|5.22|0|0.97", "formula|Ta2[17O]5|8.2|0|1",
        "gas|He|1|293.15", "gas|N2|2.5|300",
    ]
    static let energies: [Double] = [1, 10, 50, 200, 1000, 3000, 10_000]

    static func compute() throws -> [Case] {
        var out: [Case] = []

        // Stopping at energy: Bragg sum, list mode, unit conversions, ZBL universal nuclear.
        for i in ions {
            for t in targets {
                let target = try target(t)
                let calc = StoppingCalculator(ion: ion(i), target: target)
                for e in energies {
                    let s = try calc.stopping(at: e)
                    let l = try calc.listModeStopping(at: e)
                    var v: [String: Double] = ["se": s.electronic, "sn": s.nuclear, "lse": l.electronic, "lsn": l.nuclear]
                    for u in StoppingUnit.allCases { v["u\(u.rawValue)"] = calc.convert(s.total, to: u) }
                    let c = target.components[0]
                    v["snu"] = SRIMStopping.universalNuclear(z1: calc.ion.z, m1: calc.ion.mass, z2: c.z, m2: c.mass, energy: e)
                    out.append(Case(name: "stopping", inputs: ["ion": i, "target": t, "energy": "\(e)"], values: v))
                }
            }
        }
        // Heavy ions above 30 MeV/u (high-energy effective charge) and light ions above the fit range.
        for (i, t, e) in [("srim|8", "element|79", 600_000.0), ("srim|6", "element|14", 400_000.0),
                          ("srim|1", "element|13", 1_100.0), ("srim|1", "element|13", 50_000.0),
                          ("srim|2", "element|29", 9_000.0), ("srim|2", "gas|He|1|293.15", 100_000.0),
                          ("srim|3", "element|6", 5_000.0), ("srim|3", "element|6", 0.5)] {
            let s = try StoppingCalculator(ion: ion(i), target: target(t)).stopping(at: e)
            out.append(Case(name: "stopping-extra", inputs: ["ion": i, "target": t, "energy": "\(e)"],
                            values: ["se": s.electronic, "sn": s.nuclear]))
        }

        // Ranges (SR module PRAL integration).
        for i in ions.prefix(4) {
            for t in ["element|6", "element|14", "element|79", "compound|Numbered Compounds/Tantalum pentoxide  (ICRU-620)",
                      "compound|Nuclear Physics Materials/Water_Liquid (ICRU-276)", "gas|N2|2.5|300", "formula|TiN|5.22|0|0.97"] {
                let calc = StoppingCalculator(ion: ion(i), target: try target(t))
                for e in [10.0, 300, 2000, 8000] {
                    let r = try calc.range(at: e)
                    out.append(Case(name: "range", inputs: ["ion": i, "target": t, "energy": "\(e)"], values: [
                        "energy": r.energy, "se": r.electronic, "sn": r.nuclear, "rp": r.projectedRange,
                        "long": r.longitudinalStraggling, "lat": r.lateralStraggling]))
                }
            }
        }
        for (i, t, lo, hi) in [("srim|1", "element|14", 10.0, 3000.0), ("srim|2", "element|79", 1.0, 10_000.0),
                               ("srim|8", "compound|Plastics / Polymers/Kapton Polyimide Film (ICRU-179)", 20.0, 20_000.0)] {
            let rows = try StoppingCalculator(ion: ion(i), target: try target(t)).rangeTable(emin: lo, emax: hi)
            var v: [String: Double] = ["count": Double(rows.count)]
            for (k, idx) in [0, rows.count / 3, rows.count / 2, rows.count - 1].enumerated() {
                let r = rows[idx]
                v["e\(k)"] = r.energy; v["rp\(k)"] = r.projectedRange; v["long\(k)"] = r.longitudinalStraggling
                v["lat\(k)"] = r.lateralStraggling; v["se\(k)"] = r.electronic; v["sn\(k)"] = r.nuclear
            }
            out.append(Case(name: "rangetable", inputs: ["ion": i, "target": t, "emin": "\(lo)", "emax": "\(hi)"], values: v))
        }

        // Energy loss and straggling through single layers (thickness Å, angle °, incoming σ keV).
        func lossValues(_ r: StoppingCalculator.EnergyLoss) -> [String: Double] {
            ["out": r.energyOut, "le": r.electronicLoss, "ln": r.nuclearLoss, "sigma": r.sigma, "sigmaBohr": r.sigmaBohr,
             "path": r.pathLength, "mean": r.meanEnergy, "stopped": r.stopped ? 1 : 0, "points": Double(r.profile.count),
             "midDepth": r.profile[r.profile.count / 2].depth, "midE": r.profile[r.profile.count / 2].energy,
             "midSigma": r.profile[r.profile.count / 2].sigma]
        }
        let layers: [(String, String, Double, Double, Double, Double)] = [
            ("srim|1", "element|79", 400, 1000, 0, 0), ("srim|1", "element|79", 400, 1000, 45, 0),
            ("srim|2", "compound|Numbered Compounds/Tantalum pentoxide  (ICRU-620)", 1500, 2000, 55, 1.5),
            ("srim|1", "formula|TiN|5.22|0|0.97", 250, 1500, 0, 0),
            ("srim|6", "element|6", 3000, 500, 30, 0),
            ("srim|8", "compound|Plastics / Polymers/Mylar (ICRU-222)", 10_000, 20_000, 0, 5),
            ("srim|2", "gas|He|1|293.15", 400, 1e9, 0, 0),
            ("srim|1", "gas|N2|2.5|300", 300, 5e8, 0, 0.2),
            ("srim|1", "element|14", 100, 20_000, 0, 0),                     // stops in the layer
            ("ame|2|4", "compound|Plastics / Polymers/Kapton Polyimide Film (ICRU-179)", 5000, 75_000, 20, 0),
        ]
        for (i, t, e, thick, angle, sig) in layers {
            let r = try StoppingCalculator(ion: ion(i), target: try target(t))
                .energyLoss(energy: e, thickness: thick, angle: angle, sigmaIn: sig)
            out.append(Case(name: "energyloss", inputs: ["ion": i, "target": t, "energy": "\(e)", "thickness": "\(thick)",
                                                         "angle": "\(angle)", "sigmaIn": "\(sig)"], values: lossValues(r)))
        }

        // Layer stacks: layers separated by ';' as "target spec@thickness".
        let stacks: [(String, String, Double, Double)] = [
            ("srim|1", "element|6@200;formula|Ta2O5|8.2|0|1@1500;element|73@5000", 600, 0),
            ("srim|2", "compound|Plastics / Polymers/Mylar (ICRU-222)@20000;gas|He|1|293.15@1e9;element|79@3000", 4000, 30),
            ("srim|1", "element|79@5000;element|79@200000;element|29@1000", 300, 0),   // stops in the second layer
        ]
        for (i, spec, e, angle) in stacks {
            let ls = try spec.split(separator: ";").map { part -> StackLayer in
                let q = part.split(separator: "@").map(String.init)
                return StackLayer(target: try target(q[0]), thickness: Double(q[1])!)
            }
            let res = try LayerStack.transport(ion: ion(i), layers: ls, energy: e, angle: angle)
            var v: [String: Double] = ["layers": Double(res.count)]
            for (k, r) in res.enumerated() {
                for (key, x) in lossValues(r) { v["\(k).\(key)"] = x }
            }
            out.append(Case(name: "stack", inputs: ["ion": i, "layers": spec, "energy": "\(e)", "angle": "\(angle)"], values: v))
        }

        // Chemical formulas, their targets and labels.
        for text in ["Ta2N5", "Ca(OH)2", "Ta2[17O]5", "CuSO4·5H2O", "CuSO4*5H2O", "TiD2", "Ti0.5Al0.5N", "Mg(NO3)2.6H2O",
                     "C10H8O4", "LiF", "[6Li]F", "H2O", "N2", "He"] {
            let f = try ChemicalFormula(text)
            let t = StoppingTarget.formula(f, density: 2.5)
            var v: [String: Double] = ["parts": Double(f.parts.count), "meanMass": t.meanMass, "meanZ": t.meanZ,
                                       "atomDensity": t.atomDensity, "atomsPerA3": t.atomsPerA3,
                                       "atomsPerMolecule": GasTarget.defaultAtomsPerMolecule(t),
                                       "gasDensity": GasTarget.density(of: t, pressure: 3, temperature: 290,
                                                                       atomsPerMolecule: GasTarget.defaultAtomsPerMolecule(t))]
            for (k, p) in f.parts.enumerated() {
                v["z\(k)"] = Double(p.z); v["a\(k)"] = Double(p.massNumber ?? -1); v["n\(k)"] = p.count
                v["mass\(k)"] = t.components[k].mass; v["frac\(k)"] = t.fractions[k]
            }
            for (u, x) in [(ThicknessUnit.angstrom, 1.0), (.nanometre, 1), (.micrometre, 1), (.millimetre, 1),
                           (.microgramCm2, 10), (.milligramCm2, 1), (.atoms1e15, 100)] {
                v["thick.\(u.rawValue)"] = u.toAngstrom(x, target: t)
                v["back.\(u.rawValue)"] = u.fromAngstrom(1000, target: t)
            }
            v["active"] = t.activeArealDensity(z: f.parts[0].z, a: f.parts[0].massNumber ?? 1, abundance: 0.5,
                                               thickness: 1000, angle: 30) ?? -1
            out.append(Case(name: "formula", inputs: ["text": text, "label": f.label, "formulaLabel": t.formulaLabel(),
                                                      "formulaText": t.formulaText(), "composition": Self.dot(t.compositionLabel)],
                            values: v))
        }
        for text in ["", "Ta2(N", "Xx2", "[300O]5", "Ta2#", "Ta]", "Uuo"] {
            var message = "ok"
            do { _ = try ChemicalFormula(text) } catch let e as ChemicalFormula.ParseError { message = e.errorDescription ?? "?" }
            out.append(Case(name: "formula-error", inputs: ["text": text, "error": message], values: [:]))
        }
        // Compound library: labels of dictionary entries (atom fractions → integer ratios).
        for id in ["Numbered Compounds/Tantalum pentoxide  (ICRU-620)", "Nuclear Physics Materials/Water_Liquid (ICRU-276)",
                   "Plastics / Polymers/Kapton Polyimide Film (ICRU-179)", "Nuclear Physics Materials/Air, Dry (ICRU-104)"] {
            let c = SRIMData.shared.compounds.first { $0.id == id }!
            let t = StoppingTarget.compound(c)
            out.append(Case(name: "compound", inputs: ["id": id, "display": c.displayName, "summary": Self.dot(c.compositionSummary),
                                                       "formulaLabel": t.formulaLabel(), "formulaText": t.formulaText()],
                            values: ["count": Double(SRIMData.shared.compounds.count), "density": t.density,
                                     "gas": t.isGas ? 1 : 0, "meanMass": t.meanMass, "atomDensity": t.atomDensity]))
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
                #expect(abs(v - w) <= 1e-9 * max(1, abs(v)), "\(a.name) \(a.inputs) \(k): \(v) vs \(w)")
            }
        }
    }
}
