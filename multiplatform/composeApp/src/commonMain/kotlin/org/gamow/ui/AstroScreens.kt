package org.gamow.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import org.gamow.core.*
import org.gamow.core.astro.*
import org.gamow.core.runplanning.*
import org.gamow.core.stopping.*
import kotlin.math.*

// MARK: Reaction rate

@Composable
fun RateScreen(wb: Workbench, onEdit: () -> Unit) {
    val r = wb.reaction ?: return NoReaction(onEdit)
    val c = wb.entrance ?: return Message("The entrance channel ${r.label} has no Coulomb barrier.")
    val p = wb.run.profile()
    val model = p.model
    val t9 = wb.t9
    val nonRes = c.rate(model, t9)
    val res = p.resonances.sumOf { c.narrowResonanceRate(it, t9) }
    SectionCard {
        ReactionHeader(wb, onEdit, showBeam = false)
        HeroNumber(Fmt.sig(nonRes + res, 4), "cm³ mol⁻¹ s⁻¹", "Nₐ⟨σv⟩ at T₉ = ${Fmt.sig(t9, 3)}")
        if (p.resonances.isNotEmpty()) Text("Non-resonant ${Fmt.sig(nonRes, 3)} + resonances ${Fmt.sig(res, 3)}", style = MaterialTheme.typography.bodyMedium)
        if (p.placeholder) Text("No S(E) set for ${r.label} yet: S = 1 keV b is a placeholder.", color = MaterialTheme.colorScheme.error)
        NumberField("T₉", t9, "GK", range = 1e-4..100.0) { wb.updateT9(it) }
    }
    SectionCard("Rate vs temperature", footer = "Bare rate: numerical integral of S(E) plus narrow resonances; no stellar screening.") {
        val grid = ChargedChannel.rateGrid
        val rows = remember(model, p.resonances, c) { grid.map { t -> Triple(t, c.rate(model, t), p.resonances.sumOf { c.narrowResonanceRate(it, t) }) } }
        Plot(listOf(PlotSeries(rows.map { it.first to it.second + it.third }, MaterialTheme.colorScheme.primary),
            PlotSeries(rows.map { it.first to it.second }, Color(0xFF64B5F6), dashed = true)),
            xLog = true, yLog = true, cursor = t9, xLabel = "T₉", yLabel = "Nₐ⟨σv⟩", onPointer = { wb.updateT9(it) })
        val clipboard = LocalClipboardManager.current
        TextButton(onClick = {
            clipboard.setText(AnnotatedString("T9,nonresonant,resonant,total\n" + rows.joinToString("\n") {
                "${Fmt.sig(it.first, 4)},${formatSignificant(it.second, 6)},${formatSignificant(it.third, 6)},${formatSignificant(it.second + it.third, 6)}" }))
        }) { Text("Copy rate table (CSV)") }
    }
    SectionCard("S factor") {
        Choice(listOf(SFactorModel.Kind.POLYNOMIAL to "Polynomial", SFactorModel.Kind.TABLE to "Table"), model.kind) {
            wb.run.update(p.copy(model = model.copy(kind = it), placeholder = false))
        }
        if (model.kind == SFactorModel.Kind.POLYNOMIAL) {
            NumberField("S(0)", model.s0, "keV b", range = 0.0..1e12) { wb.run.update(p.copy(model = model.copy(s0 = it), placeholder = false)) }
            MoreOptions("Energy dependence", summary = if (model.s1 == 0.0 && model.s2 == 0.0) "constant" else "S′, S″ set") {
                NumberField("S′(0)", model.s1, "b", range = -1e12..1e12) { wb.run.update(p.copy(model = model.copy(s1 = it))) }
                NumberField("S″(0)", model.s2, "b/keV", range = -1e12..1e12) { wb.run.update(p.copy(model = model.copy(s2 = it))) }
                Text("S(E) = S(0) + S′(0)E + ½S″(0)E², E in keV (c.m.).", style = MaterialTheme.typography.bodySmall)
            }
        } else {
            var text by remember(r) { mutableStateOf(model.tableText) }
            val parsed = runCatching { SFactorModel.parseTable(text) }
            OutlinedTextField(text, { text = it; SFactorModel.parseTableOrNull(it)?.let { pts -> wb.run.update(p.copy(model = model.copy(table = pts), placeholder = false)) } },
                label = { Text("E (keV, c.m.), S (keV b) per line") }, minLines = 4, modifier = Modifier.fillMaxWidth())
            parsed.exceptionOrNull()?.let { Text(it.message ?: "", color = MaterialTheme.colorScheme.error) }
            model.tableRange?.let { Text("${model.table.size} points, ${Fmt.sig(it.start, 4)}–${Fmt.sig(it.endInclusive, 4)} keV; constant beyond the ends.",
                style = MaterialTheme.typography.bodySmall) }
        }
        ValueRow("S at E₀ = ${Fmt.sig(c.gamowWindow(t9).peak, 4)} keV", Fmt.sig(model.s(c.gamowWindow(t9).peak), 4), "keV b")
    }
    SectionCard("Narrow resonances", footer = "E_R (c.m.) and ωγ; rate 1.5399×10¹¹ (μT₉)^−3/2 ωγ exp(−11.605 E_R/T₉).") {
        p.resonances.forEachIndexed { i, res ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                NumberField("E_R", res.energy, "keV", Modifier.weight(1f), range = 1e-3..1e6) { v ->
                    wb.run.update(p.copy(resonances = p.resonances.mapIndexed { j, x -> if (j == i) x.copy(energy = v) else x }))
                }
                Spacer(Modifier.width(8.dp))
                NumberField("ωγ", res.strength, "eV", Modifier.weight(1f), range = 0.0..1e9) { v ->
                    wb.run.update(p.copy(resonances = p.resonances.mapIndexed { j, x -> if (j == i) x.copy(strength = v) else x }))
                }
                TextButton(onClick = { wb.run.update(p.copy(resonances = p.resonances.filterIndexed { j, _ -> j != i })) }) { Text("✕") }
            }
        }
        OutlinedButton(onClick = { wb.run.update(p.copy(resonances = p.resonances + NarrowResonance(100.0, 1e-6))) }) { Text("Add resonance") }
    }
}

// MARK: Yield and beam time

private enum class YieldSource { S_FACTOR, SIGMA, RESONANCE }

@Composable
fun YieldScreen(wb: Workbench, onEdit: () -> Unit) {
    val r = wb.reaction ?: return NoReaction(onEdit)
    val c = wb.entrance ?: return Message("The entrance channel ${r.label} has no Coulomb barrier.")
    val target = wb.run.material() ?: return Message("Choose a target material in Stopping & Energy Loss.")
    val p = wb.run.profile()
    var source by remember { mutableStateOf(YieldSource.S_FACTOR) }
    var sigmaNb by remember { mutableStateOf(1.0) }
    var eR by remember(r) { mutableStateOf(wb.beamEnergy) }
    var wg by remember { mutableStateOf(1e-3) }
    var eff by remember { mutableStateOf(Prefs.get("yield.eff")?.toDoubleOrNull() ?: 1.0) }       // %
    var branch by remember { mutableStateOf(100.0) }
    var bkg by remember { mutableStateOf(Prefs.get("yield.bkg")?.toDoubleOrNull() ?: 10.0) }       // counts/h
    var goal by remember { mutableStateOf(5.0) }
    var equalBkg by remember { mutableStateOf(true) }
    var picking by remember { mutableStateOf(false) }
    if (picking) MaterialPickerDialog(onDismiss = { picking = false }) { t, key -> wb.run.setMaterial(t, key); picking = false }

    val ion = remember(r) { StoppingIon(r.projectile) }
    val calc = remember(ion, target) { StoppingCalculator(ion, target) }
    val frac = target.activeFraction(r.target.z, r.target.a, p.abundance / 100)
    val eps: (Double) -> Double = { e -> runCatching { calc.stopping(e).total * 1e-15 / frac }.getOrDefault(0.0) }
    val layer = runCatching { calc.energyLoss(wb.beamEnergy, wb.run.thickness, wb.run.tilt) }.getOrNull()
    var note: String? = null
    val yieldPerIon: Double? = when {
        frac <= 0 -> { note = "${target.name} contains no ${r.target.label}."; null }
        layer == null -> null
        source == YieldSource.S_FACTOR -> c.targetYield(p.model, layer.energyIn, layer.energyOut, p.screening, stopping = eps)
        source == YieldSource.SIGMA -> if (layer.stopped) { note = "The beam stops in the target: use S factor."; null } else
            target.activeArealDensity(r.target.z, r.target.a, p.abundance / 100, wb.run.thickness, wb.run.tilt)?.let { ChargedChannel.thinTargetYield(sigmaNb * 1e-9, it) }
        else -> if (eR <= layer.energyOut || eR >= layer.energyIn) { note = "E_R must lie between ${Fmt.keV(layer.energyOut)} and ${Fmt.keV(layer.energyIn)} keV (lab) for the plateau."; null }
            else c.thickTargetYield(c.cmEnergy(eR), wg, eps(eR))
    }
    val pps = Beam.particlesPerSecond(wb.run.current * 1e-6, wb.run.chargeState)
    val signal = (yieldPerIon ?: 0.0) * pps * eff / 100 * branch / 100
    val b = bkg / 3600
    val time = CountingStatistics.time(signal, b, goal / 100, equalBkg)

    SectionCard {
        ReactionHeader(wb, onEdit)
        val d = durationText(time)
        HeroNumber(if (signal > 0) d.first else "—", if (signal > 0) d.second else "", "Beam time for ${Fmt.sig(goal, 3)} % statistics")
        Text("${Fmt.sig(signal * 3600, 3)} counts/h · S/B ${if (b > 0) Fmt.sig(signal / b, 2) else "∞"}", style = MaterialTheme.typography.bodyMedium)
        if (source == YieldSource.S_FACTOR && p.placeholder) Text("No S(E) set for ${r.label}: S = 1 keV b is a placeholder. Set it in Reaction Rate.",
            color = MaterialTheme.colorScheme.error)
        note?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
    SectionCard("Cross section") {
        Choice(listOf(YieldSource.S_FACTOR to "S factor", YieldSource.SIGMA to "σ", YieldSource.RESONANCE to "Resonance"), source) { source = it }
        when (source) {
            YieldSource.S_FACTOR -> ValueRow("S(E) from Reaction Rate", if (p.model.kind == SFactorModel.Kind.POLYNOMIAL) "S(0) = ${Fmt.sig(p.model.s0, 4)} keV b" else "table")
            YieldSource.SIGMA -> NumberField("σ", sigmaNb, "nb", range = 0.0..1e15) { sigmaNb = it }
            YieldSource.RESONANCE -> { NumberField("E_R (lab)", eR, "keV", range = 1e-3..1e7) { eR = it }; NumberField("ωγ", wg, "eV", range = 0.0..1e9) { wg = it } }
        }
        yieldPerIon?.let { ValueRow("Yield", Fmt.sig(it, 4), "per ion") }
        if (source == YieldSource.S_FACTOR && layer != null) c.effectiveEnergy(p.model, layer.energyIn, layer.energyOut, p.screening, stopping = eps)?.let {
            ValueRow("Effective energy (c.m.)", Fmt.keV(it), "keV") }
    }
    SectionCard("Target and beam") {
        PickerField("Target", "${target.name} · ${Fmt.sig(wb.run.thickness / ThicknessUnit.MICROGRAM_CM2.toAngstrom(1.0, target), 4)} µg/cm² · ${Fmt.sig(p.abundance, 4)} % ${r.target.label}") { picking = true }
        NumberField("Thickness", wb.run.thickness / ThicknessUnit.MICROGRAM_CM2.toAngstrom(1.0, target), "µg/cm²", range = 0.0..1e9) {
            wb.run.updateThickness(it * ThicknessUnit.MICROGRAM_CM2.toAngstrom(1.0, target)) }
        NumberField("Beam current", wb.run.current, "µA", range = 1e-9..1e6) { wb.run.updateCurrent(it) }
        MoreOptions("Abundance, tilt, charge state", summary = "${Fmt.sig(p.abundance, 4)} % · ${Fmt.fixed(wb.run.tilt, 0)}° · ${wb.run.chargeState}+") {
            NumberField("${r.target.label} abundance", p.abundance, "%", range = 0.0..100.0) { wb.run.update(p.copy(abundance = it)) }
            NumberField("Tilt", wb.run.tilt, "°", range = 0.0..89.0) { wb.run.updateTilt(it) }
            NumberField("Charge state", wb.run.chargeState.toDouble(), "+", range = 1.0..r.projectile.z.toDouble()) { wb.run.updateCharge(it.roundToInt()) }
            NumberField("Screening U_e", p.screening, "eV", range = 0.0..1e5) { wb.run.update(p.copy(screening = it)) }
        }
        layer?.let { ValueRow("Energy in → out (lab)", "${Fmt.keV(it.energyIn)} → ${Fmt.keV(it.energyOut)}", "keV") }
    }
    SectionCard("Detection and background", footer = "σ_net/N = √(S + kB)/S, k = 2 when the background comes from a run of equal length, 1 when known exactly.") {
        NumberField("Efficiency", eff, "%", range = 0.0..100.0) { eff = it; Prefs.put("yield.eff", "$it") }
        // Capture γ energy (c.m. frame, recoil included) for the efficiency of the example HPGe curve.
        org.gamow.core.spectra.InBeamGamma.primary(r, wb.beamEnergy, wb.residualExcitation)?.let { g ->
            org.gamow.core.spectra.EfficiencyCurve.example.fit()?.efficiency(g.restEnergy)?.let { e ->
                TextButton(onClick = { eff = 100 * e; Prefs.put("yield.eff", "${100 * e}") }) {
                    Text("Use the example HPGe curve at E_γ = ${Fmt.keV(g.restEnergy)} keV: ${Fmt.sig(100 * e, 3)} %")
                }
            }
        }
        NumberField("Background in the peak", bkg, "counts/h", range = 0.0..1e12) { bkg = it; Prefs.put("yield.bkg", "$it") }
        NumberField("Goal (statistical)", goal, "%", range = 0.01..100.0) { goal = it }
        MoreOptions("Branching, background model", summary = "${Fmt.sig(branch, 3)} % · ${if (equalBkg) "equal-time background" else "known background"}") {
            NumberField("Branching / γ intensity", branch, "%", range = 0.0..100.0) { branch = it }
            Row(verticalAlignment = Alignment.CenterVertically) { Switch(equalBkg, { equalBkg = it }); Text("  Background measured for the same time") }
            ValueRow("Charge needed", Fmt.sig(time * wb.run.current * 1e-6, 3), "C")
            ValueRow("Detection limit (Currie, 1 h)", Fmt.sig(CountingStatistics.detectionLimit(bkg, equalBkg), 3), "counts")
        }
    }
    SaveToNotebook("Yield & beam time", r.label) {
        listOf("Beam" to "${Fmt.sig(wb.beamEnergy, 5)} keV, ${Fmt.sig(wb.run.current, 3)} µA", "Target" to target.name,
            "Yield" to "${yieldPerIon?.let { Fmt.sig(it, 4) } ?: "—"} per ion", "Signal" to "${Fmt.sig(signal * 3600, 3)} counts/h",
            "Beam time" to durationText(time).let { "${it.first} ${it.second}" } + " for ${Fmt.sig(goal, 3)} %")
    }
}

fun durationText(s: Double): Pair<String, String> {
    if (!s.isFinite()) return "∞" to ""
    val units = listOf(HalfLifeFormat.YEAR to "y", 86400.0 to "d", 3600.0 to "h", 60.0 to "min", 1.0 to "s")
    val u = units.firstOrNull { s >= it.first } ?: units.last()
    return Fmt.sig(s / u.first, 3) to u.second
}

// MARK: Resonance strength

@Composable
fun ResonanceScreen(wb: Workbench, onEdit: () -> Unit) {
    val r = wb.reaction ?: return NoReaction(onEdit)
    val c = wb.entrance ?: return Message("The entrance channel ${r.label} has no Coulomb barrier.")
    val target = wb.run.material() ?: return Message("Choose a target material in Stopping & Energy Loss.")
    val p = wb.run.profile()
    var toStrength by remember { mutableStateOf(true) }
    var eR by remember(r) { mutableStateOf(wb.beamEnergy) }
    var yieldValue by remember { mutableStateOf(1e-12) }
    var wg by remember { mutableStateOf(1e-3) }
    val calc = remember(r, target) { StoppingCalculator(StoppingIon(r.projectile), target) }
    val frac = target.activeFraction(r.target.z, r.target.a, p.abundance / 100)
    val eps = runCatching { calc.stopping(eR).total * 1e-15 / frac }.getOrNull()?.takeIf { frac > 0 }
    val ecm = c.cmEnergy(eR)
    SectionCard {
        ReactionHeader(wb, onEdit, showBeam = false)
        if (eps == null) Text("${target.name} contains no ${r.target.label}.", color = MaterialTheme.colorScheme.error)
        else if (toStrength) HeroNumber(Fmt.sig(c.resonanceStrength(ecm, yieldValue, eps), 4), "eV", "ωγ from the plateau yield")
        else HeroNumber(Fmt.sig(c.thickTargetYield(ecm, wg, eps), 4), "per ion", "Thick-target plateau yield")
        Choice(listOf(true to "Yield → ωγ", false to "ωγ → yield"), toStrength) { toStrength = it }
    }
    SectionCard("Inputs", footer = "Infinitely thick target: Y = (λ²/2)(m₁+m₂)/m₂ · ωγ/ε_eff, ε per active ${r.target.label} nucleus (SRIM, abundance ${Fmt.sig(p.abundance, 4)} %).") {
        NumberField("E_R (lab)", eR, "keV", range = 1e-3..1e7) { eR = it }
        if (toStrength) NumberField("Plateau yield", yieldValue, "per ion", range = 0.0..1.0) { yieldValue = it }
        else NumberField("ωγ", wg, "eV", range = 0.0..1e9) { wg = it }
        PickerField("Target", target.name) {}
        eps?.let { ValueRow("ε_eff at E_R", Fmt.sig(it, 4), "eV cm²") }
        ValueRow("E_R (c.m.)", Fmt.keV(ecm), "keV")
        ValueRow("λ²/2 (c.m.)", Fmt.sig(c.deBroglieHalfSquared(ecm), 4), "cm²")
    }
}

// MARK: Penetrability

@Composable
fun PenetrabilityScreen(wb: Workbench, onEdit: () -> Unit) {
    val r = wb.reaction ?: return NoReaction(onEdit)
    val c = ChargedChannel.entrance(r)
    var l by remember { mutableStateOf(0) }
    var r0 by remember { mutableStateOf(1.25) }
    var e by remember(r) { mutableStateOf(wb.ecm ?: 100.0) }
    val radius = c.radius(r0)
    val res = runCatching { c.penetrability(l, e, radius) }.getOrNull()
    SectionCard {
        ReactionHeader(wb, onEdit, showBeam = false)
        res?.let { HeroNumber(Fmt.sig(it.penetrability, 4), "", "Penetrability P$l at ${Fmt.sig(e, 4)} keV (c.m.)") }
        Choice((0..4).map { it to "ℓ = $it" }, l) { l = it }
    }
    SectionCard("Inputs") {
        NumberField("Energy (c.m.)", e, "keV", range = 1e-3..1e6) { e = it }
        NumberField("r₀", r0, "fm", range = 0.5..3.0) { r0 = it }
        ValueRow("Channel radius a", Fmt.sig(radius, 4), "fm")
    }
    res?.let {
        SectionCard("Values") {
            ValueRow("Shift factor S$l", Fmt.sig(it.shift, 4))
            ValueRow("ρ = ka", Fmt.sig(it.rho, 4)); ValueRow("η", Fmt.sig(it.eta, 4))
            ValueRow("Wigner limit γ²_W", Fmt.sig(c.wignerLimit(radius), 4), "keV")
            ValueRow("Single-particle Γ ≈ 2P γ²_W", Fmt.sig(2 * it.penetrability * c.wignerLimit(radius), 4), "keV")
            ValueRow("Coulomb barrier", Fmt.sig(c.coulombBarrier(radius), 4), "keV")
        }
    }
    SectionCard("P$l vs energy") {
        val pts = remember(l, radius, c) { (0..120).mapNotNull { i -> val x = e / 20 * (80.0).pow(i / 120.0); runCatching { x to c.penetrability(l, x, radius).penetrability }.getOrNull() } }
        Plot(listOf(PlotSeries(pts, MaterialTheme.colorScheme.primary)), xLog = true, yLog = true, cursor = e, xLabel = "E c.m. (keV)", yLabel = "P$l",
            onPointer = { e = it })
    }
}
