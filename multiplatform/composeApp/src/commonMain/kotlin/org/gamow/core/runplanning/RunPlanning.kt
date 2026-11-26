package org.gamow.core.runplanning

import org.gamow.core.ChargedChannel
import org.gamow.core.astro.SFactorModel
import kotlin.math.max
import kotlin.math.sqrt

/** Beam current, particle rate, integrated charge and beam power. Port of NucPhysKit.Beam. */
object Beam {
    const val ELEMENTARY_CHARGE = 1.602_176_634e-19

    /** Particles per second for an electrical current (A) of ions in charge state q. */
    fun particlesPerSecond(current: Double, chargeState: Int): Double =
        current / (max(chargeState, 1).toDouble() * ELEMENTARY_CHARGE)

    /** Electrical current (A) of a particle rate in charge state q. */
    fun current(particlesPerSecond: Double, chargeState: Int): Double =
        particlesPerSecond * max(chargeState, 1).toDouble() * ELEMENTARY_CHARGE

    /** Particles carried by an integrated charge (C). */
    fun particles(charge: Double, chargeState: Int): Double = charge / (max(chargeState, 1).toDouble() * ELEMENTARY_CHARGE)

    /** Beam power on target, W, for a particle rate and kinetic energy (keV). */
    fun power(particlesPerSecond: Double, energy: Double): Double = particlesPerSecond * energy * 1e3 * ELEMENTARY_CHARGE
}

/** Counting statistics for a peak on a background. Port of NucPhysKit.CountingStatistics. */
object CountingStatistics {
    /**
     * Measuring time (s) for a relative statistical uncertainty `u` of the net signal, with signal rate `s` and
     * background rate `b` (counts/s in the peak region). The background is known as well as from an equal-length
     * measurement when `backgroundFromEqualTime` (σ² = S + 2B), or exactly otherwise (σ² = S + B).
     */
    fun time(signal: Double, background: Double, relativeUncertainty: Double, backgroundFromEqualTime: Boolean = true): Double {
        if (!(signal > 0 && relativeUncertainty > 0)) return Double.POSITIVE_INFINITY
        val k = if (backgroundFromEqualTime) 2.0 else 1.0
        return (signal + k * background) / (signal * signal * relativeUncertainty * relativeUncertainty)
    }

    /** Relative uncertainty of the net signal after time t (s). */
    fun relativeUncertainty(signal: Double, background: Double, time: Double, backgroundFromEqualTime: Boolean = true): Double {
        if (!(signal > 0 && time > 0)) return Double.POSITIVE_INFINITY
        val k = if (backgroundFromEqualTime) 2.0 else 1.0
        return sqrt((signal + k * background) * time) / (signal * time)
    }

    /**
     * Currie's detection limit (counts) for a background of B counts: L_D = 2.71 + 4.65 √B when the background is
     * measured in an equal-time blank (paired observations), 2.71 + 3.29 √B when it is known exactly.
     */
    fun detectionLimit(backgroundCounts: Double, backgroundFromEqualTime: Boolean = true): Double =
        2.71 + (if (backgroundFromEqualTime) 4.65 else 3.29) * sqrt(backgroundCounts)
}

/** Yield (reactions per projectile) of a thin target: σ N_t, σ in b and N_t in nuclei/cm². */
fun ChargedChannel.Companion.thinTargetYield(crossSection: Double, arealDensity: Double): Double =
    crossSection * 1e-24 * arealDensity

private fun ChargedChannel.sigma(model: SFactorModel, ecm: Double, ue: Double): Double =
    crossSection(model.s(ecm), ecm) * (if (ue > 0) screeningFactor(ecm, ue) else 1.0)

/**
 * Yield of a target of finite thickness from an S factor: Y = ∫ σ(E)/ε(E) dE over the laboratory energies from
 * `exitEnergy` to `entranceEnergy` (keV), ε the laboratory stopping cross section per active nucleus (eV cm², a
 * function of the laboratory energy). σ includes electron screening U_e (eV). Simpson's rule.
 */
fun ChargedChannel.targetYield(
    sFactor: SFactorModel, entranceEnergy: Double, exitEnergy: Double, screening: Double = 0.0, steps: Int = 200,
    stopping: (Double) -> Double,
): Double {
    val e1 = entranceEnergy; val e0 = exitEnergy
    if (!(e1.isFinite() && e0.isFinite() && e1 > e0 && e0 >= 0 && steps > 0)) return 0.0
    val n = if (steps % 2 == 0) steps else steps + 1
    val h = (e1 - e0) / n
    var sum = 0.0
    for (i in 0..n) {
        val eLab = max(e0 + i * h, 1e-3)
        val ecm = cmEnergy(eLab)
        val sigma = sigma(sFactor, ecm, screening)
        val w = if (i == 0 || i == n) 1.0 else if (i % 2 == 1) 4.0 else 2.0
        val s = stopping(eLab)
        sum += if (s > 0) w * sigma * 1e-24 / s else 0.0
    }
    return sum * h * 1e3 / 3        // dE in eV
}

/** Yield-weighted mean centre-of-mass energy in the same target (the "effective energy"), or null. */
fun ChargedChannel.effectiveEnergy(
    sFactor: SFactorModel, entranceEnergy: Double, exitEnergy: Double, screening: Double = 0.0, steps: Int = 200,
    stopping: (Double) -> Double,
): Double? {
    val e1 = entranceEnergy; val e0 = exitEnergy
    if (!(e1.isFinite() && e0.isFinite() && e1 > e0 && e0 >= 0 && steps > 0)) return null
    var num = 0.0; var den = 0.0
    val h = (e1 - e0) / steps
    for (i in 0 until steps) {
        val eLab = e0 + (i + 0.5) * h
        val ecm = cmEnergy(eLab)
        val sigma = sigma(sFactor, ecm, screening)
        val s = stopping(eLab)
        if (!(s > 0)) continue
        num += ecm * sigma / s; den += sigma / s
    }
    return if (den > 0) num / den else null
}
