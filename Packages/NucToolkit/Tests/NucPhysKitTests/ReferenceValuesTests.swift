import Foundation
import Testing
@testable import NucPhysKit

/// Reference values shared with the Kotlin port (Android, Linux, Windows): `Shared/reference_values.json`.
/// This suite checks that the Swift code still reproduces the file; the Kotlin tests read the same file.
/// Regenerate after a deliberate physics change with `GAMOW_WRITE_REFERENCE=1 ./Tools/test.sh --filter ReferenceValues`.
@Suite("Shared reference values")
struct ReferenceValuesTests {
    struct Case: Codable, Equatable {
        var name: String
        var inputs: [String: String]
        var values: [String: Double]
    }

    static let fileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Shared/reference_values.json")

    static func compute() throws -> [Case] {
        var out: [Case] = []
        let reactions = ["12C(p,g)13N", "14N(p,g)15O", "3He(a,g)7Be", "7Li(p,a)4He", "7Li(p,n)7Be", "12C(12C,a)20Ne",
                         "p(7Be,g)8B", "d(d,n)3He", "13C(a,n)16O", "27Al(p,p)27Al", "197Au(a,a)197Au", "22Ne(a,n)25Mg"]
        for n in reactions {
            let r = try Reaction(notation: n)
            out.append(Case(name: "qvalue", inputs: ["reaction": n, "residual": r.residual.plainLabel],
                            values: ["q": r.qValue, "dq": r.qValueUncertainty, "threshold": r.threshold()]))
        }
        let kin: [(String, Double, Double, Double)] = [
            ("7Li(p,a)4He", 500, 0, 90), ("27Al(p,p)27Al", 1000, 0, 135), ("12C(p,g)13N", 400, 0, 45),
            ("14N(p,g)15O", 400, 6176.3, 0), ("p(12C,p)12C", 12000, 0, 3), ("7Li(p,n)7Be", 1900, 0, 0),
            ("13C(a,n)16O", 5500, 6049, 30), ("12C(12C,a)20Ne", 5000, 1633.674, 10),
        ]
        for (n, e, ex, angle) in kin {
            let r = try Reaction(notation: n)
            let k = TwoBodyKinematics(reaction: r, beamEnergy: e, residualExcitation: ex)
            var v: [String: Double] = ["ecm": k.centerOfMassEnergy, "beta": k.beta, "pstar": k.pStar,
                                       "maxangle": k.maxEjectileAngle.map { $0 * 180 / .pi } ?? -1]
            for (i, s) in k.solutions(labAngle: angle * .pi / 180).enumerated() {
                v["e\(i)"] = s.ejectileEnergy; v["thcm\(i)"] = s.thetaCM * 180 / .pi
                v["jac\(i)"] = s.jacobian; v["er\(i)"] = s.residualEnergy; v["thr\(i)"] = s.residualAngle * 180 / .pi
            }
            v["branches"] = Double(k.solutions(labAngle: angle * .pi / 180).count)
            out.append(Case(name: "kinematics", inputs: ["reaction": n, "beam": "\(e)", "ex": "\(ex)", "angle": "\(angle)"], values: v))
        }
        let astro: [(String, Double, Double)] = [("12C(p,g)13N", 100, 0.03), ("3He(a,g)7Be", 50, 0.015),
                                                  ("14N(p,g)15O", 30, 0.06), ("12C(a,g)16O", 300, 0.2), ("d(p,g)3He", 10, 0.015)]
        for (n, e, t9) in astro {
            let r = try Reaction(notation: n)
            let c = ChargedChannel.entrance(r)
            let w = c.gamowWindow(t9: t9)
            out.append(Case(name: "astro", inputs: ["reaction": n, "energy": "\(e)", "t9": "\(t9)"], values: [
                "mu": c.reducedMass, "eta": c.sommerfeld(e), "gamowEnergy": c.gamowEnergy, "e0": w.peak, "delta": w.width,
                "sigmaFromS1": c.crossSection(sFactor: 1, energy: e), "sFromSigma1nb": c.sFactor(crossSection: 1e-9, energy: e),
                "screening300": c.screeningFactor(energy: e, potential: 300), "wigner": c.wignerLimit(radius: c.radius(r0: 1.25)),
                "elab": c.labEnergy(cm: e),
            ]))
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
