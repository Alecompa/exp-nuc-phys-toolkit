package org.gamow.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import org.gamow.core.Reaction

/** A titled card holding rows. */
@Composable
fun SectionCard(title: String? = null, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        if (title != null) {
            // Not uppercased: "γ energy" would become "Γ ENERGY".
            Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 4.dp, bottom = 4.dp))
        }
        ElevatedCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
        }
        if (footer != null) {
            Text(footer, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 4.dp, top = 4.dp, end = 4.dp))
        }
    }
}

/** label ………… value unit */
@Composable
fun ValueRow(label: String, value: String, unit: String = "", note: String? = null) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            if (note != null) Text(note, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(value, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
        if (unit.isNotEmpty()) Text(" $unit", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** The headline number of a tool. */
@Composable
fun HeroNumber(value: String, unit: String, caption: String) {
    Column {
        Text(caption, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(verticalAlignment = Alignment.Bottom) {
            Text(value, style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.SemiBold)
            Text(" $unit", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 6.dp))
        }
    }
}

/**
 * A number field that keeps what the user types (also half-typed text such as "1e-") and reports valid values.
 * The text follows external changes of [value] (e.g. the − / + buttons).
 */
@Composable
fun NumberField(label: String, value: Double, unit: String, modifier: Modifier = Modifier, range: ClosedFloatingPointRange<Double>? = null,
                onValue: (Double) -> Unit) {
    var text by remember { mutableStateOf(Fmt.input(value)) }
    LaunchedEffect(value) { if (text.replace(',', '.').toDoubleOrNull() != value) text = Fmt.input(value) }
    val parsed = text.replace(',', '.').toDoubleOrNull()
    val ok = parsed != null && parsed.isFinite() && (range == null || parsed in range)
    OutlinedTextField(
        value = text,
        onValueChange = { t -> text = t; t.replace(',', '.').toDoubleOrNull()?.let { if (it.isFinite() && (range == null || it in range)) onValue(it) } },
        label = { Text(label) },
        suffix = { Text(unit) },
        isError = !ok,
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        modifier = modifier.fillMaxWidth(),
    )
}

/** Reaction title with an Edit action and the beam-energy stepper. */
@Composable
fun ReactionHeader(wb: Workbench, onEdit: () -> Unit, showBeam: Boolean = true) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        TextButton(onClick = onEdit, contentPadding = PaddingValues(0.dp)) {
            Text(wb.reaction?.label ?: wb.reactionText, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface)
            Text("  ▾", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.weight(1f))
        if (showBeam) BeamStepper(wb)
    }
}

@Composable
fun BeamStepper(wb: Workbench) {
    var step by remember { mutableStateOf(org.gamow.core.Prefs.get("beamStep")?.toDoubleOrNull() ?: 10.0) }
    var menu by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        FilledTonalButton(onClick = { wb.updateBeam(maxOf(0.0, (((wb.beamEnergy - step) / step).let { kotlin.math.round(it) }) * step)) },
            contentPadding = PaddingValues(horizontal = 10.dp), modifier = Modifier.height(36.dp)) { Text("−") }
        Box {
            TextButton(onClick = { menu = true }) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(Fmt.fixed(wb.beamEnergy, 1), fontWeight = FontWeight.SemiBold)
                    Text("keV beam", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                for (s in listOf(1.0, 5.0, 10.0, 25.0, 50.0, 100.0, 500.0)) {
                    DropdownMenuItem(text = { Text((if (s == step) "✓ " else "   ") + "step ${Fmt.fixed(s, 0)} keV") },
                        onClick = { step = s; org.gamow.core.Prefs.put("beamStep", "$s"); menu = false })
                }
            }
        }
        FilledTonalButton(onClick = { wb.updateBeam((kotlin.math.round((wb.beamEnergy + step) / step)) * step) },
            contentPadding = PaddingValues(horizontal = 10.dp), modifier = Modifier.height(36.dp)) { Text("+") }
    }
}

/** Wrapping row of reaction chips. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ReactionChips(items: List<String>, selected: String?, onPick: (Reaction) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        for (item in items) {
            val r = runCatching { Reaction.parse(item) }.getOrNull() ?: continue
            FilterChip(selected = r.plainLabel == selected, onClick = { onPick(r) }, label = { Text(r.label) })
        }
    }
}
