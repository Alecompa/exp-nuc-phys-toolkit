package org.gamow.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import org.gamow.core.*
import org.gamow.core.stopping.*
import kotlin.math.pow

@Composable
fun StoppingScreen(wb: Workbench, onEdit: () -> Unit) {
    val r = wb.reaction ?: return NoReaction(onEdit)
    if (r.projectile.z !in 1..92) return Message("Stopping powers need a charged ion beam.")
    val ion = remember(r) { StoppingIon(r.projectile) }
    val material = wb.run.material()
    var picking by remember { mutableStateOf(false) }
    var unit by remember { mutableStateOf(StoppingUnit.KEV_PER_MICRON) }
    val thickness = wb.run.thickness
    var tUnit by remember { mutableStateOf(ThicknessUnit.MICROGRAM_CM2) }
    val tilt = wb.run.tilt
    val target = material ?: return Message("Choose a target material.")
    if (picking) MaterialPickerDialog(onDismiss = { picking = false }) { t, key -> wb.run.setMaterial(t, key); picking = false }

    val calc = remember(ion, target) { StoppingCalculator(ion, target) }
    val e = wb.beamEnergy
    val s = runCatching { calc.stopping(e) }.getOrNull()

    SectionCard {
        ReactionHeader(wb, onEdit)
        if (s != null) HeroNumber(Fmt.sig(calc.convert(s.total, unit), 4), unit.label,
            "Stopping of ${r.projectile.reactionLabel} in ${target.name} at ${Fmt.sig(e, 5)} keV")
        PickerField("Target material", "${target.name}   ·   ${target.formulaLabel()}   ·   ${Fmt.sig(target.density, 4)} g/cm³") { picking = true }
        Choice(listOf(StoppingUnit.KEV_PER_MICRON to "keV/µm", StoppingUnit.EV_PER_1E15_ATOMS_CM2 to "eV/10¹⁵at",
            StoppingUnit.KEV_PER_MICROGRAM_CM2 to "keV/(µg/cm²)"), unit) { unit = it }
    }

    SectionCard("Stopping power vs energy", footer = "SRIM-2013 (Ziegler et al.), Bragg's rule for compounds. Tap the plot to read a value.") {
        val energies = remember(e) { (0..120).map { 10.0.pow(-1.0 + it * 5.5 / 120) * maxOf(e, 1.0) / 100 } }
        val rows = remember(calc, energies) { energies.mapNotNull { x -> runCatching { x to calc.stopping(x) }.getOrNull() } }
        var probe by remember { mutableStateOf<Double?>(null) }
        Plot(listOf(
            PlotSeries(rows.map { it.first to calc.convert(it.second.total, unit) }, MaterialTheme.colorScheme.primary),
            PlotSeries(rows.map { it.first to calc.convert(it.second.electronic, unit) }, Color(0xFF64B5F6), dashed = true),
            PlotSeries(rows.map { it.first to calc.convert(it.second.nuclear, unit) }, Color(0xFF9E9E9E), dashed = true),
        ), xLog = true, yLog = true, xLabel = "E lab (keV)", yLabel = unit.label, cursor = probe ?: e, onPointer = { probe = it })
        val p = probe ?: e
        runCatching { calc.stopping(p) }.getOrNull()?.let { sp ->
            Text("${Fmt.sig(p, 4)} keV: total ${Fmt.sig(calc.convert(sp.total, unit), 4)}, electronic ${Fmt.sig(calc.convert(sp.electronic, unit), 4)}, " +
                "nuclear ${Fmt.sig(calc.convert(sp.nuclear, unit), 3)} ${unit.label}", style = MaterialTheme.typography.bodySmall)
        }
        Text("── total   ‒ ‒ electronic (blue), nuclear (grey)", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }

    SectionCard("Through a layer of ${target.name}") {
        ValueWithUnit("Thickness", thickness, tUnit, ThicknessUnit.entries.map { it to it.symbol },
            { u -> u.toAngstrom(1.0, target) }) { v, u -> wb.run.updateThickness(v); tUnit = u }
        val loss = runCatching { calc.energyLoss(e, thickness, tilt) }.getOrNull()
        if (loss != null) {
            if (loss.stopped) Text("The beam stops in this layer.", color = MaterialTheme.colorScheme.error)
            else {
                ValueRow("Energy after the layer", Fmt.keV(loss.energyOut), "keV")
                ValueRow("Energy loss", Fmt.keV(loss.energyLoss), "keV")
                ValueRow("Mean energy in the layer", Fmt.keV(loss.meanEnergy), "keV", note = "Where a thin-target cross section is measured")
                ValueRow("Straggling (FWHM)", Fmt.sig(loss.fwhm, 3), "keV")
            }
        }
        if (loss != null && !loss.stopped) SaveToNotebook("Energy loss", "${r.projectile.reactionLabel} ${Fmt.sig(e, 5)} keV through ${Fmt.sig(thickness / tUnit.toAngstrom(1.0, target), 4)} ${tUnit.symbol} ${target.name}") {
            listOf("Energy after" to "${Fmt.keV(loss.energyOut)} keV", "Energy loss" to "${Fmt.keV(loss.energyLoss)} keV",
                "Mean energy" to "${Fmt.keV(loss.meanEnergy)} keV", "Straggling FWHM" to "${Fmt.sig(loss.fwhm, 3)} keV", "Tilt" to "${Fmt.fixed(tilt, 1)}°")
        }
        MoreOptions("Tilt and range", summary = if (tilt == 0.0) "normal incidence" else "${Fmt.fixed(tilt, 0)}° tilt") {
            NumberField("Tilt to the beam", tilt, "°", range = 0.0..89.0) { wb.run.updateTilt(it) }
            runCatching { calc.range(e) }.getOrNull()?.let { rr ->
                ValueRow("Projected range at ${Fmt.sig(e, 4)} keV", Fmt.sig(rr.projectedRange / 1e4, 4), "µm")
            }
        }
    }
}

/** Elements, the SRIM compound library and any chemical formula, searchable in one list. */
@Composable
fun MaterialPickerDialog(onDismiss: () -> Unit, onPick: (StoppingTarget, String) -> Unit) {
    var query by remember { mutableStateOf("") }
    var density by remember { mutableStateOf(1.0) }
    val q = query.trim()
    val elements = remember(q) {
        (1..92).filter { z -> q.isEmpty() || (Elements.symbol(z) ?: "").equals(q, true) || (Elements.name(z) ?: "").startsWith(q, true) }
    }
    val compounds = remember(q) {
        if (q.length < 2) emptyList() else SRIMData.shared.compounds.filter { it.displayName.contains(q, true) }.take(60)
    }
    val formula = remember(q) { if (q.isEmpty()) null else ChemicalFormula.parseOrNull(q)?.takeIf { it.parts.size > 1 || '[' in q } }
    Dialog(onDismissRequest = onDismiss) {
        Card(Modifier.fillMaxWidth().heightIn(max = 640.dp)) {
            Column(Modifier.padding(16.dp)) {
                Text("Target material", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                OutlinedTextField(query, { query = it }, placeholder = { Text("Element, compound or formula (Ta2O5)") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp))
                LazyColumn {
                    if (formula != null) item {
                        Column(Modifier.padding(vertical = 6.dp)) {
                            Text("Formula ${formula.label}", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
                            NumberField("Density", density, "g/cm³", range = 1e-8..30.0) { density = it }
                            Button(onClick = { onPick(StoppingTarget.formula(formula, density), "fml:$q|$density") }) { Text("Use ${formula.label}") }
                        }
                    }
                    if (compounds.isNotEmpty()) {
                        item { Text("SRIM compound library", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(top = 8.dp)) }
                        items(compounds) { c ->
                            Row(Modifier.fillMaxWidth().clickable { onPick(StoppingTarget.compound(c), "cmp:${c.id}") }.padding(vertical = 8.dp)) {
                                Text(c.displayName, Modifier.weight(1f))
                                Text("${Fmt.sig(c.density, 3)} g/cm³", color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                    item { Text("Elements", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(top = 8.dp)) }
                    items(elements) { z ->
                        Row(Modifier.fillMaxWidth().clickable { onPick(StoppingTarget.element(z), "el:$z") }.padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Text(Elements.symbol(z) ?: "", Modifier.width(40.dp), fontWeight = FontWeight.SemiBold)
                            Text(Elements.name(z) ?: "", Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}
