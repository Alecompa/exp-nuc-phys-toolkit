package org.gamow.core

import kotlin.math.*

/** Radioactive decay arithmetic. Times in s, activities in Bq. Port of NucPhysKit.RadioactiveDecay. */
object RadioactiveDecay {
    const val AVOGADRO = 6.022_140_76e23
    fun decayConstant(halfLife: Double): Double = if (halfLife == Double.POSITIVE_INFINITY) 0.0 else ln(2.0) / halfLife
    fun activity(initial: Double, elapsed: Double, halfLife: Double): Double = initial * exp(-decayConstant(halfLife) * elapsed)
    /** Relative uncertainty of A(t) from the half-life uncertainty: (ln2 · t / T½) · (σT/T½). */
    fun relativeActivityUncertainty(elapsed: Double, halfLife: Double, halfLifeUncertainty: Double): Double =
        abs(ln(2.0) * elapsed / halfLife * (halfLifeUncertainty / halfLife))
    fun atoms(activity: Double, halfLife: Double): Double = activity / decayConstant(halfLife)
    fun activityOfAtoms(atoms: Double, halfLife: Double): Double = atoms * decayConstant(halfLife)
    fun mass(atoms: Double, molarMass: Double): Double = atoms * molarMass / AVOGADRO
    fun atomsOfMass(grams: Double, molarMass: Double): Double = grams * AVOGADRO / molarMass
    fun timeToFraction(fraction: Double, halfLife: Double): Double = -ln(fraction) / decayConstant(halfLife)
}

/** A photon of a decay: energy keV, intensity % per decay. */
data class EmissionLine(val energy: Double, val intensity: Double, val intensityUncertainty: Double, val kind: String)

/** A calibration source: NUBASE state and photon emissions (ENSDF via the IAEA LiveChart). */
data class CalibrationSource(val state: NuclearState, val lines: List<EmissionLine>) {
    val id: String get() = state.plainLabel
    val label: String get() = state.label
    fun prominentLines(minIntensity: Double = 1.0): List<EmissionLine> =
        lines.filter { if (it.kind == "xray") it.intensity >= 5 else it.intensity >= minIntensity }
}

object CalibrationSources {
    val all: List<CalibrationSource> by lazy {
        @Suppress("UNCHECKED_CAST")
        val root = MiniJson.parse(readResourceText("calibration_sources.json")) as Map<String, Any?>
        (root["sources"] as List<Map<String, Any?>>).mapNotNull { e ->
            val state = Nubase.nubase2020.state(e["nuclide"] as String) ?: return@mapNotNull null
            val lines = (e["lines"] as List<Map<String, Any?>>).map {
                EmissionLine(it["e"] as Double, it["i"] as Double, (it["di"] as? Double) ?: 0.0, it["kind"] as String)
            }
            CalibrationSource(state, lines)
        }
    }
    fun source(named: String): CalibrationSource? = all.firstOrNull { it.id.equals(named, ignoreCase = true) }
}

/** A lab source with its certificate. Dates as epoch seconds (UTC). */
data class SourceCertificate(
    val id: String,
    val nuclide: String,
    val name: String = "",
    /** Bq at the reference date. */
    val activity: Double,
    /** Relative standard uncertainty (0.015 = 1.5 %). */
    val relativeUncertainty: Double = 0.015,
    val referenceDate: Double,
) {
    val state: NuclearState? get() = Nubase.nubase2020.state(nuclide)

    data class Now(val activity: Double, val relativeUncertainty: Double, val elapsed: Double)

    /** Activity at `date` with the certificate and half-life uncertainties in quadrature. */
    fun activityAt(date: Double): Now? {
        val s = state ?: return null
        val t = s.halfLife ?: return null
        val dt = date - referenceDate
        val a = RadioactiveDecay.activity(activity, dt, t)
        val uT = s.halfLifeUncertainty?.let { RadioactiveDecay.relativeActivityUncertainty(dt, t, it) } ?: 0.0
        return Now(a, sqrt(relativeUncertainty * relativeUncertainty + uT * uT), dt)
    }
}
