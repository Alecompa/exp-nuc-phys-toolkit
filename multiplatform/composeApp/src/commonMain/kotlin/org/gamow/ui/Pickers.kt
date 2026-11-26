package org.gamow.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import org.gamow.core.*

/**
 * Secondary options, folded by default, with a one-line summary of what is inside, so a screen shows the answer and
 * the few inputs that matter first.
 */
@Composable
fun MoreOptions(title: String = "More options", summary: String = "", initiallyOpen: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    var open by remember { mutableStateOf(initiallyOpen) }
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().clickable(role = Role.Button, onClickLabel = if (open) "Collapse" else "Expand") { open = !open }
            .semantics { stateDescription = if (open) "Expanded" else "Collapsed" }.padding(vertical = 6.dp), verticalAlignment = Alignment.Top) {
            Text(if (open) "▾ " else "▸ ", color = MaterialTheme.colorScheme.primary)
            Column {
                Text(title, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary)
                // What is inside, on its own line so it never squeezes the title.
                if (!open && summary.isNotEmpty()) Text(summary, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
            }
        }
        AnimatedVisibility(open) { Column(verticalArrangement = Arrangement.spacedBy(8.dp), content = content) }
    }
}

/** A row showing a chosen value; tapping it opens a chooser. */
@Composable
fun PickerField(label: String, value: String, onClick: () -> Unit) {
    OutlinedCard(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(value, style = MaterialTheme.typography.titleMedium)
            }
            Text("⌄", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Segmented choice among a few options. */
@Composable
fun <T> Choice(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        options.forEachIndexed { i, (v, label) ->
            SegmentedButton(selected = v == selected, onClick = { onSelect(v) }, shape = SegmentedButtonDefaults.itemShape(i, options.size)) {
                Text(label, maxLines = 1)
            }
        }
    }
}

/** A value field with a unit chooser (Bq/kBq/MBq, s/h/d/y, …). */
@Composable
fun <U> ValueWithUnit(label: String, value: Double, unit: U, units: List<Pair<U, String>>, scale: (U) -> Double,
                      onChange: (Double, U) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        NumberField(label, value / scale(unit), "", Modifier.weight(1f), range = 0.0..1e30) { onChange(it * scale(unit), unit) }
        Box {
            TextButton(onClick = { menu = true }) { Text(units.first { it.first == unit }.second + " ⌄") }
            DropdownMenu(menu, { menu = false }) {
                for ((u, l) in units) DropdownMenuItem(text = { Text(l) }, onClick = { onChange(value, u); menu = false })
            }
        }
    }
}

/** Lab nuclides offered first in the nuclide picker. */
val commonLabNuclides = listOf("3H", "7Be", "14C", "22Na", "26Al", "40K", "54Mn", "56Co", "57Co", "60Co", "65Zn", "68Ge", "88Y",
    "109Cd", "113Sn", "133Ba", "134Cs", "137Cs", "139Ce", "152Eu", "166mHo", "207Bi", "210Pb", "226Ra", "228Th", "232Th",
    "238U", "241Am", "244Cm", "252Cf")

/** Searchable chooser of radioactive states (NUBASE2020): calibration sources, common lab nuclides, then search. */
@Composable
fun NuclidePickerDialog(selected: String, onDismiss: () -> Unit, onPick: (NuclearState) -> Unit) {
    var query by remember { mutableStateOf("") }
    val radioactive = remember { Nubase.nubase2020.states.filter { it.isRadioactive } }
    val catalog = remember { CalibrationSources.all.map { it.state } }
    val common = remember { commonLabNuclides.mapNotNull { Nubase.nubase2020.state(it) }.filter { s -> catalog.none { it.id == s.id } } }
    val matches = remember(query) {
        val q = query.trim().lowercase()
        if (q.isEmpty()) emptyList() else {
            val digits = q.filter { it.isDigit() }; val letters = q.filter { it.isLetter() }
            radioactive.filter { s ->
                val sym = (Elements.symbol(s.z) ?: "").lowercase(); val name = (Elements.name(s.z) ?: "").lowercase()
                val letterOK = letters.isEmpty() || sym == letters || name.startsWith(letters) ||
                    (letters.endsWith("m") && sym == letters.dropLast(1) && s.state > 0)
                letterOK && (digits.isEmpty() || s.a.toString().startsWith(digits))
            }.sortedWith(compareBy({ it.z }, { it.a }, { it.state })).take(200)
        }
    }
    Dialog(onDismissRequest = onDismiss) {
        Card(Modifier.fillMaxWidth().heightIn(max = 640.dp)) {
            Column(Modifier.padding(16.dp)) {
                Text("Choose a nuclide", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                OutlinedTextField(query, { query = it }, placeholder = { Text("Element, mass number or 60Co") },
                    singleLine = true, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp))
                LazyColumn {
                    if (query.isBlank()) {
                        item { Header("Calibration sources") }
                        items(catalog) { NuclideRow(it, selected, onPick) }
                        item { Header("Common in the lab") }
                        items(common) { NuclideRow(it, selected, onPick) }
                    } else if (matches.isEmpty()) {
                        item { Text("No radioactive state matches “$query”.", Modifier.padding(8.dp)) }
                    } else {
                        items(matches) { NuclideRow(it, selected, onPick) }
                    }
                }
            }
        }
    }
}

@Composable
private fun Header(t: String) = Text(t, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary,
    modifier = Modifier.padding(top = 10.dp, bottom = 4.dp))

@Composable
private fun NuclideRow(s: NuclearState, selected: String, onPick: (NuclearState) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onPick(s) }.padding(vertical = 8.dp, horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text((if (s.plainLabel == selected) "✓ " else "") + s.label, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            Text(s.decayModes.take(2).joinToString(", ") { it.text }, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(halfLifeText(s), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

fun halfLifeText(s: NuclearState): String = s.halfLifeText.ifEmpty { s.halfLife?.let { formatHalfLife(it) } ?: "—" }

fun formatHalfLife(seconds: Double): String {
    if (seconds == Double.POSITIVE_INFINITY) return "stable"
    val (scale, unit) = HalfLifeFormat.unit(seconds)
    return "${Fmt.sig(seconds / scale, 4)} $unit"
}
