package org.gamow

import org.gamow.core.MiniJson
import org.gamow.ui.ExperimentStore
import java.io.File
import kotlin.test.*

/** The Android/desktop app imports an experiment exported by the iOS app (Shared/sample_ios_experiment.json, written by Swift). */
class ExperimentImportTest {
    private val ios = File("../../Shared/sample_ios_experiment.json").readText()

    @Test fun importsIOSExport() {
        val e = assertNotNull(ExperimentStore.fromJson(ios))
        assertEquals("14N(p,g)15O", e.name)
        val s = e.setup
        assertEquals(380.0, s["beamEnergy"]); assertEquals(6176.3, s["residualExcitation"]); assertEquals(0.06, s["temperatureT9"])
        assertEquals(1500.0, s["layerThickness"]); assertEquals(55.0, s["layerAngle"]); assertEquals(250.0, s["beamCurrent"])
        assertEquals(600.0, s["screeningPotential"]); assertEquals(99.6, s["isotopicAbundance"])
        @Suppress("UNCHECKED_CAST") val m = s["sFactorModel"] as Map<String, Any?>
        assertEquals("table", m["kind"])
        @Suppress("UNCHECKED_CAST") val res = s["resonances"] as List<Map<String, Any?>>
        assertEquals(259.0, res.single()["energy"]); assertEquals(0.0127, res.single()["strength"])
    }

    @Test fun androidExportRoundTripsAndUsesIOSKeys() {
        val e = assertNotNull(ExperimentStore.fromJson(ios))
        val again = assertNotNull(ExperimentStore.fromJson(ExperimentStore.toJson(e)))
        assertEquals(e.setup, again.setup)
        // Every key the Android snapshot writes exists in the iOS format.
        @Suppress("UNCHECKED_CAST") val iosKeys = (MiniJson.parse(ios) as Map<String, Any?>).keys
        val written = listOf("version", "reactionText", "beamEnergy", "residualExcitation", "layerThickness", "layerAngle", "temperatureT9",
            "screeningPotential", "isotopicAbundance", "beamCurrent", "chargeState", "channelRadiusR0", "sFactorModel", "resonances")
        assertTrue(iosKeys.containsAll(written), "missing in iOS: ${written - iosKeys}")
    }
}
