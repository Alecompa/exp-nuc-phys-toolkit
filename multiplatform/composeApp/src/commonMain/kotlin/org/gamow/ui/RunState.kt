package org.gamow.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.gamow.core.*
import org.gamow.core.astro.NarrowResonance
import org.gamow.core.astro.SFactorModel
import org.gamow.core.stopping.*

/**
 * Target, beam and per-reaction astrophysics inputs shared by Stopping, Yield, Rate and Resonance tools.
 * S(E), resonances, U_e and abundance belong to one reaction (as in the iOS app): a reaction nobody has set an S(E)
 * for gets a flagged placeholder (S = 1 keV b) and the natural abundance from NUBASE2020.
 */
class RunState(private val wb: Workbench) {
    // MARK: Target material: "el:Z", "cmp:<SRIM id>", "fml:<formula>|<density g/cm³>"; null = the reaction's target element.
    var materialKey by mutableStateOf(Prefs.get("run.material"))
        private set
    var thickness by mutableStateOf(Prefs.get("run.thickness")?.toDoubleOrNull() ?: 1000.0)     // Å
        private set
    var tilt by mutableStateOf(Prefs.get("run.tilt")?.toDoubleOrNull() ?: 0.0)
        private set
    var current by mutableStateOf(Prefs.get("run.current")?.toDoubleOrNull() ?: 100.0)         // µA
        private set
    var chargeState by mutableStateOf(Prefs.get("run.charge")?.toIntOrNull() ?: 1)
        private set

    fun material(): StoppingTarget? = key(materialKey) ?: wb.reaction?.target?.z?.takeIf { it in 1..92 }?.let { runCatching { StoppingTarget.element(it) }.getOrNull() }

    fun setMaterial(t: StoppingTarget, key: String) { materialKey = key; Prefs.put("run.material", key) }
    fun updateThickness(a: Double) { thickness = a; Prefs.put("run.thickness", "$a") }
    fun updateTilt(t: Double) { tilt = t; Prefs.put("run.tilt", "$t") }
    fun updateCurrent(i: Double) { current = i; Prefs.put("run.current", "$i") }
    fun updateCharge(q: Int) { chargeState = q; Prefs.put("run.charge", "$q") }

    // MARK: Per-reaction astrophysics profile
    data class Profile(val model: SFactorModel, val resonances: List<NarrowResonance>, val screening: Double,
                       val abundance: Double, val placeholder: Boolean)

    private var revision by mutableStateOf(0)

    fun profile(r: Reaction? = wb.reaction): Profile {
        revision  // read for recomposition
        if (r == null) return Profile(SFactorModel(s0 = 1.0), emptyList(), 0.0, 100.0, true)
        Prefs.get("astro." + r.plainLabel)?.let { decode(it) }?.let { return it }
        val natural = Nubase.nubase2020.groundState(r.target.z, r.target.a)?.abundance
        return Profile(SFactorModel(s0 = 1.0), emptyList(), 0.0, natural?.takeIf { it > 0 } ?: 100.0, true)
    }

    fun update(p: Profile) {
        val r = wb.reaction ?: return
        Prefs.put("astro." + r.plainLabel, encode(p)); revision++
    }

    private fun encode(p: Profile): String = listOf(
        p.model.kind.name, "${p.model.s0}", "${p.model.s1}", "${p.model.s2}",
        p.model.table.joinToString(";") { "${it.energy}:${it.s}" },
        p.resonances.joinToString(";") { "${it.energy}:${it.strength}" },
        "${p.screening}", "${p.abundance}", "${p.placeholder}",
    ).joinToString("|")

    private fun decode(s: String): Profile? = runCatching {
        val f = s.split('|')
        fun pairs(t: String) = t.split(';').filter { it.isNotEmpty() }.map { it.split(':').let { (a, b) -> a.toDouble() to b.toDouble() } }
        Profile(SFactorModel(SFactorModel.Kind.valueOf(f[0]), f[1].toDouble(), f[2].toDouble(), f[3].toDouble(),
            pairs(f[4]).map { SFactorModel.Point(it.first, it.second) }),
            pairs(f[5]).map { NarrowResonance(it.first, it.second) }, f[6].toDouble(), f[7].toDouble(), f[8].toBoolean())
    }.getOrNull()

    companion object {
        fun key(k: String?): StoppingTarget? = runCatching {
            when {
                k == null -> null
                k.startsWith("el:") -> StoppingTarget.element(k.drop(3).toInt())
                k.startsWith("cmp:") -> SRIMData.shared.compounds.firstOrNull { it.id == k.drop(4) }?.let { StoppingTarget.compound(it) }
                k.startsWith("fml:") -> k.drop(4).split('|').let { (f, d) -> StoppingTarget.formula(ChemicalFormula.parse(f), d.toDouble()) }
                else -> null
            }
        }.getOrNull()
    }
}
