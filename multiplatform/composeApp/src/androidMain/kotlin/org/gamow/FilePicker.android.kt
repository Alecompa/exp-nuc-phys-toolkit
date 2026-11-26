package org.gamow.ui

import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

@Composable
actual fun rememberFilePicker(onFile: (name: String, bytes: ByteArray) -> Unit): () -> Unit {
    val context = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val resolver = context.contentResolver
        val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        } ?: uri.lastPathSegment ?: "spectrum"
        val bytes = resolver.openInputStream(uri)?.use { it.readBytes() } ?: return@rememberLauncherForActivityResult
        onFile(name, bytes)
    }
    return { launcher.launch(arrayOf("*/*")) }
}

@Composable
actual fun rememberTextExporter(): (fileName: String, text: String) -> Unit {
    val context = LocalContext.current
    return { name, text ->
        val send = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
            type = if (name.endsWith(".csv")) "text/csv" else "text/plain"
            putExtra(android.content.Intent.EXTRA_SUBJECT, name)
            putExtra(android.content.Intent.EXTRA_TEXT, text)
        }
        context.startActivity(android.content.Intent.createChooser(send, name).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
