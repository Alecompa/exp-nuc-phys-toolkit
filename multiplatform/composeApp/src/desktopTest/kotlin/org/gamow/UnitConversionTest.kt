package org.gamow

import org.gamow.ui.ReferenceConstants
import org.gamow.ui.UnitQuantity
import kotlin.math.abs
import kotlin.test.*

/** Unit-converter factors as in the Swift UnitConverterView. */
class UnitConversionTest {
    private fun close(expected: Double, actual: Double, rel: Double = 1e-12) =
        assertTrue(abs(actual - expected) <= rel * abs(expected), "expected $expected, got $actual")

    private fun conv(q: UnitQuantity, v: Double, from: String, to: String) = q.convert(v, q.index(from), q.index(to))

    @Test fun conversions() {
        close(1000.0, conv(UnitQuantity.ENERGY, 1.0, "MeV", "keV"))
        close(1.602_176_634e-13, conv(UnitQuantity.ENERGY, 1.0, "MeV", "J"))
        close(931.494_102_42, conv(UnitQuantity.ENERGY, 1.0, "u c²", "MeV"))
        close(86.173_332_62, conv(UnitQuantity.TEMPERATURE, 1.0, "T₉", "kT (keV)"))
        close(1.0, conv(UnitQuantity.TEMPERATURE, 86.173_332_62, "kT (keV)", "T₉"))
        close(1e9, conv(UnitQuantity.TEMPERATURE, 1.0, "T₉", "K"))
        close(3.7e10, conv(UnitQuantity.ACTIVITY, 1.0, "Ci", "Bq"))
        close(1e-24, conv(UnitQuantity.CROSS_SECTION, 1.0, "b", "cm²"))
        close(100.0, conv(UnitQuantity.CROSS_SECTION, 1.0, "b", "fm²"))
        close(1e5, conv(UnitQuantity.LENGTH, 1.0, "Å", "fm"))
        close(365.2422 * 86400.0, conv(UnitQuantity.TIME, 1.0, "y", "s"))
        close(1.0 / 1.602_176_634e-19, conv(UnitQuantity.CHARGE, 1.0, "C", "e"))
        close(1000.0, conv(UnitQuantity.AREAL_DENSITY, 1.0, "10¹⁸ at/cm²", "10¹⁵ at/cm²"))
        // 10¹⁸ 12C atoms/cm² ≈ 19.93 µg/cm²
        close(1e18 * 12.0 / 6.022_140_76e23 * 1e6, UnitQuantity.massThickness(1e18, 12.0))
    }

    @Test fun clipboardText() {
        assertEquals("6.582119569e-16", ReferenceConstants.clipboardText("6.582 119 569 × 10⁻¹⁶"))
        assertEquals("1e-24", ReferenceConstants.clipboardText("10⁻²⁴"))
        assertEquals("299792458", ReferenceConstants.clipboardText("299 792 458"))
        assertEquals("1/137.035999084", ReferenceConstants.clipboardText("1/137.035 999 084"))
        assertEquals("1.2–1.4", ReferenceConstants.clipboardText("1.2–1.4"))
    }
}
