package org.gamow.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.gamow.core.*
import org.gamow.core.exfor.*
import kotlin.math.abs
import kotlin.math.log10

private val palette = listOf(0xFFF57329, 0xFF42A5F5, 0xFF66BB6A, 0xFFAB47BC, 0xFFEF5350, 0xFF26A69A, 0xFFEC407A, 0xFF5C6BC0,
    0xFF8D6E63, 0xFF9CCC65, 0xFF26C6DA, 0xFFFFCA28).map { Color(it) }

private fun color(i: Int): Color = if (i < palette.size) palette[i]
    else Color.hsv(((i - palette.size) * 137.508f) % 360f, 0.7f, 0.85f)

/** Measured σ or S for the setup reaction: S factor at c.m. energies by default, tap for author and value. */
@Composable
fun ExforScreen(wb: Workbench, onEdit: () -> Unit) {
    val r = wb.reaction ?: return NoReaction(onEdit)
    val (filed, datasets) = remember(r) { ExforIndex.bundled.datasetsAllowingInverse(r) }
    val f = filed ?: r
    val entrance = remember(f) { ChargedChannel.entrance(f).takeIf { it.isCharged } }
    val levels = remember(datasets) { datasets.map { it.level }.distinct().sortedWith(compareBy(nullsFirst()) { it }) }
    var level by remember(datasets) { mutableStateOf(levels.firstOrNull()) }
    var quantity by remember { mutableStateOf(if (entrance != null) ExforTable.Quantity.S_FACTOR else ExforTable.Quantity.CROSS_SECTION) }
    var frame by remember { mutableStateOf(ExforTable.Frame.CM) }
    var logX by remember { mutableStateOf(true) }
    var logY by remember { mutableStateOf(true) }
    var showGamow by remember { mutableStateOf(true) }
    var hidden by remember { mutableStateOf(setOf<String>()) }
    val tables = remember(r) { mutableStateMapOf<String, Result<ExforTable>>() }
    val shown = datasets.filter { it.level == level }
    var picked by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(r, level) {
        val gate = Semaphore(6)
        shown.filter { it.id !in tables }.map { d ->
            async { gate.withPermit { tables[d.id] = runCatching { ExforClient.shared.table(d) } } }
        }.awaitAll()
    }

    SectionCard {
        ReactionHeader(wb, onEdit, showBeam = false)
        if (filed != null && filed != r) Text("EXFOR files these data as ${f.label}.", style = MaterialTheme.typography.bodyMedium)
        Text(if (datasets.isEmpty()) "No EXFOR tables for this channel in the bundled index."
            else "${shown.size} tables · ${tables.count { it.value.isSuccess && shown.any { d -> d.id == it.key } }} loaded",
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    if (datasets.isEmpty()) return

    val series = shown.mapIndexedNotNull { i, d ->
        if (d.id in hidden) return@mapIndexedNotNull null
        val t = tables[d.id]?.getOrNull() ?: return@mapIndexedNotNull null
        val pts = entrance?.let { t.points(quantity, frame, it) } ?: t.points
        Triple(d, color(i), pts.filter { it.energy > 0 && (!logY || it.value > 0) })
    }
    val gamow = if (showGamow && entrance != null && quantity == ExforTable.Quantity.S_FACTOR) entrance.gamowWindow(wb.t9) else null
    SectionCard(if (quantity == ExforTable.Quantity.S_FACTOR) "S factor" else "Cross section",
        footer = "Tables from IAEA-NDS/exfortables_py (snapshot ${ExforIndex.bundled.date}), downloaded on demand and cached. Measured data include electron screening.") {
        if (series.isEmpty()) Text("Downloading tables…") else {
            Plot(series.map { (_, c, pts) -> PlotSeries(pts.map { it.energy to it.value }, c, line = false) },
                xLog = logX, yLog = logY, xLabel = "E ${if (frame == ExforTable.Frame.CM) "c.m." else "lab"} (keV)",
                yLabel = if (quantity == ExforTable.Quantity.S_FACTOR) "S (keV b)" else "σ (b)",
                band = gamow?.let { g -> (if (frame == ExforTable.Frame.CM) g.lower else entrance!!.labEnergy(g.lower))..
                    (if (frame == ExforTable.Frame.CM) g.upper else entrance!!.labEnergy(g.upper)) },
                height = 300.dp,
                onPointer = { x ->
                    // Nearest point in log energy among the shown series.
                    val best = series.flatMap { (d, _, pts) -> pts.map { d to it } }
                        .minByOrNull { (_, p) -> if (logX) abs(log10(p.energy) - log10(x)) else abs(p.energy - x) }
                    picked = best?.let { (d, p) ->
                        val v = if (quantity == ExforTable.Quantity.S_FACTOR) "S = ${Fmt.sig(p.value, 4)}${p.uncertainty?.let { " ± ${Fmt.sig(it, 2)}" } ?: ""} keV b"
                            else Fmt.crossSection(p.value).let { (a, u) -> "σ = $a $u" }
                        "${d.author} (${d.year}) · E = ${Fmt.sig(p.energy, 5)} keV · $v"
                    }
                })
            Text(picked ?: "Tap the plot to identify the nearest point.", style = MaterialTheme.typography.bodySmall)
            if (gamow != null) Text("Shaded: Gamow window at T₉ = ${Fmt.sig(wb.t9, 3)}", style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (entrance != null) Choice(listOf(ExforTable.Quantity.S_FACTOR to "S factor", ExforTable.Quantity.CROSS_SECTION to "Cross section"), quantity) { quantity = it }
        if (levels.size > 1) {
            var menu by remember { mutableStateOf(false) }
            Box {
                PickerField("Final state", levelLabel(level, datasets)) { menu = true }
                DropdownMenu(menu, { menu = false }) {
                    for (l in levels) DropdownMenuItem(text = { Text(levelLabel(l, datasets)) }, onClick = { level = l; menu = false })
                }
            }
        }
        MoreOptions("Plot options", summary = "${if (frame == ExforTable.Frame.CM) "c.m." else "lab"} · ${if (logY) "log" else "linear"}") {
            if (entrance != null) Choice(listOf(ExforTable.Frame.CM to "Centre of mass", ExforTable.Frame.LAB to "Laboratory"), frame) { frame = it }
            Row(verticalAlignment = Alignment.CenterVertically) { Switch(logX, { logX = it }); Text("  Logarithmic energy axis") }
            Row(verticalAlignment = Alignment.CenterVertically) { Switch(logY, { logY = it }); Text("  Logarithmic value axis") }
            if (entrance != null) Row(verticalAlignment = Alignment.CenterVertically) { Switch(showGamow, { showGamow = it }); Text("  Gamow window") }
        }
    }
    SectionCard("Tables, newest first", footer = "Tap a row to hide or show it in the plot.") {
        shown.forEachIndexed { i, d ->
            val state = tables[d.id]
            Row(Modifier.fillMaxWidth().clickable { hidden = if (d.id in hidden) hidden - d.id else hidden + d.id }.padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(12.dp).background(if (d.id in hidden) Color.Transparent else color(i), CircleShape))
                Column(Modifier.weight(1f).padding(start = 10.dp)) {
                    Text("${d.author} (${d.year})", fontWeight = FontWeight.Medium)
                    Text(buildString {
                        append("EXFOR ${d.exforID}")
                        state?.getOrNull()?.let { t -> append(" · ${t.points.size} points") }
                        state?.exceptionOrNull()?.let { append(" · not available: ${it.message ?: "error"}") }
                        if (state == null) append(" · downloading…")
                    }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

private fun levelLabel(l: Int?, ds: List<ExforDataset>): String {
    val n = ds.count { it.level == l }
    return when (l) { null -> "Total"; 0 -> "Ground state"; else -> "Level $l" } + " ($n)"
}
