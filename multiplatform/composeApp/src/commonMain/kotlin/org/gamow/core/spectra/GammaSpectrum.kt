package org.gamow.core.spectra

import org.gamow.core.MiniJson
import org.gamow.core.readResourceText
import org.gamow.core.stopping.StoppingTarget
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Errors of the spectrum model (messages as in the Swift app). */
class SpectrumException(val kind: Kind) : Exception() {
    enum class Kind { ATTENUATION_RANGE, INVALID_MATERIAL, INVALID_INPUT }

    override val message: String
        get() = when (kind) {
            Kind.ATTENUATION_RANGE -> "Foil attenuation requires elements Z = 1–92 and gamma energies from 1 keV to 20 MeV."
            Kind.INVALID_MATERIAL -> "Foils need a valid composition, positive density and nonnegative thickness."
            Kind.INVALID_INPUT -> "Use finite, nonnegative counts and background, positive resolution, 1–20000 keV gamma energies, and 128–8192 channels."
        }
}

@Suppress("UNCHECKED_CAST")
private fun loadTables(name: String): Map<String, List<DoubleArray>> = runCatching {
    (MiniJson.parse(readResourceText(name)) as Map<String, Any?>).mapValues { (_, rows) ->
        (rows as List<List<Any?>>).map { r -> DoubleArray(r.size) { (r[it] as Number).toDouble() } }
    }
}.getOrDefault(emptyMap())

/**
 * NIST total photon attenuation, 1 keV–20 MeV, Z=1–92.
 * Log-log interpolation never bridges a duplicate-energy absorption edge.
 */
object PhotonAttenuation {
    private val tables: Map<String, List<DoubleArray>> by lazy { loadTables("photon_attenuation.json") }

    /** Mass attenuation coefficient μ/ρ, cm²/g. Throws [SpectrumException] outside Z = 1–92, 1–20000 keV. */
    fun massCoefficient(z: Int, energy: Double): Double {
        val rows = tables[z.toString()]
        if (!energy.isFinite() || energy < 1 || energy > 20000 || rows == null) {
            throw SpectrumException(SpectrumException.Kind.ATTENUATION_RANGE)
        }
        // Last row at or below E selects the high-energy side at an exact edge.
        val i = rows.indexOfLast { it[0] <= energy }
        if (i < 0) throw SpectrumException(SpectrumException.Kind.ATTENUATION_RANGE)
        val lo = rows[i]
        if (lo[0] == energy || i == rows.size - 1) return lo[1]
        val hi = rows[i + 1]
        val f = ln(energy / lo[0]) / ln(hi[0] / lo[0])
        return exp(ln(lo[1]) + f * ln(hi[1] / lo[1]))
    }

    /** Mixture rule uses mass fractions, not atom fractions. Elemental tables assume natural isotopes. */
    fun massCoefficient(material: StoppingTarget, energy: Double): Double {
        val comps = material.components
        if (comps.isEmpty() || !comps.all { it.mass.isFinite() && it.mass > 0 && it.stoichiometry.isFinite() && it.stoichiometry > 0 }) {
            throw SpectrumException(SpectrumException.Kind.INVALID_MATERIAL)
        }
        var mass = 0.0
        for (c in comps) mass += c.mass * c.stoichiometry
        if (!mass.isFinite()) throw SpectrumException(SpectrumException.Kind.INVALID_MATERIAL)
        var sum = 0.0
        for (c in comps) sum += c.mass * c.stoichiometry / mass * massCoefficient(c.z, energy)
        return sum
    }
}

/** An absorber in front of the γ detector. Thickness in Å along the normal; angle of the photons to the normal, degrees. */
data class DetectorFoil(
    val material: StoppingTarget = StoppingTarget.element(13),
    val thickness: Double = 100000.0,
    val angle: Double = 0.0,
    val id: String = SpecMath.newId(),
) {
    /** Photon transmission at `energy` keV. */
    fun transmission(energy: Double): Double {
        if (!thickness.isFinite() || thickness < 0 || !material.density.isFinite() || !(material.density > 0) ||
            !angle.isFinite() || angle < 0 || angle > 89) throw SpectrumException(SpectrumException.Kind.INVALID_MATERIAL)
        val mu = PhotonAttenuation.massCoefficient(material, energy)
        return exp(-mu * material.density * thickness * 1e-8 / cos(angle * PI / 180))
    }
}

data class SpectrumLine(
    val name: String = "Custom gamma",
    val energy: Double = 1000.0,
    /** Expected photopeak area without foils, after geometry/efficiency/live time. */
    val counts: Double = 1000.0,
    val enabled: Boolean = true,
    /** Half-width of a flat Doppler distribution around `energy` (γ rays emitted in flight), keV; 0 = sharp line. */
    val dopplerHalfWidth: Double = 0.0,
    val id: String = SpecMath.newId(),
)

data class SpectrumSetup(
    val lines: List<SpectrumLine> = emptyList(),
    val foils: List<DetectorFoil> = emptyList(),
    val maximumEnergy: Double = 3000.0,
    val channels: Int = 4096,
    /** Integrated single-scatter continuum / photopeak area; an empirical input, not a material prediction. */
    val continuumRatio: Double = 2.0,
    /** Flat recorded background, counts/keV; not attenuated by front foils. */
    val background: Double = 0.0,
    /** Single- and double-escape peaks (and an optional 511 keV line) above the pair threshold. */
    val escape: EscapeModel = EscapeModel(),
    /** γ-detector angle and recoil stopping, for Doppler shifts of in-beam lines. */
    val geometry: GammaGeometry = GammaGeometry(),
    /** Beam-induced contaminants and room-background sources switched on (see [BackgroundLibrary]). */
    val backgrounds: List<BackgroundEntry> = emptyList(),
) {
    /**
     * Spectrum lines of the enabled background sources at a beam energy (lab, keV). `counts` of an entry is the
     * photopeak area of each γ ray of its cascade (room lines: of the strongest).
     */
    fun backgroundLines(beamEnergy: Double): List<SpectrumLine> = backgrounds.filter { it.enabled }.flatMap { entry ->
        val source = BackgroundLibrary.source(entry.id) ?: return@flatMap emptyList()
        source.lines(beamEnergy, geometry).flatMap { it.spectrumLines(entry.counts * it.intensity) }
    }
}

/** Detector crystal, for the energy dependence of pair production. */
enum class DetectorCrystal(val id: String, val displayName: String) {
    HPGE("hpge", "HPGe"), NAI("nai", "NaI(Tl)"), LABR3("labr3", "LaBr₃(Ce)"), BGO("bgo", "BGO"), CSI("csi", "CsI(Tl)");

    /** Mass fractions by Z. */
    internal val composition: List<Pair<Int, Double>>
        get() {
            fun mix(vararg atoms: Triple<Int, Double, Double>): List<Pair<Int, Double>> {   // (Z, count, atomic mass)
                var total = 0.0
                for (a in atoms) total += a.second * a.third
                return atoms.map { it.first to it.second * it.third / total }
            }
            return when (this) {
                HPGE -> listOf(32 to 1.0)
                NAI -> mix(Triple(11, 1.0, 22.990), Triple(53, 1.0, 126.904))
                LABR3 -> mix(Triple(57, 1.0, 138.905), Triple(35, 3.0, 79.904))
                BGO -> mix(Triple(83, 4.0, 208.980), Triple(32, 3.0, 72.630), Triple(8, 12.0, 15.999))
                CSI -> mix(Triple(55, 1.0, 132.905), Triple(53, 1.0, 126.904))
            }
        }

    /** Typical single/double escape-to-photopeak ratios at 6 MeV for a mid-size crystal (rough planning defaults). */
    val typicalEscape: Pair<Double, Double>
        get() = when (this) {
            HPGE -> 0.8 to 0.5
            NAI -> 0.6 to 0.25
            LABR3 -> 0.6 to 0.3
            BGO -> 0.25 to 0.08
            CSI -> 0.5 to 0.2
        }

    companion object {
        /** The crystal of a resolution preset, judged from its name. */
        fun matching(presetName: String): DetectorCrystal? {
            val n = presetName.lowercase()
            if ("ge" in n && "bgo" !in n) return HPGE
            if ("nai" in n) return NAI
            if ("labr" in n) return LABR3
            if ("bgo" in n) return BGO
            if ("csi" in n) return CSI
            return null
        }
    }
}

/** NIST XCOM pair production (nuclear + electron field) and total attenuation, 1.022–20 MeV. */
object PairProduction {
    private val tables: Map<String, List<DoubleArray>> by lazy { loadTables("pair_production.json") }

    /** Pair-production share of the total attenuation, κ/μ, in a crystal (0 below 1022 keV). */
    fun fraction(crystal: DetectorCrystal, energy: Double): Double {
        if (!(energy > 1022)) return 0.0
        var pair = 0.0
        var total = 0.0
        for ((z, w) in crystal.composition) {
            val rows = tables[z.toString()] ?: return 0.0
            if (rows.isEmpty()) return 0.0
            val e = min(max(energy, rows.first()[0]), rows.last()[0])
            val found = rows.indexOfLast { it[0] <= e }
            val i = min(rows.size - 2, if (found < 0) 0 else found)
            val f = (e - rows[i][0]) / (rows[i + 1][0] - rows[i][0])
            pair += w * (rows[i][1] + f * (rows[i + 1][1] - rows[i][1]))
            total += w * (rows[i][2] + f * (rows[i + 1][2] - rows[i][2]))
        }
        return if (total > 0) pair / total else 0.0
    }
}

/** Escape peaks scaled from ratios at a reference energy by the crystal's pair-production share. */
data class EscapeModel(
    val enabled: Boolean = true,
    val crystal: DetectorCrystal = DetectorCrystal.HPGE,
    /** Single- and double-escape area / photopeak area at 6 MeV. */
    val singleAtReference: Double = 0.8,
    val doubleAtReference: Double = 0.5,
    /** Area of the 511 keV annihilation line per single-escape count (annihilation in the surroundings); 0 = off. */
    val annihilation: Double = 0.0,
) {
    /** The crystal with its typical escape ratios. */
    fun usingTypical(crystal: DetectorCrystal): EscapeModel =
        copy(crystal = crystal, singleAtReference = crystal.typicalEscape.first, doubleAtReference = crystal.typicalEscape.second)

    /** Escape / photopeak area ratios (single, double) at `energy` keV. */
    fun ratios(energy: Double): Pair<Double, Double> {
        if (!enabled || !(energy > 1022)) return 0.0 to 0.0
        val reference = PairProduction.fraction(crystal, REFERENCE_ENERGY)
        if (!(reference > 0)) return 0.0 to 0.0
        val scale = PairProduction.fraction(crystal, energy) / reference
        return min(20.0, singleAtReference * scale) to min(20.0, doubleAtReference * scale)
    }

    companion object {
        const val REFERENCE_ENERGY = 6000.0
    }
}

data class SpectrumBin(
    val id: Int,
    val energy: Double,
    val photopeak: Double,
    val compton: Double,
    val background: Double,
    /** Single and double escape peaks and the 511 keV line. */
    val escape: Double = 0.0,
) {
    val total: Double get() = photopeak + compton + background + escape
}

/** Deterministic expected spectrum, not a detector transport Monte Carlo. */
object GammaSpectrum {
    fun comptonEdge(energy: Double): Double = energy * (2 * energy / 510.99895) / (1 + 2 * energy / 510.99895)

    /**
     * Expected spectrum of `setup` with the detector `resolution`. Throws [SpectrumException] on invalid input.
     * `checkCancelled` is called between lines and every 64 continuum samples (pass `{ ensureActive() }` from a coroutine).
     */
    fun simulate(setup: SpectrumSetup, resolution: ResolutionModel, checkCancelled: () -> Unit = {}): List<SpectrumBin> {
        fun inRange(x: Double, lo: Double, hi: Double) = x >= lo && x <= hi
        if (!setup.maximumEnergy.isFinite() || !inRange(setup.maximumEnergy, 1.0, 20000.0) || setup.channels !in 128..8192 ||
            !setup.background.isFinite() || setup.background < 0 ||
            !setup.continuumRatio.isFinite() || !inRange(setup.continuumRatio, 0.0, 100.0) ||
            !listOf(setup.escape.singleAtReference, setup.escape.doubleAtReference, setup.escape.annihilation)
                .all { it.isFinite() && inRange(it, 0.0, 20.0) }) throw SpectrumException(SpectrumException.Kind.INVALID_INPUT)
        val width = setup.maximumEnergy / setup.channels
        val peak = DoubleArray(setup.channels)
        val continuum = DoubleArray(setup.channels)
        val escapes = DoubleArray(setup.channels)
        for (line in setup.lines) {
            if (!line.enabled) continue
            checkCancelled()
            if (!line.energy.isFinite() || !inRange(line.energy, 1.0, 20000.0) || !line.counts.isFinite() ||
                !inRange(line.counts, 0.0, 1e12)) throw SpectrumException(SpectrumException.Kind.INVALID_INPUT)
            var area = line.counts
            for (f in setup.foils) area *= f.transmission(line.energy)
            if (!line.dopplerHalfWidth.isFinite() || line.dopplerHalfWidth < 0) throw SpectrumException(SpectrumException.Kind.INVALID_INPUT)
            val h = line.dopplerHalfWidth
            deposit(line.energy, area, width, resolution, h, peak)
            val (single, double) = setup.escape.ratios(line.energy)
            if ((single > 0 || double > 0) && area > 0) {
                deposit(line.energy - 510.99895, area * single, width, resolution, h, escapes)
                deposit(line.energy - 1021.9979, area * double, width, resolution, h, escapes)
                if (setup.escape.annihilation > 0) {
                    deposit(510.99895, area * single * setup.escape.annihilation, width, resolution, 0.0, escapes)
                }
            }
            if (!(setup.continuumRatio > 0) || !(area > 0)) continue
            val edge = comptonEdge(line.energy)
            // Midpoint integration in deposited energy. dσ/dT ∝ k + 1/k − sin²θ;
            // the angular Jacobian cancels the k² in dσ/dΩ.
            val samples = min(8192, max(512, ceil(edge / width).toInt()))
            val step = edge / samples
            val weights = DoubleArray(samples)
            for (j in 0 until samples) {
                val t = (j + 0.5) * step
                val k = 1 - t / line.energy
                val cosine = 1 - 510.99895 * (1 / (line.energy - t) - 1 / line.energy)
                weights[j] = k + 1 / k - (1 - cosine * cosine)
            }
            var norm = 0.0
            for (w in weights) norm += w
            for (j in 0 until samples) {
                if (j % 64 == 0) checkCancelled()
                deposit((j + 0.5) * step, area * setup.continuumRatio * weights[j] / norm, width, resolution, 0.0, continuum)
            }
        }
        return (0 until setup.channels).map {
            SpectrumBin(it, (it + 0.5) * width, peak[it], continuum[it], setup.background * width, escapes[it])
        }
    }

    /**
     * Integrates the Gaussian across channel boundaries, including sub-channel narrow peaks. Out-of-window counts are
     * lost, never renormalized back into the displayed range. A flat distribution of half-width `h` (Doppler
     * broadening) is folded with the Gaussian exactly: with G(t) = t Φ(t/σ) + σ φ(t/σ), the antiderivative of Φ(t/σ),
     * a bin [a, b] receives area/(2h) · [G(b−E+h) − G(b−E−h) − G(a−E+h) + G(a−E−h)].
     */
    internal fun deposit(energy: Double, area: Double, width: Double, resolution: ResolutionModel, h: Double, bins: DoubleArray) {
        val sigma = resolution.fwhm(energy) / (2 * sqrt(2 * ln(2.0)))
        if (!sigma.isFinite() || !(sigma > 0) || !(sigma < 1e6)) throw SpectrumException(SpectrumException.Kind.INVALID_INPUT)
        val lo = max(0, floor((energy - h - 6 * sigma) / width).toInt())
        val hi = min(bins.size - 1, floor((energy + h + 6 * sigma) / width).toInt())
        if (lo > hi) return
        if (h < 0.01 * sigma) {
            val scale = sqrt(2.0) * sigma
            for (i in lo..hi) {
                val left = (i * width - energy) / scale
                val right = ((i + 1) * width - energy) / scale
                bins[i] += area * 0.5 * (SpecMath.erf(right) - SpecMath.erf(left))
            }
            return
        }
        fun g(t: Double): Double {
            val u = t / sigma
            return t * 0.5 * SpecMath.erfc(-u / sqrt(2.0)) + sigma * exp(-0.5 * u * u) / sqrt(2 * PI)
        }
        for (i in lo..hi) {
            val a = i * width - energy
            val b = (i + 1) * width - energy
            val w = g(b + h) - g(b - h) - g(a + h) + g(a - h)
            bins[i] += area * max(0.0, w) / (2 * h)
        }
    }

    /** CSV export with Swift's number formatting. */
    fun csv(bins: List<SpectrumBin>): String {
        val d = SpecMath::swiftDescription
        return "energy_keV,total_counts,photopeak_counts,compton_counts,background_counts,escape_counts\n" +
            bins.joinToString("\n") { "${d(it.energy)},${d(it.total)},${d(it.photopeak)},${d(it.compton)},${d(it.background)},${d(it.escape)}" }
    }
}
