package org.gamow.core.astro

import org.gamow.core.ChargedChannel
import org.gamow.core.Reaction
import kotlin.math.*

/**
 * Regular and irregular Coulomb functions F_ℓ, G_ℓ through F² + G², for penetrabilities and shift factors deep
 * below the barrier. Port of NucPhysKit.CoulombFunctions (same RK4 steps, so the same numbers).
 *
 * Two independent solutions of u'' = (ℓ(ℓ+1)/ρ² + 2η/ρ − 1)u start far beyond the turning point as WKB waves
 * p^−½ sin φ and p^−½ cos φ (Wronskian 1) and are integrated inward with RK4; F² + G² does not depend on their
 * phase. Values are rescaled as they grow, and the penetrability is also returned as a logarithm.
 */
object CoulombFunctions {
    data class Result(
        /** P_ℓ = ρ/(F² + G²); 0 when it underflows (see [lnP]). */
        val penetrability: Double,
        val lnP: Double,
        /** Shift factor S_ℓ = ρ(FF' + GG')/(F² + G²). */
        val shift: Double,
        val rho: Double,
        val eta: Double,
    )

    /** Integration step in units of the local wavelength scale 1/√|q|. */
    internal const val STEP = 0.08
    internal const val MAX_STEP = 0.2

    fun penetrability(l: Int, eta: Double, rho: Double): Result {
        require(l >= 0 && rho > 0)
        val bigL = (l * (l + 1)).toDouble()
        fun q(r: Double): Double = bigL / (r * r) + 2 * eta / r - 1

        val turning = eta + sqrt(eta * eta + bigL)
        val start = max(max(2 * turning + 1000, rho + 1000), 30 * turning)
        val p2 = -q(start)
        val p = sqrt(p2)
        val dp = (eta / (start * start) + bigL / (start * start * start)) / p
        // y = (F-like, F', G-like, G')
        var y0 = 0.0
        var y1 = sqrt(p)
        var y2 = 1 / sqrt(p)
        var y3 = -dp / (2 * p.pow(1.5))
        var logScale = 0.0
        var r = start

        while (r > rho) {
            val local = max(1.0, sqrt(abs(q(r))))
            var h = min(STEP / local, MAX_STEP)
            if (r - h < rho) h = r - rho
            val hh = h / 2
            // f(r, y) = (y1, q y0, y3, q y2); inward step dr = −h
            val q1 = q(r)
            val k1a = y1; val k1b = q1 * y0; val k1c = y3; val k1d = q1 * y2
            val qm = q(r - h / 2)
            val t0 = y0 - hh * k1a; val t1 = y1 - hh * k1b; val t2 = y2 - hh * k1c; val t3 = y3 - hh * k1d
            val k2a = t1; val k2b = qm * t0; val k2c = t3; val k2d = qm * t2
            val u0 = y0 - hh * k2a; val u1 = y1 - hh * k2b; val u2 = y2 - hh * k2c; val u3 = y3 - hh * k2d
            val k3a = u1; val k3b = qm * u0; val k3c = u3; val k3d = qm * u2
            val q4 = q(r - h)
            val v0 = y0 - h * k3a; val v1 = y1 - h * k3b; val v2 = y2 - h * k3c; val v3 = y3 - h * k3d
            val k4a = v1; val k4b = q4 * v0; val k4c = v3; val k4d = q4 * v2
            val h6 = h / 6
            y0 -= h6 * (k1a + 2 * k2a + 2 * k3a + k4a)
            y1 -= h6 * (k1b + 2 * k2b + 2 * k3b + k4b)
            y2 -= h6 * (k1c + 2 * k2c + 2 * k3c + k4c)
            y3 -= h6 * (k1d + 2 * k2d + 2 * k3d + k4d)
            r -= h
            if (max(abs(y0), abs(y2)) > 1e100) {
                y0 *= 1e-100; y1 *= 1e-100; y2 *= 1e-100; y3 *= 1e-100
                logScale += 100 * ln(10.0)
            }
        }
        val sum = y0 * y0 + y2 * y2
        val lnP = ln(rho) - ln(sum) - 2 * logScale
        val shift = rho * (y0 * y1 + y2 * y3) / sum
        return Result(exp(lnP), lnP, shift, rho, eta)
    }
}

/** Penetrability P_ℓ and shift S_ℓ at channel radius `radius` (fm) and energy `energy` (keV, c.m.). */
fun ChargedChannel.penetrability(l: Int, energy: Double, radius: Double): CoulombFunctions.Result {
    val rho = waveNumber(energy) * radius
    return CoulombFunctions.penetrability(l, if (isCharged) sommerfeld(energy) else 0.0, rho)
}

/** The exit channel ejectile + residual, or null for a γ ejectile. */
fun ChargedChannel.Companion.exit(reaction: Reaction): ChargedChannel? {
    val e = reaction.ejectile.nuclide ?: return null
    return ChargedChannel(e, reaction.residual)
}
