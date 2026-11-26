package org.gamow.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.gamow.core.Nuclide
import org.gamow.core.Reaction
import org.gamow.core.exfor.ExforChannel
import org.gamow.core.exfor.ExforIndex
import org.gamow.core.spectra.Level
import org.gamow.core.spectra.LevelScheme
import org.gamow.core.spectra.LiveChartClient
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow

// region EXFOR channels on a nuclide

/** The two-body reaction of an EXFOR channel on `target`, or null for production, multi-particle or other channels. */
fun ExforChannel.twoBodyReaction(target: Nuclide): Reaction? {
    fun code(c: String): String? = when (c) {
        "p", "d", "t", "a", "n", "g" -> c
        "h", "he3" -> "3He"
        else -> Regex("""^([A-Z][a-z]?)-(\d+)$""").find(c)?.destructured?.let { (s, a) -> "$a$s" }
    }
    val p = code(projectile)?.takeIf { it != "g" } ?: return null
    val e = when (outgoing) { "el", "inl" -> p; else -> code(outgoing) } ?: return null
    return runCatching { Reaction.parse("${target.plainLabel}($p,$e)") }.getOrNull()
}

/** Every reaction channel the bundled EXFOR index has on a nuclide, grouped by projectile. */
@Composable
fun ExforChannelsSection(n: Nuclide, wb: Workbench, onUseReaction: () -> Unit) {
    val channels = remember(n) { ExforIndex.bundled.channels(n) }
    if (channels.isEmpty()) return
    val groups = remember(channels) { channels.groupBy { it.channel.projectile }.toList() }
    SectionCard("Measured reactions on ${n.label} (EXFOR)",
        footer = "${channels.sumOf { it.datasets.size }} tables in ${channels.size} channels (snapshot ${ExforIndex.bundled.date}). " +
            "Tap a two-body channel to make it the shared reaction; production and multi-particle channels show their table count only.") {
        groups.forEachIndexed { gi, (_, list) ->
            val label = list.first().channel.projectileLabel
            MoreOptions("$label-induced", summary = "${list.size} channels · ${list.sumOf { it.datasets.size }} tables", initiallyOpen = gi == 0) {
                for (c in list) {
                    val r = remember(c.channel, n) { c.channel.twoBodyReaction(n) }
                    Row(Modifier.fillMaxWidth().then(if (r != null) Modifier.clickable { wb.setReaction(r); onUseReaction() } else Modifier)
                        .padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(n.label + c.channel.label, fontWeight = FontWeight.Medium,
                                color = if (r != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
                            Text(c.channel.kind + if (r == null) "" else " · ${r.label}", style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text("${c.datasets.size}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

// endregion
// region ENSDF levels

/** Excited levels and their γ rays from ENSDF (IAEA LiveChart), cached for offline use. */
@Composable
fun LevelsSection(n: Nuclide, wb: Workbench) {
    var scheme by remember(n) { mutableStateOf<LevelScheme?>(null) }
    var loading by remember(n) { mutableStateOf(false) }
    var error by remember(n) { mutableStateOf<String?>(null) }
    var showAll by remember(n) { mutableStateOf(false) }
    var expanded by remember(n) { mutableStateOf(setOf<Int>()) }
    val scope = rememberCoroutineScope()

    suspend fun load(force: Boolean) {
        loading = true; error = null
        try {
            scheme = LiveChartClient.shared.levelScheme(n.z, n.a, forceRefresh = force)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.message ?: "The levels could not be loaded."
        } finally { loading = false }
    }

    LaunchedEffect(n) {
        // Cached data at once; the client refreshes it only when it is older than its maximum age.
        runCatching { LiveChartClient.shared.cached(n.z, n.a) }.getOrNull()?.let { scheme = it }
        load(force = false)
    }

    val r = wb.reaction
    val isResidual = r != null && r.residual.z == n.z && r.residual.a == n.a
    val s = scheme
    SectionCard("ENSDF levels",
        footer = if (s != null) "${if (s.reference.isEmpty()) "ENSDF" else "ENSDF: " + s.reference}. From the IAEA LiveChart of Nuclides; cached for offline use." +
            (if (isResidual) " Open a level to use it as the residual level of ${r!!.label}." else "")
        else "Needs an internet connection the first time; afterwards the data stay available offline.") {
        if (s != null) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("${s.levels.size} levels · ${s.gammas.size} γ rays", Modifier.weight(1f), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (loading) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                else TextButton(onClick = { scope.launch { load(force = true) } }) { Text("Refresh") }
            }
            Row(Modifier.fillMaxWidth()) {
                Text("Eₓ (keV)", Modifier.weight(1.2f), style = MaterialTheme.typography.labelMedium)
                Text("Jπ", Modifier.weight(1f), style = MaterialTheme.typography.labelMedium)
                Text("T½", Modifier.weight(1f), style = MaterialTheme.typography.labelMedium)
            }
            var levelQuery by remember(n) { mutableStateOf("") }
            val clipboard = androidx.compose.ui.platform.LocalClipboardManager.current
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(levelQuery, { levelQuery = it }, placeholder = { Text("Find Eₓ (keV) or Jπ") }, singleLine = true,
                    modifier = Modifier.weight(1f))
                TextButton(onClick = { clipboard.setText(androidx.compose.ui.text.AnnotatedString(levelsCsv(s))) }) { Text("Copy CSV") }
            }
            // Search: an energy shows levels within ±max(5 keV, 0.5 %); otherwise match Jπ text.
            val shownLevels = levelQuery.trim().let { q ->
                if (q.isEmpty()) s.levels else q.replace(',', '.').toDoubleOrNull()?.let { e -> s.levels.filter { abs(it.energy - e) <= maxOf(5.0, 0.005 * e) } }
                    ?: s.levels.filter { it.spinParity.contains(q, ignoreCase = true) }
            }
            val limit = 15
            for (l in if (showAll || levelQuery.isNotBlank()) shownLevels else shownLevels.take(limit)) {
                val open = l.index in expanded
                val gammas = s.gammas.filter { abs(it.initialLevel - l.energy) < 0.01 }.sortedByDescending { it.relativeIntensity ?: 0.0 }
                val current = isResidual && l.energy > 0 && abs(wb.residualExcitation - l.energy) < 0.01
                Row(Modifier.fillMaxWidth().clickable { expanded = if (open) expanded - l.index else expanded + l.index }.padding(vertical = 3.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(levelEnergyText(l.energy, l.energyUncertainty) + if (current) " ●" else "", Modifier.weight(1.2f),
                        fontFamily = FontFamily.Monospace, fontWeight = if (current) FontWeight.Bold else FontWeight.Normal)
                    Text(l.spinParity.ifEmpty { "—" }, Modifier.weight(1f))
                    Text(levelHalfLifeText(l), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                    Text(if (gammas.isEmpty() && !(isResidual && l.energy > 0)) "" else if (open) "▴" else "▾ ${if (gammas.isEmpty()) "" else "${gammas.size}γ"}",
                        style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (open) Column(Modifier.padding(start = 16.dp, bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    if (gammas.isEmpty()) Text("No γ rays from this level in ENSDF.", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    else Text("Eγ (keV) · I_rel · → final level", style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    for (g in gammas) Row(Modifier.fillMaxWidth()) {
                        Text(levelEnergyText(g.energy, g.energyUncertainty), Modifier.weight(1.2f), fontFamily = FontFamily.Monospace,
                            style = MaterialTheme.typography.bodySmall)
                        Text(g.relativeIntensity?.let { Fmt.sig(it, 3) } ?: "—", Modifier.weight(0.8f), style = MaterialTheme.typography.bodySmall)
                        Text("→ ${levelEnergyText(g.finalLevel, null)}" + (if (g.finalSpinParity.isNotEmpty()) " ${g.finalSpinParity}" else "") +
                            (if (g.multipolarity.isNotEmpty()) " · ${g.multipolarity}" else ""), Modifier.weight(1.4f),
                            style = MaterialTheme.typography.bodySmall)
                    }
                    if (isResidual && l.energy > 0) {
                        if (current) Text("Residual level of ${r!!.label}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                        else OutlinedButton(onClick = { wb.updateExcitation(l.energy) }) { Text("Use as residual level") }
                    }
                }
            }
            if (s.levels.size > limit) TextButton(onClick = { showAll = !showAll }) {
                Text(if (showAll) "Show fewer" else "Show all ${s.levels.size} levels")
            }
        } else if (loading) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                Text("Loading from the IAEA…", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else if (error != null) {
            Text(error!!, color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onClick = { scope.launch { load(force = true) } }) { Text("Try again") }
        }
    }
}

/** Level or γ energy with as many decimals as its uncertainty supports (PDG rule), as the iOS app. */
fun levelEnergyText(keV: Double, uncertainty: Double?): String {
    if (keV == 0.0) return "0"
    val d = uncertainty?.takeIf { it > 0 && it.isFinite() }?.let { u ->
        val exp = floor(log10(u)).toInt()
        val lead = u / 10.0.pow(exp)
        ((if (lead < 3) 1 else 0) - exp).coerceIn(0, 4)
    } ?: run {
        val frac = keV.toString().substringAfter('.', "")
        if (frac.isEmpty() || frac == "0" || 'E' in frac) 0 else frac.length.coerceAtMost(3)
    }
    return Fmt.fixed(keV, d)
}

/** ENSDF half-life: from seconds when available, otherwise the evaluator's text (widths, "STABLE"). */
fun levelHalfLifeText(l: Level): String = when {
    l.halfLife.uppercase().startsWith("STABLE") -> "stable"
    (l.halfLifeSeconds ?: 0.0) > 0 -> formatHalfLife(l.halfLifeSeconds!!)
    else -> l.halfLife.ifEmpty { "—" }
}

// endregion

/** Levels and γ rays as CSV (one row per γ ray; levels without γ data get one row). */
fun levelsCsv(s: LevelScheme): String = "level_keV,level_unc_keV,Jpi,half_life,gamma_keV,gamma_unc_keV,relative_intensity,final_level_keV,multipolarity\n" +
    s.levels.flatMap { l ->
        val gs = s.gammas.filter { abs(it.initialLevel - l.energy) < 0.01 }
        val head = listOf(Fmt.fixed(l.energy, 3), l.energyUncertainty?.let { Fmt.fixed(it, 3) } ?: "", l.spinParity, l.halfLife)
        if (gs.isEmpty()) listOf((head + listOf("", "", "", "", "")).joinToString(",") { it.replace(",", ";") })
        else gs.map { g -> (head + listOf(Fmt.fixed(g.energy, 3), g.energyUncertainty?.let { Fmt.fixed(it, 3) } ?: "",
            g.relativeIntensity?.let { Fmt.sig(it, 4) } ?: "", Fmt.fixed(g.finalLevel, 3), g.multipolarity)).joinToString(",") { it.replace(",", ";") } }
    }.joinToString("\n")
