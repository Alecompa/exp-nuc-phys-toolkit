import Foundation
import Testing
@testable import NucPhysKit

/// NUBASE2020, decay arithmetic and calibration sources shared with the Kotlin port: `Shared/reference_decay.json`.
/// Regenerate with `GAMOW_WRITE_REFERENCE=1 ./Tools/test.sh --filter ReferenceDecay`.
@Suite("Shared reference values: decay")
struct ReferenceDecayTests {
    static let fileURL = ReferenceValuesTests.fileURL.deletingLastPathComponent().appendingPathComponent("reference_decay.json")

    static func compute() -> [ReferenceValuesTests.Case] {
        var out: [ReferenceValuesTests.Case] = []
        let nb = Nubase.nubase2020
        out.append(.init(name: "nubase", inputs: [:], values: ["states": Double(nb.states.count),
            "radioactive": Double(nb.states.filter { ($0.halfLife ?? 0).isFinite && ($0.halfLife ?? 0) > 0 }.count)]))
        for n in ["60Co", "137Cs", "26mAl", "178m2Hf", "166mHo", "241Am", "3H", "14N", "238U", "8Be", "7Be"] {
            guard let s = nb.state(named: n) else { continue }
            out.append(.init(name: "state", inputs: ["nuclide": n, "label": s.plainLabel, "modes": s.decayModes.map(\.text).joined(separator: "; ")],
                             values: ["z": Double(s.z), "a": Double(s.a), "state": Double(s.state), "excitation": s.excitation,
                                      "halfLife": s.halfLife.map { $0.isFinite ? $0 : -1 } ?? -2, "halfLifeUnc": s.halfLifeUncertainty ?? -2,
                                      "abundance": s.abundance ?? -2]))
        }
        for (n, a0, t) in [("60Co", 1e4, 3.0e8), ("137Cs", 3.7e4, 1.0e9), ("22Na", 1e5, 5e7), ("26mAl", 1e3, 10.0)] {
            let s = nb.state(named: n)!
            let h = s.halfLife!
            out.append(.init(name: "decay", inputs: ["nuclide": n, "a0": "\(a0)", "t": "\(t)"], values: [
                "activity": RadioactiveDecay.activity(initial: a0, elapsed: t, halfLife: h),
                "relUnc": RadioactiveDecay.relativeActivityUncertainty(elapsed: t, halfLife: h, halfLifeUncertainty: s.halfLifeUncertainty ?? 0),
                "atoms": RadioactiveDecay.atoms(activity: a0, halfLife: h),
                "tenth": RadioactiveDecay.time(toFraction: 0.1, halfLife: h)]))
        }
        for src in CalibrationSources.all {
            var v: [String: Double] = ["lines": Double(src.lines.count)]
            for (i, l) in src.prominentLines(minIntensity: 5).prefix(4).enumerated() { v["e\(i)"] = l.energy; v["i\(i)"] = l.intensity }
            out.append(.init(name: "source", inputs: ["nuclide": src.id], values: v))
        }
        return out
    }

    @Test func swiftReproducesSharedFile() throws {
        let cases = Self.compute()
        if ProcessInfo.processInfo.environment["GAMOW_WRITE_REFERENCE"] == "1" {
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(cases).write(to: Self.fileURL)
        }
        let stored = try JSONDecoder().decode([ReferenceValuesTests.Case].self, from: Data(contentsOf: Self.fileURL))
        #expect(stored == cases)
    }
}
