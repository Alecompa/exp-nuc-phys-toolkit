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
    private var storedCharge by mutableStateOf(Prefs.get("run.charge")?.toIntOrNull() ?: 1)
    /** Beam charge state, never above the projectile's Z (a 2+ from an α run does not carry over to protons). */
    val chargeState: Int get() = storedCharge.coerceIn(1, maxOf(1, wb.reaction?.projectile?.z ?: 1))

    // MARK: Gas target: the target layer is a gas cell (thickness = cell length) at this pressure and temperature.
    var gasOn by mutableStateOf(Prefs.get("run.gas") == "1")
        private set
    var pressure by mutableStateOf(Prefs.get("run.p")?.toDoubleOrNull() ?: 1.0)          // mbar
        private set
    var temperature by mutableStateOf(Prefs.get("run.T")?.toDoubleOrNull() ?: 293.15)    // K
        private set
    fun updateGas(on: Boolean, p: Double = pressure, t: Double = temperature) {
        gasOn = on; pressure = p; temperature = t
        Prefs.put("run.gas", if (on) "1" else "0"); Prefs.put("run.p", "$p"); Prefs.put("run.T", "$t")
    }

    // MARK: Layers the beam crosses before (windows, dead layers) and after (backing) the target: material key + Å.
    var before by mutableStateOf(loadLayers("run.before"))
        private set
    var after by mutableStateOf(loadLayers("run.after"))
        private set
    fun updateLayers(beforeTarget: Boolean, list: List<Pair<String, Double>>) {
        if (beforeTarget) before = list else after = list
        Prefs.put(if (beforeTarget) "run.before" else "run.after", list.joinToString("\u001E") { "${it.first}\u001F${it.second}" })
    }
    private fun loadLayers(k: String): List<Pair<String, Double>> = (Prefs.get(k) ?: "").split('\u001E').mapNotNull { e ->
        e.split('\u001F').takeIf { it.size == 2 }?.let { (a, b) -> b.toDoubleOrNull()?.let { a to it } }
    }

    /** The target layer material, as a gas at `pressure` and `temperature` when the gas cell is on. */
    fun target(): StoppingTarget? = material()?.let { t ->
        if (!gasOn) t else t.copy(density = GasTarget.density(t, pressure, temperature, GasTarget.defaultAtomsPerMolecule(t)), isGas = true)
    }

    /** Beam transport through windows, the target layer and the backing: (before, target, after); target null if the beam stops first. */
    data class Transport(val before: List<StoppingCalculator.EnergyLoss>, val target: StoppingCalculator.EnergyLoss?, val after: List<StoppingCalculator.EnergyLoss>)

    fun transport(ion: StoppingIon, energy: Double): Transport? {
        val t = target() ?: return null
        val pre = before.mapNotNull { (k, a) -> key(k)?.let { StackLayer(it, a) } }.filter { it.thickness > 0 }
        val post = after.mapNotNull { (k, a) -> key(k)?.let { StackLayer(it, a) } }.filter { it.thickness > 0 }
        // A target of zero thickness has no layer: never let the backing stand in for it.
        if (!(thickness > 0)) {
            val windows = runCatching { LayerStack.transport(ion, pre, energy, tilt) }.getOrNull() ?: return null
            return Transport(windows, null, emptyList())
        }
        val all = runCatching { LayerStack.transport(ion, pre + StackLayer(t, thickness) + post, energy, tilt) }.getOrNull() ?: return null
        return Transport(all.take(pre.size), all.getOrNull(pre.size), if (all.size > pre.size + 1) all.drop(pre.size + 1) else emptyList())
    }

    fun material(): StoppingTarget? = key(materialKey) ?: wb.reaction?.target?.z?.takeIf { it in 1..92 }?.let { runCatching { StoppingTarget.element(it) }.getOrNull() }

    fun setMaterial(t: StoppingTarget, key: String) { materialKey = key; Prefs.put("run.material", key) }
    fun updateThickness(a: Double) { thickness = a; Prefs.put("run.thickness", "$a") }
    fun updateTilt(t: Double) { tilt = t; Prefs.put("run.tilt", "$t") }
    fun updateCurrent(i: Double) { current = i; Prefs.put("run.current", "$i") }
    fun updateCharge(q: Int) { storedCharge = q; Prefs.put("run.charge", "$q") }

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
