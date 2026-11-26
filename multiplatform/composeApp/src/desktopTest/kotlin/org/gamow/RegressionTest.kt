package org.gamow

import org.gamow.core.MassTable
import org.gamow.core.Prefs
import org.gamow.ui.spinOf
import kotlin.test.*

/** Regressions found in the review of the parity round. */
class RegressionTest {
    @Test fun spinOfMultiValuedAndFractionJpi() {
        val t = MassTable.ame2020
        assertEquals(0.5, spinOf(t.nuclide(named = "p")!!))           // 1/2+
        assertEquals(1.5, spinOf(t.nuclide(named = "7Li")!!))         // 3/2-
        assertEquals(1.0, spinOf(t.nuclide(named = "14N")!!))         // 1+
        assertEquals(0.0, spinOf(t.nuclide(named = "12C")!!))         // 0+
        assertEquals(1.0, spinOf(t.nuclide(named = "10Li")!!))        // (1-,2-): first alternative, was 0
    }

    @Test fun longPreferenceValuesSurvive() {
        // java.util.prefs rejects values over 8192 characters; the desktop store splits them.
        val key = "test.regression.long"
        val long = (0 until 3000).joinToString(";") { "$it:${it * 1.5}" }      // ≈ 30 000 characters
        Prefs.put(key, long)
        assertEquals(long, Prefs.get(key))
        Prefs.put(key, "short")
        assertEquals("short", Prefs.get(key))
    }
}
