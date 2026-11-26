package org.gamow.core.spectra

import kotlin.math.abs
import kotlin.math.max

/** γ rays emitted when a level de-excites to the ground state, following the ENSDF branching of each level. */
object GammaCascade {
    data class Line(
        /** keV */
        val energy: Double,
        /** γ rays per decay of the starting level (internal conversion neglected). */
        val intensity: Double,
        val initialLevel: Double,
        val finalLevel: Double,
    ) {
        val id: String
            get() = "${SpecMath.swiftDescription(initialLevel)}-${SpecMath.swiftDescription(finalLevel)}-${SpecMath.swiftDescription(energy)}"
    }

    data class Result(
        val lines: List<Line>,
        /** The ENSDF level matched to the requested excitation energy, keV; null when none is close. */
        val startLevel: Double?,
        /**
         * Fraction of the cascade that reached a level with no γ data (other than the ground state), or a final level
         * that is not in the level list.
         */
        val unresolved: Double,
        /** Transitions left out because ENSDF gives no intensity for them while their siblings have one. */
        val withoutIntensity: Int = 0,
    )

    /** Cascade from the level nearest `excitation` (within `tolerance` keV, default max(2 keV, 0.2 %)). */
    fun from(excitation: Double, scheme: LevelScheme, tolerance: Double? = null): Result {
        val levels = scheme.levels.map { it.energy }.filter { it > 0 }.sorted()
        val tol = tolerance ?: max(2.0, 0.002 * excitation)
        val start = levels.minByOrNull { abs(it - excitation) }
        if (!(excitation > 0) || start == null || !(abs(start - excitation) <= tol)) {
            return Result(emptyList(), null, if (excitation > 0) 1.0 else 0.0, 0)
        }
        // Population of each level, keyed by its tabulated energy.
        val population = HashMap<Double, Double>()
        population[start] = 1.0
        val lines = ArrayList<Line>()
        var unresolved = 0.0
        var withoutIntensity = 0
        for (level in levels.asReversed()) {
            if (!(level <= start)) continue
            val p = population[level] ?: continue
            if (!(p > 1e-9)) continue
            val out = scheme.gammas.filter { abs(it.initialLevel - level) < 0.5 && it.energy > 0 }
            if (out.isEmpty()) { unresolved += p; continue }
            val weights = out.map { it.relativeIntensity ?: 0.0 }
            var total = 0.0
            for (w in weights) total += w
            if (total > 0) withoutIntensity += out.count { it.relativeIntensity == null }
            for ((g, w) in out.zip(weights)) {
                val branch = if (total > 0) w / total else 1.0 / out.size
                if (!(branch > 0)) continue
                lines.add(Line(g.energy, p * branch, level, g.finalLevel))
                // Feed the final level (nearest tabulated level; the ground state ends the cascade).
                if (g.finalLevel > 0.5) {
                    val f = levels.minByOrNull { abs(it - g.finalLevel) }
                    if (f != null && abs(f - g.finalLevel) < max(1.0, 0.001 * f)) {
                        population[f] = (population[f] ?: 0.0) + p * branch
                    } else {
                        unresolved += p * branch          // the final level is missing from the list: report, don't drop
                    }
                }
            }
        }
        return Result(lines.sortedByDescending { it.intensity }, start, unresolved, withoutIntensity)
    }

    /**
     * Mean time from the reaction to the decay of each level of a cascade, s: the level's own mean life plus the
     * intensity-weighted mean time of the levels feeding it. A short-lived level fed by a long-lived one therefore
     * decays late (at rest in a solid target). Keyed by the initial-level energies of `lines`.
     */
    fun meanDecayTimes(lines: List<Line>, meanLife: (Double) -> Double?): Map<Double, Double> {
        val levels = lines.map { it.initialLevel }.toSet().sortedDescending()
        val times = HashMap<Double, Double>()
        for (level in levels) {
            val feeders = lines.filter { abs(it.finalLevel - level) < max(1.0, 0.001 * level) && it.initialLevel > level }
            var fed = 0.0
            for (f in feeders) fed += f.intensity
            var delay = 0.0
            if (fed > 0) {
                var s = 0.0
                for (f in feeders) s += f.intensity * (times[f.initialLevel] ?: 0.0)
                delay = s / fed
            }
            times[level] = delay + (meanLife(level) ?: 0.0)
        }
        return times
    }
}
