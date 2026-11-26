package org.gamow

import kotlinx.serialization.json.*
import org.gamow.core.*
import java.io.File
import kotlin.math.abs
import kotlin.math.max
import kotlin.test.*

/** NUBASE2020, decay arithmetic and calibration sources must reproduce `Shared/reference_decay.json` (written by Swift). */
class ReferenceDecayTest {
    private val cases = Json.parseToJsonElement(File("../../Shared/reference_decay.json").readText()).jsonArray

    @Test fun reproducesEverySwiftCase() {
        val nb = Nubase.nubase2020
        var checked = 0
        for (c in cases) {
            val o = c.jsonObject
            val inputs = o["inputs"]!!.jsonObject
            fun inp(k: String) = inputs[k]!!.jsonPrimitive.content
            val expected = o["values"]!!.jsonObject
            val actual: Map<String, Double> = when (val name = o["name"]!!.jsonPrimitive.content) {
                "nubase" -> mapOf("states" to nb.states.size.toDouble(), "radioactive" to nb.states.count { it.isRadioactive }.toDouble())
                "state" -> {
                    val s = nb.state(inp("nuclide"))!!
                    assertEquals(inp("label"), s.plainLabel)
                    // Swift prints branchings in the Mac's locale (decimal comma); compare the numbers, not the separator.
                    assertEquals(inp("modes").replace(',', '.'), s.decayModes.joinToString("; ") { it.text })
                    mapOf("z" to s.z.toDouble(), "a" to s.a.toDouble(), "state" to s.state.toDouble(), "excitation" to s.excitation,
                        "halfLife" to (s.halfLife?.let { if (it.isFinite()) it else -1.0 } ?: -2.0),
                        "halfLifeUnc" to (s.halfLifeUncertainty ?: -2.0), "abundance" to (s.abundance ?: -2.0))
                }
                "decay" -> {
                    val s = nb.state(inp("nuclide"))!!
                    val h = s.halfLife!!; val a0 = inp("a0").toDouble(); val t = inp("t").toDouble()
                    mapOf("activity" to RadioactiveDecay.activity(a0, t, h),
                        "relUnc" to RadioactiveDecay.relativeActivityUncertainty(t, h, s.halfLifeUncertainty ?: 0.0),
                        "atoms" to RadioactiveDecay.atoms(a0, h), "tenth" to RadioactiveDecay.timeToFraction(0.1, h))
                }
                "source" -> {
                    val src = CalibrationSources.source(inp("nuclide"))!!
                    buildMap {
                        put("lines", src.lines.size.toDouble())
                        src.prominentLines(5.0).take(4).forEachIndexed { i, l -> put("e$i", l.energy); put("i$i", l.intensity) }
                    }
                }
                else -> fail("unknown case $name")
            }
            assertEquals(expected.keys, actual.keys, "$inputs")
            for ((k, v) in expected) {
                val want = v.jsonPrimitive.double; val got = actual.getValue(k)
                assertTrue(abs(want - got) <= 1e-9 * max(1.0, abs(want)), "$inputs $k: Swift $want, Kotlin $got")
            }
            checked++
        }
        assertEquals(cases.size, checked)
        assertEquals(CalibrationSources.all.size, cases.count { it.jsonObject["name"]!!.jsonPrimitive.content == "source" })
    }
}
