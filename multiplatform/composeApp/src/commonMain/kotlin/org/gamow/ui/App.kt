package org.gamow.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** Tools of the app; the same list on phones (stack) and wide windows (sidebar). */
enum class Tool(val title: String, val subtitle: String, val group: String) {
    Setup("Reaction Setup", "Reaction, beam energy, saved and recent", "Setup"),
    QValue("Q-Value", "Masses, thresholds, final states", "Reactions"),
    Kinematics("Kinematics", "Relativistic two-body, both branches", "Reactions"),
    Exfor("EXFOR Cross Sections", "Measured σ and S factors", "Reactions"),
    Rutherford("Rutherford Scattering", "dσ/dΩ lab and c.m., monitor counts", "Reactions"),
    Doppler("Gamma Doppler", "Shift and broadening at a detector", "Reactions"),
    Stopping("Stopping & Energy Loss", "SRIM-2013, layers, straggling", "Stopping & targets"),
    Gamow("Gamow Window", "E₀ and Δ vs T₉", "Nuclear astrophysics"),
    SFactor("S-Factor ↔ Cross Section", "With electron screening", "Nuclear astrophysics"),
    Rate("Reaction Rate", "Nₐ⟨σv⟩ from S(E) and resonances", "Nuclear astrophysics"),
    Resonance("Resonance Strength", "Thick-target yield ↔ ωγ", "Nuclear astrophysics"),
    Penetrability("Penetrability & Widths", "P_ℓ, shift, Wigner limit", "Nuclear astrophysics"),
    Yield("Yield & Beam Time", "Count rate, statistics, beam time", "Run planning"),
    Beam("Beam Current", "µA ↔ particles/s, charge, power", "Run planning"),
    Detector("Detector Response", "Resolution, efficiency curve fit", "Detectors & sources"),
    Spectrum("Detector Spectrum", "γ or particle peaks, contaminants", "Detectors & sources"),
    Analysis("Spectrum Analysis", "Open a spectrum, find peaks, calibrate", "Detectors & sources"),
    Sources("Calibration Sources", "Activity today, γ lines", "Detectors & sources"),
    Decay("Decay Calculator", "Activity, atoms, mass, time", "Detectors & sources"),
    Nuclides("Nuclides", "Masses, half-lives, isomers, reactions", "Data"),
    Notebook("Notebook", "Saved results and notes", "Data"),
    Experiments("Experiments", "Saved setups and run log", "Data"),
    Settings("Settings & About", "Caches, data sources, licences", "Data"),
    Constants("Constants", "CODATA 2018, nuclear and atomic", "Reference"),
    Units("Unit Converter", "Energy, T₉ ↔ kT, barns, lengths, activity", "Reference"),
    Formulas("Formula Sheet", "Kinematics, astrophysics, decay, detectors", "Reference"),
}

private val Accent = Color(0xFFF57329)

@Composable
fun GamowTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val scheme = if (dark) darkColorScheme(primary = Accent, secondary = Color(0xFFFFB68C), tertiary = Color(0xFFFFD54F))
        else lightColorScheme(primary = Color(0xFFC4501A), secondary = Accent, tertiary = Color(0xFF8D6E00))
    MaterialTheme(colorScheme = scheme, content = content)
}

@Composable
fun App(initialTool: Tool? = null) {
    val wb = remember { Workbench() }
    var current by remember { mutableStateOf(initialTool) }
    GamowTheme {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            BoxWithConstraints {
                val wide = maxWidth >= 760.dp
                if (wide) {
                    val tool = current ?: Tool.Kinematics
                    Row(Modifier.fillMaxSize()) {
                        Column(Modifier.width(300.dp).fillMaxHeight().verticalScroll(rememberScrollState()).padding(12.dp)) {
                            SetupSummary(wb) { current = Tool.Setup }
                            ToolList(selected = tool) { current = it }
                        }
                        VerticalDivider()
                        ToolPage(tool, wb, onEdit = { current = Tool.Setup }, onDone = { current = Tool.Kinematics }, modifier = Modifier.weight(1f))
                    }
                } else {
                    PlatformBackHandler(current != null) { current = null }
                    val tool = current
                    if (tool == null) {
                        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
                            Text("Gamow", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                            Spacer(Modifier.height(8.dp))
                            SetupSummary(wb) { current = Tool.Setup }
                            ToolList(selected = null) { current = it }
                        }
                    } else {
                        Column(Modifier.fillMaxSize()) {
                            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(start = 4.dp, top = 8.dp)) {
                                TextButton(onClick = { current = null }) { Text("‹ Tools") }
                                Text(tool.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            }
                            ToolPage(tool, wb, onEdit = { current = Tool.Setup }, onDone = { current = null }, modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ToolPage(tool: Tool, wb: Workbench, onEdit: () -> Unit, onDone: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxHeight().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp).widthIn(max = 900.dp)) {
        when (tool) {
            Tool.Setup -> SetupScreen(wb, onDone)
            Tool.QValue -> QValueScreen(wb, onEdit)
            Tool.Kinematics -> KinematicsScreen(wb, onEdit)
            Tool.Exfor -> ExforScreen(wb, onEdit)
            Tool.Rutherford -> RutherfordScreen(wb, onEdit)
            Tool.Doppler -> DopplerScreen(wb, onEdit)
            Tool.Beam -> BeamScreen(wb, onEdit)
            Tool.Detector -> DetectorScreen()
            Tool.Stopping -> StoppingScreen(wb, onEdit)
            Tool.Gamow -> GamowScreen(wb, onEdit)
            Tool.SFactor -> SFactorScreen(wb, onEdit)
            Tool.Rate -> RateScreen(wb, onEdit)
            Tool.Resonance -> ResonanceScreen(wb, onEdit)
            Tool.Penetrability -> PenetrabilityScreen(wb, onEdit)
            Tool.Yield -> YieldScreen(wb, onEdit)
            Tool.Spectrum -> SpectrumScreen(wb, onEdit)
            Tool.Analysis -> AnalysisScreen(wb)
            Tool.Sources -> SourcesScreen()
            Tool.Decay -> DecayScreen()
            Tool.Nuclides -> NuclidesScreen(wb, onUseReaction = onDone)
            Tool.Notebook -> NotebookScreen()
            Tool.Experiments -> ExperimentsScreen(wb, onRestored = onDone)
            Tool.Settings -> SettingsScreen()
            Tool.Constants -> ConstantsScreen()
            Tool.Units -> UnitsScreen()
            Tool.Formulas -> FormulasScreen()
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun SetupSummary(wb: Workbench, onEdit: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF5E1A2E)), modifier = Modifier.fillMaxWidth().clickable(onClick = onEdit)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("CURRENT SETUP", color = Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.labelMedium)
            Text(wb.reaction?.label ?: wb.reactionText, color = Color.White, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            val r = wb.reaction
            Text(buildString {
                append("Beam ${Fmt.fixed(wb.beamEnergy, 1)} keV")
                wb.ecm?.let { append(" · E c.m. ${Fmt.fixed(it, 1)} keV") }
                r?.let { append(" · Q ${Fmt.fixed(it.qValue, 1)} keV") }
            }, color = Color.White.copy(alpha = 0.9f), style = MaterialTheme.typography.bodyMedium)
            Text("Tap to edit", color = Color.White.copy(alpha = 0.6f), style = MaterialTheme.typography.labelSmall)
        }
    }
}

/** Pinned tools, kept between launches. */
private object Pins {
    var pinned by mutableStateOf((org.gamow.core.Prefs.get("pins") ?: "Kinematics,Yield,Stopping,Spectrum").split(',').mapNotNull { n -> Tool.entries.firstOrNull { it.name == n } })
        private set
    fun toggle(t: Tool) {
        pinned = if (t in pinned) pinned - t else pinned + t
        org.gamow.core.Prefs.put("pins", pinned.joinToString(",") { it.name })
    }
}

@Composable
private fun ToolList(selected: Tool?, onPick: (Tool) -> Unit) {
    var query by remember { mutableStateOf("") }
    OutlinedTextField(query, { query = it }, placeholder = { Text("Find a tool") }, singleLine = true,
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp))
    val q = query.trim()
    @Composable fun row(t: Tool) {
        ListItem(
            headlineContent = { Text(t.title, fontWeight = if (t == selected) FontWeight.SemiBold else null) },
            supportingContent = { Text(t.subtitle) },
            trailingContent = {
                TextButton(onClick = { Pins.toggle(t) }) { Text(if (t in Pins.pinned) "★" else "☆", color = MaterialTheme.colorScheme.primary) }
            },
            colors = ListItemDefaults.colors(containerColor = if (t == selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                else MaterialTheme.colorScheme.surface),
            modifier = Modifier.clickable { onPick(t) },
        )
    }
    @Composable fun header(text: String) = Text(text.uppercase(), style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 4.dp, top = 14.dp, bottom = 4.dp))
    if (q.isNotEmpty()) {
        val hits = Tool.entries.filter { it.title.contains(q, true) || it.subtitle.contains(q, true) || it.group.contains(q, true) }
        header("${hits.size} tool${if (hits.size == 1) "" else "s"}")
        hits.forEach { row(it) }
        return
    }
    if (Pins.pinned.isNotEmpty()) { header("Pinned"); Pins.pinned.forEach { row(it) } }
    for (group in Tool.entries.map { it.group }.distinct()) {
        val rest = Tool.entries.filter { it.group == group && it !in Pins.pinned }
        if (rest.isEmpty()) continue          // every tool of the group is pinned above
        header(group)
        rest.forEach { row(it) }
    }
}
