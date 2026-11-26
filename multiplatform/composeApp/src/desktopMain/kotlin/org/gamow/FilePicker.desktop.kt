package org.gamow.ui

import androidx.compose.runtime.Composable
import java.awt.FileDialog
import java.awt.Frame
import java.io.File

@Composable
actual fun rememberFilePicker(onFile: (name: String, bytes: ByteArray) -> Unit): () -> Unit = {
    val dialog = FileDialog(null as Frame?, "Open spectrum", FileDialog.LOAD)
    dialog.isVisible = true
    val dir = dialog.directory; val file = dialog.file
    if (dir != null && file != null) { val f = File(dir, file); onFile(f.name, f.readBytes()) }
}
