import Foundation
import Testing
@testable import NucPhysKit

/// One SR.IN input and the rows SRModule.exe (SRIM-2013) wrote for it; see Tools/convert_srim.py.
struct SRReference: Decodable {
    struct Element: Decodable { let z: Int; let stoich: Double; let mass: Double }
    let ionZ: Int
    let ionMass: Double
    let gas: Bool
    let density: Double
    let correction: Double
    let elements: [Element]
    let units: Int
    let emin: Double
    let emax: Double
    let list: [Double]
    let rows: [[Double]]

    var calculator: StoppingCalculator {
        StoppingCalculator(
            ion: StoppingIon(z: ionZ, mass: ionMass),
            target: StoppingTarget(name: "ref",
                                   components: elements.map { .init(z: $0.z, stoichiometry: $0.stoich, mass: $0.mass) },
                                   density: density, isGas: gas, compoundCorrection: correction))
    }

    static let all: [String: SRReference] = {
        let url = Bundle.module.url(forResource: "srim_reference", withExtension: "json")!
        return try! JSONDecoder().decode([String: SRReference].self, from: Data(contentsOf: url))
    }()
}

/// Relative deviation, allowing for the 4 significant figures SRModule.exe prints.
private func relDev(_ a: Double, _ b: Double) -> Double { b == 0 ? abs(a) : abs(a - b) / abs(b) }

@Suite("SRIM stopping (vs SRModule.exe)")
struct SRIMReferenceTests {
    static let listCases = SRReference.all.filter { !$0.value.list.isEmpty }.keys.sorted()
    static let tableCases = SRReference.all.filter { $0.value.list.isEmpty }.keys.sorted()

    @Test func referencesLoaded() {
        #expect(Self.listCases.count == 6)
        #expect(Self.tableCases.count == 18)
    }

    /// SR list mode: S_e and S_n at given energies, pair nuclear stopping.
    @Test(arguments: listCases)
    func listMode(_ name: String) throws {
        let ref = SRReference.all[name]!
        let calc = ref.calculator
        let unit = StoppingUnit(rawValue: ref.units)!
        for row in ref.rows {
            let s = try calc.listModeStopping(at: row[0])
            let se = calc.convert(s.electronic, to: unit), sn = calc.convert(s.nuclear, to: unit)
            #expect(relDev(se, row[1]) < 6e-4, "\(name) S_e at \(row[0]) keV: \(se) vs \(row[1])")
            #expect(relDev(sn, row[2]) < 6e-4, "\(name) S_n at \(row[0]) keV: \(sn) vs \(row[2])")
        }
    }

    /// SR table mode: stopping on SRIM's grid plus projected range and stragglings.
    @Test(arguments: tableCases)
    func tableMode(_ name: String) throws {
        let ref = SRReference.all[name]!
        let calc = ref.calculator
        let unit = StoppingUnit(rawValue: ref.units)!
        let rows = try calc.rangeTable(emin: ref.emin, emax: ref.emax)
        try #require(rows.count == ref.rows.count, "\(name): \(rows.count) rows vs \(ref.rows.count)")
        for (r, x) in zip(rows, ref.rows) {
            #expect(relDev(r.energy, x[0]) < 5e-3, "\(name) energy \(r.energy) vs \(x[0])")   // printed to 3 figures
            #expect(relDev(calc.convert(r.electronic, to: unit), x[1]) < 6e-4, "\(name) S_e at \(x[0]) keV")
            #expect(relDev(calc.convert(r.nuclear, to: unit), x[2]) < 6e-4, "\(name) S_n at \(x[0]) keV")
            // Lengths are printed as integers in Å or with 2 decimals in µm, mm, …
            for (mine, theirs) in [(r.projectedRange, x[3]), (r.longitudinalStraggling, x[4]), (r.lateralStraggling, x[5])] {
                let printStep = theirs < 1e4 ? 1.0 : (theirs < 1e7 ? 100 : (theirs < 1e10 ? 1e5 : 1e8))
                #expect(abs(mine - theirs) <= 0.5 * printStep + 1e-6 * theirs,
                        "\(name) length at \(x[0]) keV: \(mine) vs \(theirs) Å")
            }
        }
    }

    @Test func overflowAboveSRIMLimitThrows() {
        // SRModule.exe stops with VB run-time error 6 above ≈ 5.9 GeV/u (case HAu8G).
        let h = StoppingCalculator(ion: StoppingIon(z: 1, mass: 1.008), target: .element(79))
        #expect(throws: StoppingCalculator.RangeError.energyTooHigh) { try h.rangeTable(emin: 1e6, emax: 8e6) }
        #expect(throws: SRIMStopping.StoppingError.energyTooHigh) { try h.stopping(at: 7e6) }
    }
}

@Suite("Energy loss and straggling")
struct EnergyLossTests {
    /// LunaSRIM docs/physics.md §6, analytic column (exit energy, Ω in keV).
    @Test(arguments: [
        (1, 1.008, 14, 2.3212, false, 400.0, 1e4, 330.5, 4.48),      // H 400 keV, Si 1 µm
        (1, 1.008, 6, 2.253, false, 100.0, 3000, 50.1, 2.22),         // H 100 keV, C 300 nm
        (2, 4.003, 79, 19.311, false, 2000.0, 3000, 1799.8, 12.27),   // He 2 MeV, Au 300 nm
        (2, 4.003, 7, 0.001251, true, 300.0, 2e6, 258.5, 2.72),       // He 300 keV, N₂ gas 200 µm
        (6, 12.000, 28, 8.8955, false, 5000.0, 5000, 3486.2, 33.58),  // C 5 MeV, Ni 500 nm
    ])
    func againstLunaSRIM(_ c: (Int, Double, Int, Double, Bool, Double, Double, Double, Double)) throws {
        let (z1, m1, z2, rho, gas, e0, x, eOut, omega) = c
        let target = StoppingTarget(name: "t", components: [.init(z: z2, stoichiometry: 1, mass: SRIMData.shared.element(z2).naturalMass)],
                                    density: rho, isGas: gas)
        let r = try StoppingCalculator(ion: StoppingIon(z: z1, mass: m1), target: target)
            .energyLoss(energy: e0, thickness: x)
        #expect(abs(r.energyOut - eOut) < 0.15, "exit \(r.energyOut) vs \(eOut)")
        #expect(abs(r.sigma - omega) < 0.02, "Ω \(r.sigma) vs \(omega)")
        #expect(!r.stopped)
        #expect(abs(r.electronicLoss + r.nuclearLoss - r.energyLoss) < 1e-6 * e0)
        #expect(r.meanEnergy < e0 && r.meanEnergy > r.energyOut)
    }

    /// Thin layer: ΔE = S·x and the straggling tends to Bohr's value.
    @Test func thinLayerIsStoppingTimesThickness() throws {
        let calc = StoppingCalculator(ion: StoppingIon(z: 1, mass: 1.008), target: .element(14))
        let s = try calc.stopping(at: 1000)
        let x = 10.0  // Å
        let expected = s.total * 10 * calc.target.atomsPerA3 * x / 1000   // keV
        let r = try calc.energyLoss(energy: 1000, thickness: x)
        #expect(abs(r.energyLoss - expected) / expected < 1e-4)
    }

    @Test func ionsStopInThickLayer() throws {
        let calc = StoppingCalculator(ion: StoppingIon(z: 2, mass: 4.003), target: .element(79))
        let r = try calc.energyLoss(energy: 2000, thickness: 1e6)
        #expect(r.stopped)
    }

    @Test func compoundDictionary() throws {
        let data = SRIMData.shared
        #expect(data.compounds.count == 356)
        let mylar = try #require(data.compounds.first { $0.name.lowercased().hasPrefix("mylar") })
        let t = StoppingTarget.compound(mylar)
        #expect(abs(t.density - 1.397) < 0.01)
        #expect(Set(t.components.map(\.z)) == [1, 6, 8])
    }

    @Test func thicknessUnits() {
        let si = StoppingTarget.element(14)
        #expect(abs(ThicknessUnit.micrometre.toAngstrom(1, target: si) - 1e4) < 1e-9)
        let ug = ThicknessUnit.microgramCm2.toAngstrom(si.density * 100, target: si)   // 1 µm of Si in µg/cm²
        #expect(abs(ug - 1e4) < 1e-6)
        let back = ThicknessUnit.atoms1e15.fromAngstrom(1e4, target: si)
        #expect(abs(back - si.atomsPerA3 * 1e4 * 10) / back < 1e-12)
    }
}
