package org.gamow.core.spectra

import org.gamow.core.Nuclide
import org.gamow.core.Reaction
import org.gamow.core.TwoBodyKinematics
import org.gamow.core.formatFixed
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

/** Where the γ detector sits and how fast recoils stop, for Doppler shifts of in-beam γ rays. */
data class GammaGeometry(
    /** Detector axis relative to the beam, degrees. */
    val angle: Double = 55.0,
    /** Half-opening of the detector face seen from the target, degrees. */
    val halfOpening: Double = 0.0,
    /** Recoils come to rest in the target (solid) after `stoppingTime` seconds; in a gas target they do not. */
    val recoilsStop: Boolean = true,
    /** Typical slowing-down time of a recoil in a solid, s (0.1–1 ps). */
    val stoppingTime: Double = 0.5e-12,
) {
    /**
     * Probability that a level of mean life `tau` (s) decays before its recoil has stopped.
     * Instantaneous emitters (tau = 0 or null, e.g. the capture state) are always in flight.
     */
    fun fractionInFlight(meanLife: Double?): Double {
        if (!recoilsStop) return 1.0
        if (meanLife == null || !(meanLife > 0)) return 1.0
        return 1 - exp(-stoppingTime / meanLife)
    }
}

/** A γ ray from a reaction as a detector at a given angle sees it. */
data class InBeamLine(
    val label: String,
    /** Emitter at rest: transition energy minus the recoil energy, keV. */
    val restEnergy: Double,
    /** Centroid of the part emitted in flight, keV. */
    val shiftedEnergy: Double,
    /**
     * Half-width of the flat Doppler distribution of the part emitted in flight, keV
     * (residual velocities isotropic in the c.m. frame project uniformly on the detector axis).
     */
    val halfWidth: Double,
    /** Fraction emitted before the recoil stops (shifted and broadened); the rest sits at `restEnergy`. */
    val fractionInFlight: Double,
    /** γ rays per reaction. */
    val intensity: Double,
) {
    val id: String get() = "$label-${SpecMath.swiftDescription(restEnergy)}"

    /** Mean detected energy, keV. */
    val meanEnergy: Double get() = fractionInFlight * shiftedEnergy + (1 - fractionInFlight) * restEnergy

    /**
     * Spectrum lines for the Gaussian-response model: the stopped part as a sharp line, the part in flight as a
     * Doppler box. `counts` is the photopeak area of the whole γ ray.
     */
    fun spectrumLines(counts: Double, name: String? = null): List<SpectrumLine> {
        val n = name ?: label
        val out = ArrayList<SpectrumLine>(2)
        val moving = counts * fractionInFlight
        if (counts - moving > 0) out.add(SpectrumLine(name = n, energy = restEnergy, counts = counts - moving))
        if (moving > 0) out.add(SpectrumLine(name = "$n (in flight)", energy = shiftedEnergy, counts = moving, dopplerHalfWidth = halfWidth))
        return out
    }
}

/** In-beam γ-ray energies with recoil and Doppler corrections. */
object InBeamGamma {
    /**
     * Primary γ of radiative capture to `finalLevel` (keV) of the residual. The capture state decays at once and
     * moves with the c.m. velocity; in its rest frame E*γ = (s − M_f²)/(2√s), exact (recoil included). The lab energy
     * is E*γ/[γ_cm(1 − β_cm cos θ)], averaged over the detector face.
     */
    fun primary(r: Reaction, beamEnergy: Double, finalLevel: Double = 0.0, geometry: GammaGeometry = GammaGeometry()): InBeamLine? {
        if (!r.ejectile.isPhoton) return null
        val k = TwoBodyKinematics(r, beamEnergy, residualExcitation = finalLevel)
        if (!k.isOpen || !(k.e3Star > 1)) return null
        val eStar = k.e3Star
        val theta = geometry.angle * PI / 180
        val open = geometry.halfOpening * PI / 180
        val lab = GammaDoppler.meanOverCone(eStar, k.beta, theta, open)
        val spread = if (open > 0) GammaDoppler.range(eStar, k.beta, theta, open) else lab..lab
        // Strictly the capture state is never at rest; restEnergy is the c.m. value for reference.
        return InBeamLine(if (finalLevel > 0) "primary → ${fmt(finalLevel)}" else "primary → g.s.",
            eStar, lab, (spread.endInclusive - spread.start) / 2, 1.0, 1.0)
    }

    /**
     * A transition from `level` (keV) of the reaction's residual, with ENSDF energy `transition` (keV, recoil already
     * included as tabulated; null: level − recoil). The residual's lab velocity is the c.m. velocity plus an isotropic
     * c.m. velocity β*₄; projected on the detector axis it is uniform in β_cm cos θ ± β*₄.
     */
    fun residualLevel(
        r: Reaction, beamEnergy: Double, level: Double, transition: Double? = null, finalLevel: Double = 0.0,
        meanLife: Double?, intensity: Double = 1.0, geometry: GammaGeometry = GammaGeometry(), label: String? = null,
    ): InBeamLine? {
        val k = TwoBodyKinematics(r, beamEnergy, residualExcitation = level)
        if (!k.isOpen) return null
        val m = r.residual.kinematicMass + finalLevel
        val e0 = transition ?: GammaDoppler.recoilCorrected(level - finalLevel, m)
        val beta4 = if (k.e4Star > 0) k.pStar / k.e4Star else 0.0
        val theta = geometry.angle * PI / 180
        val centre = e0 * (1 + k.beta * cos(theta))
        // Opening angle adds the spread of β_cm cos θ over the detector face.
        val open = geometry.halfOpening * PI / 180
        val coneSpread = if (open > 0) e0 * k.beta * abs(cos(max(0.0, theta - open)) - cos(min(PI, theta + open))) / 2 else 0.0
        return InBeamLine(label ?: "${r.residual.label} ${fmt(level)} → ${fmt(finalLevel)}",
            e0, centre, e0 * beta4 + coneSpread, geometry.fractionInFlight(meanLife), intensity)
    }

    internal fun fmt(e: Double): String = if (e == 0.0) "0" else formatFixed(e, if (e < 100) 1 else 0)
}

// Contaminants and room background

/**
 * A beam-induced background reaction or a room-background line, with the γ rays it produces. Each beam-induced source
 * lists one complete cascade (every γ once per reaction); branchings to other levels depend on the resonance and are
 * left out, so the counts the user sets apply to each listed γ ray. Energies and lifetimes are ENSDF values (IAEA
 * LiveChart, retrieved 2026-11-20); capture primaries are computed from AME2020 Q values and the beam energy.
 */
data class BackgroundSource(
    val id: String,
    /** Reaction notation for beam-induced sources; null for room background. */
    val notation: String?,
    val name: String,
    val note: String,
    val gammas: List<Gamma>,
) {
    sealed class Gamma {
        /** Primary capture γ to a residual level, keV. */
        data class Primary(val finalLevel: Double) : Gamma()
        /** Residual level → final level with the tabulated γ energy (keV) and the level's mean life (s). */
        data class Level(val level: Double, val gamma: Double, val to: Double, val meanLife: Double, val intensity: Double) : Gamma()
        /** A line from radioactive decay, emitted at rest (keV, γ per decay relative to the strongest line). */
        data class Decay(val energy: Double, val intensity: Double) : Gamma()
    }

    val reaction: Reaction? get() = notation?.let { runCatching { Reaction.parse(it) }.getOrNull() }

    /** Lines at the given beam energy (keV, lab) and detector geometry; empty when the channel is closed. */
    fun lines(beamEnergy: Double, geometry: GammaGeometry): List<InBeamLine> {
        if (notation == null) {
            return gammas.mapNotNull { g ->
                if (g !is Gamma.Decay) null
                else InBeamLine("$name ${InBeamGamma.fmt(g.energy)}", g.energy, g.energy, 0.0, 0.0, g.intensity)
            }
        }
        val r = reaction ?: return emptyList()
        return gammas.mapNotNull { g ->
            when (g) {
                is Gamma.Primary -> InBeamGamma.primary(r, beamEnergy, g.finalLevel, geometry)?.let {
                    InBeamLine("${r.label} ${it.label}", it.restEnergy, it.shiftedEnergy, it.halfWidth, 1.0, 1.0)
                }
                // For capture the "residual" is the capture product: it moves with the c.m. plus the small recoil
                // from the primary γ, which β*₄ includes.
                is Gamma.Level -> InBeamGamma.residualLevel(r, beamEnergy, g.level, g.gamma, g.to, g.meanLife, g.intensity, geometry,
                    "${r.label} ${r.residual.label} ${InBeamGamma.fmt(g.level)} → ${InBeamGamma.fmt(g.to)}")
                is Gamma.Decay -> null
            }
        }
    }

    /** True when the source can occur with this beam: same projectile and the channel open. */
    fun applies(projectile: Nuclide, beamEnergy: Double): Boolean {
        val r = reaction ?: return true
        return r.projectile == projectile && lines(beamEnergy, GammaGeometry()).isNotEmpty()
    }
}

object BackgroundLibrary {
    /** τ = T½ / ln 2, or ħ/Γ for widths in eV. */
    private fun tauHalfLife(t: Double): Double = t / ln(2.0)
    private fun tauWidth(g: Double): Double = 6.582_119_569e-16 / g

    private fun level(lv: Double, gamma: Double, tau: Double) = BackgroundSource.Gamma.Level(lv, gamma, 0.0, tau, 1.0)
    private fun decay(e: Double, i: Double) = BackgroundSource.Gamma.Decay(e, i)
    private fun primary(f: Double) = BackgroundSource.Gamma.Primary(f)

    /** Common beam-induced contaminant reactions for proton and α beams. */
    val beamInduced: List<BackgroundSource> = listOf(
        BackgroundSource("19F(p,ag)", "19F(p,a)16O", "¹⁹F(p,αγ)¹⁶O",
            "Fluorine in targets, backings and o-rings; 6.13 MeV mostly emitted after the ¹⁶O recoil stopped (T½ = 18.4 ps).",
            listOf(level(6129.89, 6128.63, tauHalfLife(18.4e-12)))),
        BackgroundSource("15N(p,ag)", "15N(p,a)12C", "¹⁵N(p,αγ)¹²C",
            "Nitrogen in targets; the 4.44 MeV γ is emitted in flight (τ ≈ 61 fs) and Doppler broadened.",
            listOf(level(4439.82, 4438.94, tauWidth(10.8e-3)))),
        BackgroundSource("11B(p,g)", "11B(p,g)12C", "¹¹B(p,γ)¹²C",
            "Boron in backings and glass; capture through the 4.44 MeV level (the ground-state branch is not included).",
            listOf(primary(4439.82), level(4439.82, 4438.94, tauWidth(10.8e-3)))),
        BackgroundSource("13C(p,g)", "13C(p,g)14N", "¹³C(p,γ)¹⁴N",
            "Carbon build-up on the target; primary to the ground state.", listOf(primary(0.0))),
        BackgroundSource("12C(p,g)", "12C(p,g)13N", "¹²C(p,γ)¹³N",
            "Carbon build-up on the target; primary to the ground state.", listOf(primary(0.0))),
        BackgroundSource("2H(p,g)", "d(p,g)3He", "²H(p,γ)³He", "Deuterium in targets and water layers.", listOf(primary(0.0))),
        BackgroundSource("14N(p,g)", "14N(p,g)15O", "¹⁴N(p,γ)¹⁵O",
            "Nitrogen in targets; capture through the 6.18 MeV level only (other branches depend on energy and are not included).",
            listOf(primary(6176.3), level(6176.3, 6174.9, tauHalfLife(1.74e-15)))),
        BackgroundSource("23Na(p,g)", "23Na(p,g)24Mg", "²³Na(p,γ)²⁴Mg",
            "Sodium (glass, salts); primary to the first 2⁺ level and its 1369 keV γ.",
            listOf(primary(1368.667), level(1368.667, 1368.625, tauHalfLife(1.36e-12)))),
        BackgroundSource("27Al(p,g)", "27Al(p,g)28Si", "²⁷Al(p,γ)²⁸Si",
            "Aluminium in apertures and holders; primary to the first 2⁺ level and its 1779 keV γ.",
            listOf(primary(1779.03), level(1779.03, 1778.969, tauHalfLife(475e-15)))),
        BackgroundSource("23Na(p,ag)", "23Na(p,a)20Ne", "²³Na(p,αγ)²⁰Ne",
            "Sodium; 1634 keV γ from the first 2⁺ level of ²⁰Ne.",
            listOf(level(1633.674, 1633.602, tauHalfLife(0.73e-12)))),
        BackgroundSource("7Li(p,p'g)", "7Li(p,p)7Li", "⁷Li(p,p′γ)⁷Li",
            "Lithium; inelastic scattering to the 478 keV level.",
            listOf(level(477.612, 477.595, tauHalfLife(73e-15)))),
        BackgroundSource("10B(p,ag)", "10B(p,a)7Be", "¹⁰B(p,αγ)⁷Be",
            "Boron; 429 keV γ from the first excited state of ⁷Be.",
            listOf(level(429.08, 429.07, tauHalfLife(133e-15)))),
        BackgroundSource("19F(p,p'g)", "19F(p,p)19F", "¹⁹F(p,p′γ)¹⁹F",
            "Fluorine; 110 and 197 keV γ from inelastic scattering (long-lived levels, emitted at rest).",
            listOf(level(109.894, 109.9, tauHalfLife(0.591e-9)), level(197.143, 197.1, tauHalfLife(89.3e-9)))),
        // ENSDF lists Eγ = 440.5 keV above its 440.2 keV level; the level energy is used.
        BackgroundSource("23Na(p,p'g)", "23Na(p,p)23Na", "²³Na(p,p′γ)²³Na",
            "Sodium; 440 keV γ from inelastic scattering.",
            listOf(level(440.2, 440.2, tauHalfLife(1.14e-12)))),
        BackgroundSource("27Al(p,p'g)", "27Al(p,p)27Al", "²⁷Al(p,p′γ)²⁷Al",
            "Aluminium; 844 and 1015 keV γ from inelastic scattering.",
            listOf(level(843.76, 843.76, tauHalfLife(35e-12)), level(1014.56, 1014.52, tauHalfLife(1.49e-12)))),
        BackgroundSource("13C(a,ng)", "13C(a,n)16O", "¹³C(α,nγ)¹⁶O",
            "Carbon build-up under α beams; the 6.13 MeV level opens only at high α energies.",
            listOf(level(6129.89, 6128.63, tauHalfLife(18.4e-12)))),
        BackgroundSource("9Be(a,ng)", "9Be(a,n)12C", "⁹Be(α,nγ)¹²C", "Beryllium; 4.44 MeV γ in flight.",
            listOf(level(4439.82, 4438.94, tauWidth(10.8e-3)))),
        BackgroundSource("12C(a,a'g)", "12C(a,a)12C", "¹²C(α,α′γ)¹²C",
            "Carbon under α beams, above the threshold of the 4.44 MeV level.",
            listOf(level(4439.82, 4438.94, tauWidth(10.8e-3)))),
    )

    /** Laboratory background lines (emitted at rest). Intensities relative within each source (ENSDF decay data). */
    val room: List<BackgroundSource> = listOf(
        BackgroundSource("40K", null, "⁴⁰K", "Concrete, glass, people.", listOf(decay(1460.82, 1.0))),
        BackgroundSource("208Tl", null, "²⁰⁸Tl (²³²Th)", "Thorium chain.",
            listOf(decay(2614.511, 1.0), decay(583.187, 85 / 99.754), decay(860.557, 12.5 / 99.754))),
        BackgroundSource("214Bi", null, "²¹⁴Bi (radon)", "Radon daughters; varies with ventilation.",
            listOf(decay(609.321, 1.0), decay(1764.491, 15.29 / 45.44), decay(1120.294, 14.9 / 45.44), decay(2204.1, 4.92 / 45.44))),
        BackgroundSource("511", null, "Annihilation", "e⁺e⁻ annihilation (Doppler broadened in reality).",
            listOf(decay(510.999, 1.0))),
    )

    val all: List<BackgroundSource> get() = beamInduced + room

    fun source(id: String): BackgroundSource? = all.firstOrNull { it.id == id }
}

/** A background source switched on in the spectrum, with the photopeak area of its strongest γ ray. */
data class BackgroundEntry(val id: String, val counts: Double = 1000.0, val enabled: Boolean = true)
