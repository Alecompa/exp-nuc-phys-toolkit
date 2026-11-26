package org.gamow.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.gamow.core.Prefs
import org.gamow.core.formatDate
import org.gamow.core.nowEpochSeconds

/** A saved calculation: what tool, which reaction, the values shown, and the user's note. */
data class NotebookEntry(val id: String, val date: Double, val tool: String, val title: String, val lines: List<Pair<String, String>>, val note: String) {
    val text: String get() = buildString {
        appendLine("$tool — $title (${formatDate(date)})")
        for ((k, v) in lines) appendLine("  $k: $v")
        if (note.isNotBlank()) appendLine("  Note: $note")
    }
}

/** Entries stored as records separated by \u001E, fields by \u001F, label/value by \u001D. */
object NotebookStore {
    private const val RS = '\u001E'; private const val FS = '\u001F'; private const val GS = '\u001D'
    var entries by mutableStateOf(load())
        private set

    private fun load(): List<NotebookEntry> = (Prefs.get("notebook") ?: "").split(RS).mapNotNull { rec ->
        val f = rec.split(FS)
        if (f.size < 6) null else NotebookEntry(f[0], f[1].toDoubleOrNull() ?: 0.0, f[2], f[3],
            f[4].split(GS).chunked(2).filter { it.size == 2 }.map { it[0] to it[1] }, f[5])
    }

    private fun save() = Prefs.put("notebook", entries.joinToString(RS.toString()) { e ->
        listOf(e.id, "${e.date}", e.tool, e.title, e.lines.flatMap { listOf(it.first, it.second) }.joinToString(GS.toString()), e.note)
            .joinToString(FS.toString()) { it.replace(RS, ' ').replace(FS, ' ') }
    })

    fun add(tool: String, title: String, lines: List<Pair<String, String>>) {
        val now = nowEpochSeconds()
        entries = listOf(NotebookEntry("n" + (now * 1000).toLong(), now, tool, title, lines, "")) + entries
        save()
    }
    fun update(e: NotebookEntry) { entries = entries.map { if (it.id == e.id) e else it }; save() }
    fun remove(id: String) { entries = entries.filter { it.id != id }; save() }
}

/** "Save to notebook" with a short confirmation. */
@Composable
fun SaveToNotebook(tool: String, title: String, lines: () -> List<Pair<String, String>>) {
    var saved by remember(title) { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        OutlinedButton(onClick = { NotebookStore.add(tool, title, lines()); saved = true }) { Text("Save to notebook") }
        if (saved) Text("  Saved ✓", color = MaterialTheme.colorScheme.primary)
    }
}

@Composable
fun NotebookScreen() {
    val clipboard = LocalClipboardManager.current
    val entries = NotebookStore.entries
    SectionCard(footer = "Results saved from the tools, newest first. Copy one entry or all of them as text, e.g. into the logbook.") {
        if (entries.isEmpty()) Text("Nothing saved yet. Use “Save to notebook” in a tool.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        else {
            val export = rememberTextExporter()
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { clipboard.setText(AnnotatedString(entries.joinToString("\n") { it.text })) }) { Text("Copy all") }
                OutlinedButton(onClick = { export("gamow_notebook.csv", notebookCsv(entries)) }) { Text("Export CSV") }
                OutlinedButton(onClick = { export("gamow_notebook.txt", entries.joinToString("\n") { it.text }) }) { Text("Export text") }
            }
        }
    }
    for (e in entries) {
        SectionCard {
            Text("${e.tool} · ${formatDate(e.date)}", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(e.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            for ((k, v) in e.lines) ValueRow(k, v)
            var note by remember(e.id) { mutableStateOf(e.note) }
            OutlinedTextField(note, { note = it; NotebookStore.update(e.copy(note = it)) }, label = { Text("Note") }, modifier = Modifier.fillMaxWidth())
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = { clipboard.setText(AnnotatedString(e.text)) }) { Text("Copy") }
                TextButton(onClick = { NotebookStore.remove(e.id) }) { Text("Delete") }
            }
        }
    }
}

/** One row per value: date, tool, title, quantity, value, note (RFC 4180 quoting). */
fun notebookCsv(entries: List<NotebookEntry>): String {
    fun q(x: String) = if (x.any { it == ',' || it == '"' || it == '\n' }) "\"" + x.replace("\"", "\"\"") + "\"" else x
    return "date,tool,title,quantity,value,note\n" + entries.flatMap { e ->
        (e.lines.ifEmpty { listOf("" to "") }).map { (k, v) -> listOf(formatDate(e.date), e.tool, e.title, k, v, e.note).joinToString(",") { q(it) } }
    }.joinToString("\n")
}
