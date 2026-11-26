package org.gamow

import kotlinx.serialization.json.*
import org.gamow.core.MassTable
import org.gamow.core.stopping.*
import java.io.File
import kotlin.math.abs
import kotlin.test.*

/**
 * The Kotlin stopping port must reproduce `Shared/reference_stopping.json`, which the Swift NucPhysKit writes and
 * checks (ReferenceStoppingTests.swift): SRIM-2013 stopping, ranges, energy loss and straggling, stacks, formulas.
 * Tolerance: 1e-9 relative to each value (stricter than the Swift check, which allows 1e-9 absolute below 1).
 */
class ReferenceStoppingTest {
    private val cases = Json.parseToJsonElement(File("../../Shared/reference_stopping.json").readText()).jsonArray

    private fun ion(spec: String): StoppingIon {
        val p = spec.split("|")
        return if (p[0] == "ame") StoppingIon(MassTable.ame2020.nuclide(p[1].toInt(), p[2].toInt())!!)
        else StoppingIon(p[1].toInt())
    }

    private fun target(spec: String): StoppingTarget {
        val p = spec.split("|")
        return when (p[0]) {
            "element" -> StoppingTarget.element(p[1].toInt())
            "elementgas" -> StoppingTarget.element(p[1].toInt(), gas = p[2] == "1")
            "compound" -> StoppingTarget.compound(SRIMData.shared.compounds.first { it.id == p[1] })
            "formula" -> StoppingTarget.formula(ChemicalFormula.parse(p[1]), p[2].toDouble(), p[3] == "1")
                .copy(compoundCorrection = p[4].toDouble())
            "gas" -> {
                val t = StoppingTarget.formula(ChemicalFormula.parse(p[1]), 1.0, gas = true)
                t.copy(density = GasTarget.density(t, p[2].toDouble(), p[3].toDouble(), GasTarget.defaultAtomsPerMolecule(t)))
            }
            else -> fail(spec)
        }
    }

    private fun lossValues(r: StoppingCalculator.EnergyLoss): Map<String, Double> {
        val mid = r.profile[r.profile.size / 2]
        return mapOf("out" to r.energyOut, "le" to r.electronicLoss, "ln" to r.nuclearLoss, "sigma" to r.sigma,
            "sigmaBohr" to r.sigmaBohr, "path" to r.pathLength, "mean" to r.meanEnergy,
            "stopped" to if (r.stopped) 1.0 else 0.0, "points" to r.profile.size.toDouble(),
            "midDepth" to mid.depth, "midE" to mid.energy, "midSigma" to mid.sigma)
    }

    private var checked = 0

    private fun check(name: String, inputs: JsonObject, expected: JsonObject, actual: Map<String, Double>) {
        assertEquals(expected.keys, actual.keys, "$name $inputs: keys")
        for ((k, v) in expected) {
            val want = v.jsonPrimitive.double
            val got = actual.getValue(k)
            assertTrue(want == got || abs(want - got) <= 1e-9 * abs(want), "$name $inputs $k: Swift $want, Kotlin $got")
            checked++
        }
    }

    @Test fun reproducesEverySwiftCase() {
        assertTrue(cases.size >= 800)
        val counts = HashMap<String, Int>()
        for (c in cases) {
            val o = c.jsonObject
            val name = o["name"]!!.jsonPrimitive.content
            counts[name] = (counts[name] ?: 0) + 1
            val inputs = o["inputs"]!!.jsonObject
            fun inp(k: String) = inputs[k]!!.jsonPrimitive.content
            val values = o["values"]!!.jsonObject
            val actual: Map<String, Double> = when (name) {
                "stopping" -> {
                    val t = target(inp("target"))
                    val calc = StoppingCalculator(ion(inp("ion")), t)
                    val e = inp("energy").toDouble()
                    val s = calc.stopping(e)
                    val l = calc.listModeStopping(e)
                    buildMap {
                        put("se", s.electronic); put("sn", s.nuclear); put("lse", l.electronic); put("lsn", l.nuclear)
                        for (u in StoppingUnit.entries) put("u${u.code}", calc.convert(s.total, u))
                        val c0 = t.components[0]
                        put("snu", SRIMStopping.universalNuclear(calc.ion.z, calc.ion.mass, c0.z, c0.mass, e))
                    }
                }
                "stopping-extra" -> {
                    val s = StoppingCalculator(ion(inp("ion")), target(inp("target"))).stopping(inp("energy").toDouble())
                    mapOf("se" to s.electronic, "sn" to s.nuclear)
                }
                "range" -> {
                    val r = StoppingCalculator(ion(inp("ion")), target(inp("target"))).range(inp("energy").toDouble())
                    mapOf("energy" to r.energy, "se" to r.electronic, "sn" to r.nuclear, "rp" to r.projectedRange,
                        "long" to r.longitudinalStraggling, "lat" to r.lateralStraggling)
                }
                "rangetable" -> {
                    val rows = StoppingCalculator(ion(inp("ion")), target(inp("target")))
                        .rangeTable(inp("emin").toDouble(), inp("emax").toDouble())
                    buildMap {
                        put("count", rows.size.toDouble())
                        listOf(0, rows.size / 3, rows.size / 2, rows.size - 1).forEachIndexed { k, idx ->
                            val r = rows[idx]
                            put("e$k", r.energy); put("rp$k", r.projectedRange); put("long$k", r.longitudinalStraggling)
                            put("lat$k", r.lateralStraggling); put("se$k", r.electronic); put("sn$k", r.nuclear)
                        }
                    }
                }
                "energyloss" -> lossValues(StoppingCalculator(ion(inp("ion")), target(inp("target")))
                    .energyLoss(inp("energy").toDouble(), inp("thickness").toDouble(), inp("angle").toDouble(),
                        inp("sigmaIn").toDouble()))
                "stack" -> {
                    val layers = inp("layers").split(";").map {
                        val q = it.split("@")
                        StackLayer(target(q[0]), q[1].toDouble())
                    }
                    val res = LayerStack.transport(ion(inp("ion")), layers, inp("energy").toDouble(), inp("angle").toDouble())
                    buildMap {
                        put("layers", res.size.toDouble())
                        res.forEachIndexed { k, r -> for ((key, x) in lossValues(r)) put("$k.$key", x) }
                    }
                }
                "formula" -> {
                    val f = ChemicalFormula.parse(inp("text"))
                    val t = StoppingTarget.formula(f, 2.5)
                    assertEquals(inp("label"), f.label)
                    assertEquals(inp("formulaLabel"), t.formulaLabel())
                    assertEquals(inp("formulaText"), t.formulaText())
                    assertEquals(inp("composition"), t.compositionLabel)
                    val apm = GasTarget.defaultAtomsPerMolecule(t)
                    buildMap {
                        put("parts", f.parts.size.toDouble()); put("meanMass", t.meanMass); put("meanZ", t.meanZ)
                        put("atomDensity", t.atomDensity); put("atomsPerA3", t.atomsPerA3); put("atomsPerMolecule", apm)
                        put("gasDensity", GasTarget.density(t, 3.0, 290.0, apm))
                        f.parts.forEachIndexed { k, p ->
                            put("z$k", p.z.toDouble()); put("a$k", (p.massNumber ?: -1).toDouble()); put("n$k", p.count)
                            put("mass$k", t.components[k].mass); put("frac$k", t.fractions[k])
                        }
                        for ((u, x) in listOf(ThicknessUnit.ANGSTROM to 1.0, ThicknessUnit.NANOMETRE to 1.0,
                            ThicknessUnit.MICROMETRE to 1.0, ThicknessUnit.MILLIMETRE to 1.0, ThicknessUnit.MICROGRAM_CM2 to 10.0,
                            ThicknessUnit.MILLIGRAM_CM2 to 1.0, ThicknessUnit.ATOMS_1E15 to 100.0)) {
                            put("thick.${u.symbol}", u.toAngstrom(x, t))
                            put("back.${u.symbol}", u.fromAngstrom(1000.0, t))
                        }
                        put("active", t.activeArealDensity(f.parts[0].z, f.parts[0].massNumber ?: 1, 0.5, 1000.0, 30.0) ?: -1.0)
                    }
                }
                "formula-error" -> {
                    val message = try { ChemicalFormula.parse(inp("text")); "ok" } catch (e: FormulaException) { e.message }
                    assertEquals(inp("error"), message, "formula ${inp("text")}")
                    emptyMap()
                }
                "compound" -> {
                    val cpd = SRIMData.shared.compounds.first { it.id == inp("id") }
                    val t = StoppingTarget.compound(cpd)
                    assertEquals(inp("display"), cpd.displayName)
                    assertEquals(inp("summary"), cpd.compositionSummary)
                    assertEquals(inp("formulaLabel"), t.formulaLabel())
                    assertEquals(inp("formulaText"), t.formulaText())
                    mapOf("count" to SRIMData.shared.compounds.size.toDouble(), "density" to t.density,
                        "gas" to if (t.isGas) 1.0 else 0.0, "meanMass" to t.meanMass, "atomDensity" to t.atomDensity)
                }
                else -> fail("unknown case $name")
            }
            check(name, inputs, values, actual)
        }
        println("ReferenceStoppingTest: ${cases.size} cases $counts, $checked values checked")
    }

    @Test fun errorsAndEdges() {
        // SRIM's phase correction overflows above ≈ 5.9 GeV/u (VB run-time error 6), as in Swift.
        val calc = StoppingCalculator(StoppingIon(1), StoppingTarget.element(14))
        val e = assertFailsWith<StoppingException> { calc.stopping(1e7) }
        assertEquals(StoppingError.ENERGY_TOO_HIGH, e.error)
        assertFailsWith<RangeException> { calc.rangeTable(0.0, 0.0) }
        assertNull(ChemicalFormula.parseOrNull("Ta2(N"))
        assertEquals(listOf(ChemicalFormula.Part(1, 2, 2.0), ChemicalFormula.Part(8, null, 1.0)), ChemicalFormula.parse("D2O").parts)
    }
}
