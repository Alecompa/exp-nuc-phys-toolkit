package org.gamow.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.gamow.core.ChargedChannel
import org.gamow.core.astro.SFactorModel
import org.gamow.core.exfor.ExforDataset
import org.gamow.core.exfor.ExforTable

/**
 * One EXFOR table (port of the Swift ExforDatasetView): bibliographic data, final state, quantity, S(0) rows,
 * the points, the IAEA entry, CSV copy and, for the setup reaction with a charged entrance channel, the table as
 * the S(E) model of the Reaction Rate tool.
 */
@Composable
fun ExforDatasetDetail(wb: Workbench, dataset: ExforDataset, table: ExforTable, entrance: ChargedChannel?, onBack: () -> Unit) {
    PlatformBackHandler(true, onBack)
    val clipboard = LocalClipboardManager.current
    val uri = LocalUriHandler.current
    var copied by remember(dataset) { mutableStateOf(false) }
    var stored by remember(dataset) { mutableStateOf(false) }

    TextButton(onClick = onBack, contentPadding = PaddingValues(horizontal = 4.dp)) { Text("‹ All tables") }
    SectionCard {
        Text("${dataset.author} (${dataset.year})", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        if (table.reactionCode.isNotEmpty()) Text(table.reactionCode, fontFamily = FontFamily.Monospace,
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        ValueRow("EXFOR", dataset.exforID)
        if (table.reference.isNotEmpty()) ValueRow("Reference", table.reference)
        if (table.institute.isNotEmpty()) ValueRow("Institute", table.institute)
        if (table.facility.isNotEmpty()) ValueRow("Facility", table.facility)
        ValueRow("Final state", dataset.finalStateLabel,
            note = table.levelEnergy?.takeIf { it > 0 }?.let { "Eₓ = ${Fmt.keV(it)} keV" })
        ValueRow("Quantity", if (table.quantity == ExforTable.Quantity.S_FACTOR) "S factor" else "Cross section",
            note = "Energies ${if (table.frame == ExforTable.Frame.CM) "c.m." else "laboratory"}")
        if (table.qualifier != ExforTable.Qualifier.VALUE) ValueRow("Values",
            when (table.qualifier) { ExforTable.Qualifier.UPPER_LIMIT -> "Upper limits"; ExforTable.Qualifier.APPROXIMATE -> "Approximate"; else -> "Other" },
            note = when (table.qualifier) {
                ExforTable.Qualifier.UPPER_LIMIT -> "EXFOR heading DATA-MAX; see the entry's comments"
                ExforTable.Qualifier.APPROXIMATE -> "EXFOR heading DATA-APRX"
                else -> "Non-standard EXFOR data heading"
            })
        if (table.missingValues > 0) ValueRow("Rows without a value", "${table.missingValues}", note = "NAN in EXFOR; not shown")
        for (p in table.zeroEnergyPoints) ValueRow(if (table.quantity == ExforTable.Quantity.S_FACTOR) "S(0)" else "Value at E = 0",
            exforValueText(table.quantity, p), note = "Extrapolation given by the authors; not plotted")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { runCatching { uri.openUri(dataset.exforURL) } }) { Text("Open entry ${dataset.entry} at the IAEA ↗") }
            OutlinedButton(onClick = { clipboard.setText(AnnotatedString(exforTableCsv(dataset, table))); copied = true }) {
                Text(if (copied) "Copied ✓" else "Copy CSV")
            }
        }
    }

    if (entrance != null && table.points.count { it.energy > 0 } >= 2) {
        SectionCard(footer = "Replaces the S-factor model of ${wb.reaction?.label ?: "the setup reaction"} with these points as a table " +
            "(S at c.m. energies, interpolated in ln S, constant beyond the ends). The data are used as measured: no fit, and " +
            "measured data include electron screening (no correction applied).") {
            Button(onClick = {
                val pts = table.points(ExforTable.Quantity.S_FACTOR, ExforTable.Frame.CM, entrance)
                    .filter { it.value.isFinite() && it.energy > 0 }
                    .map { SFactorModel.Point(it.energy, it.value) }
                if (pts.size >= 2) {
                    val profile = wb.run.profile()
                    wb.run.update(profile.copy(model = profile.model.copy(kind = SFactorModel.Kind.TABLE, table = pts), placeholder = false))
                    stored = true
                }
            }) { Text("Use as S(E) in Reaction Rate") }
            if (stored) Text("Stored as a ${table.points.count { it.energy > 0 }}-point S(E) table for ${wb.reaction?.label ?: ""}.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
        }
    }

    val rows = table.points
    // The table as tabulated (its own quantity and frame), on log axes where the values allow it.
    val pts = rows.filter { it.energy > 0 && it.value.isFinite() }
    if (pts.size >= 2) SectionCard {
        val logY = pts.all { it.value > 0 }
        Plot(listOf(PlotSeries(pts.map { it.energy to it.value }, MaterialTheme.colorScheme.primary, line = false)),
            xLog = pts.minOf { it.energy } > 0 && pts.maxOf { it.energy } / pts.minOf { it.energy } > 5, yLog = logY && pts.maxOf { it.value } / pts.minOf { it.value } > 20,
            xLabel = "E ${if (table.frame == ExforTable.Frame.CM) "c.m." else "lab"} (keV)",
            yLabel = if (table.quantity == ExforTable.Quantity.S_FACTOR) "S (keV b)" else "σ (b)")
    }
    var showAll by remember(dataset) { mutableStateOf(false) }
    val limit = 200
    SectionCard("E ${if (table.frame == ExforTable.Frame.CM) "(c.m.)" else "(lab)"}, keV · " +
        if (table.quantity == ExforTable.Quantity.S_FACTOR) "S, keV b" else "σ",
        footer = "As tabulated in exfortables_py, converted to keV and barn. Uncertainties are those given in EXFOR (often statistical only).") {
        for (p in if (showAll) rows else rows.take(limit)) {
            Row(Modifier.fillMaxWidth()) {
                Text(Fmt.keV(p.energy) + (p.energyUncertainty?.let { " ± ${Fmt.sig(it, 2)}" } ?: ""), Modifier.weight(1f),
                    fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodyMedium)
                Text(exforValueText(table.quantity, p), fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodyMedium)
            }
        }
        if (rows.size > limit && !showAll) TextButton(onClick = { showAll = true }) { Text("Show all ${rows.size} points") }
    }
}

/** S in keV b, σ with a barn prefix; the uncertainty in the same unit. */
fun exforValueText(q: ExforTable.Quantity, p: ExforTable.Point): String {
    if (q == ExforTable.Quantity.S_FACTOR) return Fmt.sig(p.value, 4) + (p.uncertainty?.let { " ± ${Fmt.sig(it, 2)}" } ?: "")
    val (v, unit) = Fmt.crossSection(p.value)
    val scale = barnPerUnit[unit] ?: 1.0
    return v + (p.uncertainty?.let { " ± ${Fmt.sig(it / scale, 2)}" } ?: "") + " $unit"
}

private val barnPerUnit = mapOf("b" to 1.0, "mb" to 1e-3, "µb" to 1e-6, "nb" to 1e-9, "pb" to 1e-12, "fb" to 1e-15)

/** One table as CSV, as tabulated (keV, barn or keV b). */
fun exforTableCsv(d: ExforDataset, t: ExforTable): String {
    val e = if (t.frame == ExforTable.Frame.CM) "E_cm_keV" else "E_lab_keV"
    val y = if (t.quantity == ExforTable.Quantity.S_FACTOR) "S_keVb" else "sigma_b"
    return "# EXFOR ${d.exforID} ${t.reactionCode} ${t.reference}\n$e,d$e,$y,d$y\n" +
        t.points.joinToString("\n") { "${it.energy},${it.energyUncertainty ?: ""},${it.value},${it.uncertainty ?: ""}" } + "\n"
}
