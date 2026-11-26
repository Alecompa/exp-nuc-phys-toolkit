package org.gamow

import kotlinx.serialization.json.*
import org.gamow.core.*
import java.io.File
import kotlin.math.abs
import kotlin.math.max
import kotlin.test.*

/**
 * The Kotlin port must reproduce `Shared/reference_values.json`, which the Swift NucPhysKit writes and checks
 * (ReferenceValuesTests.swift). Same physics on iPhone/Mac and on Android/Linux/Windows.
 */
class ReferenceValuesTest {
    private val cases = Json.parseToJsonElement(File("../../Shared/reference_values.json").readText()).jsonArray

    private fun check(name: String, inputs: JsonObject, expected: JsonObject, actual: Map<String, Double>) {
        assertEquals(expected.keys, actual.keys, "$name $inputs: keys")
        for ((k, v) in expected) {
            val want = v.jsonPrimitive.double
            val got = actual.getValue(k)
            assertTrue(abs(want - got) <= 1e-9 * max(1.0, abs(want)), "$name $inputs $k: Swift $want, Kotlin $got")
        }
    }

    @Test fun reproducesEverySwiftCase() {
        assertTrue(cases.size >= 20)
        for (c in cases) {
            val o = c.jsonObject
            val name = o["name"]!!.jsonPrimitive.content
            val inputs = o["inputs"]!!.jsonObject
            fun inp(k: String) = inputs[k]!!.jsonPrimitive.content
            val values = o["values"]!!.jsonObject
            val r = Reaction.parse(inp("reaction"))
            val actual: Map<String, Double> = when (name) {
                "qvalue" -> {
                    assertEquals(inp("residual"), r.residual.plainLabel)
                    mapOf("q" to r.qValue, "dq" to r.qValueUncertainty, "threshold" to r.threshold())
                }
                "kinematics" -> {
                    val k = TwoBodyKinematics(r, inp("beam").toDouble(), inp("ex").toDouble())
                    val sols = k.solutions(inp("angle").toDouble().radians)
                    buildMap {
                        put("ecm", k.centerOfMassEnergy); put("beta", k.beta); put("pstar", k.pStar)
                        put("maxangle", k.maxEjectileAngle?.degrees ?: -1.0)
                        sols.forEachIndexed { i, s ->
                            put("e$i", s.ejectileEnergy); put("thcm$i", s.thetaCM.degrees); put("jac$i", s.jacobian)
                            put("er$i", s.residualEnergy); put("thr$i", s.residualAngle.degrees)
                        }
                        put("branches", sols.size.toDouble())
                    }
                }
                "astro" -> {
                    val c = ChargedChannel.entrance(r)
                    val e = inp("energy").toDouble()
                    val w = c.gamowWindow(inp("t9").toDouble())
                    mapOf("mu" to c.reducedMass, "eta" to c.sommerfeld(e), "gamowEnergy" to c.gamowEnergy, "e0" to w.peak,
                        "delta" to w.width, "sigmaFromS1" to c.crossSection(1.0, e), "sFromSigma1nb" to c.sFactor(1e-9, e),
                        "screening300" to c.screeningFactor(e, 300.0), "wigner" to c.wignerLimit(c.radius(1.25)),
                        "elab" to c.labEnergy(e))
                }
                else -> fail("unknown case $name")
            }
            check(name, inputs, values, actual)
        }
    }

    @Test fun notationTraps() {
        assertNull(NuclideNotation.parse("H")); assertNull(NuclideNotation.parse("N"))
        assertEquals(6 to 12, NuclideNotation.parse("¹²C"))
        assertEquals(2 to 4, NuclideNotation.parse("Alpha"))
        assertEquals("27Al(p,p)27Al", Reaction.parse("27Al(p,p')").plainLabel)
        assertEquals("7Be(p,g)8B", Reaction.parse("p(7Be,g)8B").swappedBeamAndTarget?.plainLabel)
        assertFailsWith<ReactionException> { Reaction.parse("12C(p,g)14N") }
    }
}
