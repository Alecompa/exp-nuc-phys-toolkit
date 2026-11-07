import Foundation
import Testing
@testable import NucPhysKit

@Suite("Chemical formulas")
struct ChemicalFormulaTests {
    private func counts(_ text: String) throws -> [String: Double] {
        let f = try ChemicalFormula(text)
        return Dictionary(uniqueKeysWithValues: f.parts.map {
            (ChemicalFormula.symbol(z: $0.z, massNumber: $0.massNumber), $0.count)
        })
    }

    @Test func simpleAndArbitraryStoichiometry() throws {
        #expect(try counts("Ta2N3") == ["Ta": 2, "N": 3])
        #expect(try counts("Ta2O5") == ["Ta": 2, "O": 5])
        #expect(try counts("Ti0.5Al0.5N") == ["Ti": 0.5, "Al": 0.5, "N": 1])
        #expect(try counts(" Si O 2 ") == ["Si": 1, "O": 2])
        #expect(try ChemicalFormula("Ta2N3").label == "Ta₂N₃")
    }

    @Test func groupsAndHydrates() throws {
        #expect(try counts("Ca(OH)2") == ["Ca": 1, "O": 2, "H": 2])
        #expect(try counts("Al2(SO4)3") == ["Al": 2, "S": 3, "O": 12])
        #expect(try counts("CuSO4·5H2O") == ["Cu": 1, "S": 1, "O": 9, "H": 10])
        #expect(try counts("CuSO4*5H2O") == ["Cu": 1, "S": 1, "O": 9, "H": 10])
    }

    @Test func isotopes() throws {
        #expect(try counts("TiD2") == ["Ti": 1, "D": 2])
        #expect(try counts("Ta2[17O]5") == ["Ta": 2, "¹⁷O": 5])
        #expect(try counts("H2O") == ["H": 2, "O": 1])
        let t = StoppingTarget.formula(try ChemicalFormula("TiD2"), density: 3.9)
        let d = try #require(t.components.first { $0.z == 1 })
        #expect(abs(d.mass - 2.0141) < 1e-3)
        #expect(t.formulaLabel() == "TiD₂")
        #expect(t.formulaText() == "TiD2")
        let o = StoppingTarget.formula(try ChemicalFormula("Ta2[17O]5"), density: 8.2)
        #expect(o.formulaText() == "Ta2[17O]5")
        #expect(try ChemicalFormula(o.formulaText()) == ChemicalFormula("Ta2[17O]5"))
    }

    @Test func errors() {
        #expect(throws: ChemicalFormula.ParseError.empty) { try ChemicalFormula("  ") }
        #expect(throws: ChemicalFormula.ParseError.unknownSymbol("Xx")) { try ChemicalFormula("Xx2") }
        #expect(throws: ChemicalFormula.ParseError.unbalancedParentheses) { try ChemicalFormula("Ca(OH2") }
        #expect(throws: ChemicalFormula.ParseError.outOfRange("Pu")) { try ChemicalFormula("PuO2") }
        #expect(throws: ChemicalFormula.ParseError.unknownIsotope("99O")) { try ChemicalFormula("[99O]") }
        #expect(throws: (any Error).self) { try ChemicalFormula("ta2n3") }
    }

    /// A formula target gives the same stopping as SRIM's dictionary entry of that compound.
    @Test func formulaMatchesDictionary() throws {
        let water = try #require(SRIMData.shared.compounds.first { $0.name.contains("Water") && !$0.gas })
        let a = StoppingTarget.compound(water)
        let b = StoppingTarget.formula(try ChemicalFormula("H2O"), density: water.density)
        let ion = StoppingIon(z: 1)
        let sa = try StoppingCalculator(ion: ion, target: a).stopping(at: 500)
        let sb = try StoppingCalculator(ion: ion, target: b).stopping(at: 500)
        #expect(abs(sa.total - sb.total) / sa.total < 1e-6)
        #expect(abs(a.atomDensity - b.atomDensity) / a.atomDensity < 1e-3)
    }
}

@Suite("Layer stacks and gas targets")
struct LayerStackTests {
    let ion = StoppingIon(z: 1)
    let al = StoppingTarget.element(13)

    /// Two halves of a layer give the same exit energy and straggling as the whole layer.
    @Test func splitLayerEqualsWhole() throws {
        let whole = try StoppingCalculator(ion: ion, target: al).energyLoss(energy: 1000, thickness: 20_000)
        let halves = try LayerStack.transport(ion: ion, layers: [StackLayer(target: al, thickness: 10_000),
                                                                 StackLayer(target: al, thickness: 10_000)],
                                              energy: 1000)
        #expect(halves.count == 2)
        #expect(abs(halves[1].energyOut - whole.energyOut) < 0.01)
        #expect(abs(halves[1].sigma - whole.sigma) / whole.sigma < 0.01)
        #expect(halves[1].energyIn == halves[0].energyOut)
    }

    /// The beam stops in a thick backing; later layers are not reached.
    @Test func stopsInBacking() throws {
        let ta = StoppingTarget.element(73)
        let r = try LayerStack.transport(ion: ion, layers: [StackLayer(target: al, thickness: 1000),
                                                            StackLayer(target: ta, thickness: 1e7),
                                                            StackLayer(target: al, thickness: 1000)],
                                         energy: 400)
        #expect(r.count == 2)
        #expect(r[1].stopped)
    }

    /// N₂ at 0 °C and 1 atm has SRIM's gas density of nitrogen, 1.251 mg/cm³.
    @Test func gasDensityFromPressure() {
        let n = StoppingTarget.element(7)
        let apm = GasTarget.defaultAtomsPerMolecule(n)
        #expect(apm == 2)
        let rho = GasTarget.density(of: n, pressure: 1013.25, temperature: 273.15, atomsPerMolecule: apm)
        #expect(abs(rho - 1.2506e-3) / 1.2506e-3 < 2e-3)
        var t = n
        t.density = rho
        // 1 mbar of He over 10 cm: p/kT·L
        let he = StoppingTarget.element(2)
        let n1 = GasTarget.atomDensity(pressure: 1, temperature: 293.15, atomsPerMolecule: 1)
        var h = he
        h.density = GasTarget.density(of: he, pressure: 1, temperature: 293.15, atomsPerMolecule: 1)
        #expect(abs(h.atomDensity - n1) / n1 < 1e-12)
        #expect(abs(ThicknessUnit.atoms1e15.fromAngstrom(1e9, target: h) - n1 * 10 / 1e15) / (n1 * 10 / 1e15) < 1e-3)
        #expect(t.atomDensity > 0)
    }
}

@Suite("Formula labels")
struct FormulaLabelTests {
    @Test func dictionaryFractionsBecomeIntegerRatios() throws {
        func compound(_ s: String) throws -> StoppingTarget {
            .compound(try #require(SRIMData.shared.compounds.first { $0.displayName.hasPrefix(s) }))
        }
        #expect(try compound("LiF").formulaLabel() == "LiF")
        #expect(try compound("Kapton").formulaText() == "H10C22N2O5")
        let tialn = StoppingTarget.formula(try ChemicalFormula("Ti0.5Al0.5N"), density: 4)
        #expect(tialn.formulaText() == "Ti0.5Al0.5N")
    }
}
