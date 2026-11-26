package org.gamow

import kotlinx.serialization.json.*
import org.gamow.core.*
import org.gamow.core.astro.*
import org.gamow.core.runplanning.*
import org.gamow.core.stopping.*
import java.io.File
import kotlin.math.PI
import kotlin.math.abs
import kotlin.test.*

/**
 * The Kotlin astro and run-planning port must reproduce `Shared/reference_astro.json`, which the Swift NucPhysKit
 * writes and checks (ReferenceAstroTests.swift): reaction rates, penetrabilities and shifts, Rutherford
 * scattering, counting statistics, beam arithmetic, target and resonance yields through SRIM targets.
 * Tolerance: 1e-9 relative to each value.
 */
class ReferenceAstroTest {
    private val cases = Json.parseToJsonElement(File("../../Shared/reference_astro.json").readText()).jsonArray

    private fun model(spec: String): SFactorModel {
        val p = spec.split("|", limit = 2)
        if (p[0] == "table") return SFactorModel(SFactorModel.Kind.TABLE, table = SFactorModel.parseTable(p[1]))
        val q = spec.split("|").map { it.toDoubleOrNull() ?: 0.0 }
        return SFactorModel(SFactorModel.Kind.POLYNOMIAL, q[1], q[2], q[3])
    }

    private fun resonances(spec: String) = spec.split(";").filter { it.isNotEmpty() }.map {
        val q = it.split(":").map(String::toDouble)
        NarrowResonance(q[0], q[1])
    }

    private fun target(spec: String): StoppingTarget {
        val p = spec.split("|")
        return when (p[0]) {
            "element" -> StoppingTarget.element(p[1].toInt())
            "formula" -> StoppingTarget.formula(ChemicalFormula.parse(p[1]), p[2].toDouble(), p[3] == "1")
                .copy(compoundCorrection = p[4].toDouble())
            "gas" -> {
                val t = StoppingTarget.formula(ChemicalFormula.parse(p[1]), 1.0, gas = true)
                t.copy(density = GasTarget.density(t, p[2].toDouble(), p[3].toDouble(), GasTarget.defaultAtomsPerMolecule(t)))
            }
            else -> fail(spec)
        }
    }

    private fun nuclide(spec: String): Nuclide {
        val p = spec.split("|").map(String::toInt)
        return MassTable.ame2020.nuclide(p[0], p[1])!!
    }

    private var checked = 0
    private var maxRel = 0.0

    private fun check(name: String, inputs: JsonObject, expected: JsonObject, actual: Map<String, Double>) {
        assertEquals(expected.keys, actual.keys, "$name $inputs: keys")
        for ((k, v) in expected) {
            val want = v.jsonPrimitive.double
            val got = actual.getValue(k)
            assertTrue(want == got || abs(want - got) <= 1e-9 * abs(want), "$name $inputs $k: Swift $want, Kotlin $got")
            if (want != got) maxRel = maxOf(maxRel, abs(want - got) / abs(want))
            checked++
        }
    }

    @Test fun reproducesEverySwiftCase() {
        assertTrue(cases.size >= 190)
        val counts = HashMap<String, Int>()
        for (c in cases) {
            val o = c.jsonObject
            val name = o["name"]!!.jsonPrimitive.content
            counts[name] = (counts[name] ?: 0) + 1
            val inputs = o["inputs"]!!.jsonObject
            fun inp(k: String) = inputs[k]!!.jsonPrimitive.content
            fun d(k: String) = inp(k).toDouble()
            val values = o["values"]!!.jsonObject
            val actual: Map<String, Double> = when (name) {
                "rate" -> {
                    val ch = ChargedChannel.entrance(Reaction.parse(inp("reaction")))
                    val m = model(inp("model"))
                    val res = resonances(inp("resonances"))
                    buildMap {
                        ChargedChannel.rateGrid.forEachIndexed { i, t9 ->
                            put("r$i", ch.rate(m, t9))
                            res.forEachIndexed { k, r -> put("nr$k.$i", ch.narrowResonanceRate(r, t9)) }
                        }
                        put("r1000pts.T9=0.05", ch.rate(m, 0.05, points = 1001))
                        put("grid", ChargedChannel.rateGrid.size.toDouble())
                    }
                }
                "sfactor" -> {
                    val m = model(inp("model"))
                    assertEquals(inp("text"), m.tableText)
                    buildMap {
                        put("points", m.table.size.toDouble())
                        put("lo", m.tableRange?.start ?: -1.0); put("hi", m.tableRange?.endInclusive ?: -1.0)
                        listOf(0.0, 5.0, 20.0, 35.0, 100.0, 150.0, 400.0, 999.0, 1250.0, 1750.0, 2200.0, 5000.0)
                            .forEachIndexed { i, e -> put("s$i", m.s(e)) }
                    }
                }
                "sfactor-parse" -> {
                    var message = "ok"; var text = ""
                    try { text = SFactorModel(SFactorModel.Kind.TABLE, table = SFactorModel.parseTable(inp("text"))).tableText }
                    catch (e: SFactorParseException) { message = e.message }
                    assertEquals(inp("error"), message, "parse ${inp("text")}")
                    assertEquals(inp("tableText"), text, "tableText ${inp("text")}")
                    emptyMap()
                }
                "penetrability" -> {
                    val r = Reaction.parse(inp("reaction"))
                    val ch = if (inp("side") == "exit") ChargedChannel.exit(r)!! else ChargedChannel.entrance(r)
                    val p = ch.penetrability(inp("l").toInt(), d("energy"), d("radius"))
                    mapOf("P" to p.penetrability, "lnP" to p.lnP, "shift" to p.shift, "rho" to p.rho, "eta" to p.eta)
                }
                "coulomb" -> {
                    val p = CoulombFunctions.penetrability(inp("l").toInt(), d("eta"), d("rho"))
                    mapOf("P" to p.penetrability, "lnP" to p.lnP, "shift" to p.shift)
                }
                "rutherford" -> {
                    val rs = RutherfordScattering(nuclide(inp("projectile")), nuclide(inp("target")), d("energy"))
                    val pts = rs.at(d("angle") * PI / 180)
                    buildMap {
                        put("branches", pts.size.toDouble()); put("ecm", rs.kinematics.centerOfMassEnergy)
                        put("cm90", rs.crossSectionCM(PI / 2))
                        pts.forEachIndexed { i, p ->
                            put("th$i", p.thetaCM); put("e$i", p.energy); put("cm$i", p.crossSectionCM); put("lab$i", p.crossSectionLab)
                        }
                    }
                }
                "counting" -> buildMap {
                    for (eq in listOf(true, false)) {
                        val k = if (eq) "eq" else "known"
                        put("time.$k", CountingStatistics.time(d("s"), d("b"), d("u"), eq))
                        put("unc.$k", CountingStatistics.relativeUncertainty(d("s"), d("b"), d("t"), eq))
                        put("ld.$k", CountingStatistics.detectionLimit(d("bc"), eq))
                    }
                }
                "beam" -> {
                    val q = inp("q").toInt()
                    val pps = Beam.particlesPerSecond(d("current"), q)
                    mapOf("pps" to pps, "current" to Beam.current(pps, q), "particles" to Beam.particles(d("charge"), q),
                        "power" to Beam.power(pps, d("energy")))
                }
                "targetyield" -> {
                    val r = Reaction.parse(inp("reaction"))
                    val ch = ChargedChannel.entrance(r)
                    val t = target(inp("target"))
                    val calc = StoppingCalculator(StoppingIon(r.projectile), t)
                    val abundance = d("abundance")
                    val f = t.activeFraction(r.target.z, r.target.a, abundance)
                    val eps: (Double) -> Double = { e -> try { calc.stopping(e).total * 1e-15 / f } catch (_: Exception) { 0.0 } }
                    val m = model(inp("model"))
                    val e1 = d("entrance"); val thick = d("thickness"); val exitThick = d("thickExit")
                    val loss = calc.energyLoss(e1, thick)
                    val nt = t.activeArealDensity(r.target.z, r.target.a, abundance, thick, 0.0) ?: -1.0
                    buildMap {
                        put("f", f); put("eps", eps(e1)); put("thinExit", loss.energyOut); put("nt", nt)
                        for (ue in listOf(0.0, 300.0)) {
                            val k = if (ue > 0) ".ue" else ""
                            put("thinYield$k", ch.targetYield(m, e1, loss.energyOut, ue, stopping = eps))
                            put("thinEff$k", ch.effectiveEnergy(m, e1, loss.energyOut, ue, stopping = eps) ?: -1.0)
                            put("thickYield$k", ch.targetYield(m, e1, exitThick, ue, stopping = eps))
                            put("thickEff$k", ch.effectiveEnergy(m, e1, exitThick, ue, stopping = eps) ?: -1.0)
                        }
                        put("thickYield.odd51", ch.targetYield(m, e1, exitThick, steps = 51, stopping = eps))
                        put("thickEff.50", ch.effectiveEnergy(m, e1, exitThick, steps = 50, stopping = eps) ?: -1.0)
                        val emean = ch.cmEnergy(loss.meanEnergy)
                        put("thinSimple", ChargedChannel.thinTargetYield(ch.crossSection(m.s(emean), emean), nt))
                        resonances(inp("resonances")).forEachIndexed { k, rr ->
                            val eLab = ch.labEnergy(rr.energy)
                            val y = ch.thickTargetYield(rr.energy, rr.strength, eps(eLab))
                            put("res$k.elab", eLab); put("res$k.eps", eps(eLab))
                            put("res$k.lambda2", ch.deBroglieHalfSquared(rr.energy)); put("res$k.yield", y)
                            put("res$k.wg", ch.resonanceStrength(rr.energy, 2 * y, eps(eLab)))
                        }
                    }
                }
                "yield-edges" -> {
                    val c12 = ChargedChannel.entrance(Reaction.parse("12C(p,g)13N"))
                    val flat = SFactorModel(SFactorModel.Kind.POLYNOMIAL, s0 = 1.5)
                    mapOf(
                        "reversed" to c12.targetYield(flat, 100.0, 200.0) { 1e-14 },
                        "noStopping" to c12.targetYield(flat, 200.0, 100.0) { 0.0 },
                        "noEff" to (c12.effectiveEnergy(flat, 200.0, 100.0) { 0.0 } ?: -1.0),
                        "constEps" to c12.targetYield(flat, 200.0, 0.0) { 1e-14 },
                        "constEff" to (c12.effectiveEnergy(flat, 200.0, 0.0) { 1e-14 } ?: -1.0),
                    )
                }
                "strength" -> {
                    val w = NarrowResonance.spinFactor(d("j"), d("j1"), d("j2"))
                    mapOf("omega" to w, "wg" to NarrowResonance.strength(w, d("ga"), d("gb"), d("g")))
                }
                else -> fail("unknown case $name")
            }
            check(name, inputs, values, actual)
        }
        println("ReferenceAstroTest: ${cases.size} cases $counts, $checked values checked, max relative deviation $maxRel")
    }

    @Test fun edges() {
        assertEquals(Double.POSITIVE_INFINITY, CountingStatistics.time(0.0, 1.0, 0.1))
        assertEquals(Double.POSITIVE_INFINITY, CountingStatistics.relativeUncertainty(1.0, 1.0, 0.0))
        assertNull(SFactorModel().tableRange)
        assertEquals(0.0, SFactorModel(SFactorModel.Kind.TABLE).s(100.0))
        assertNull(SFactorModel.parseTableOrNull("1 2"))
        assertNull(ChargedChannel.exit(Reaction.parse("12C(p,g)13N")))
        assertEquals(60, ChargedChannel.rateGrid.size)
        val m = SFactorModel(SFactorModel.Kind.TABLE, table = listOf(SFactorModel.Point(2.0, 1.0), SFactorModel.Point(1.0, 3.0)))
        assertEquals(listOf(1.0, 2.0), m.table.map { it.energy })
        assertEquals(m, m.copy())
    }
}
