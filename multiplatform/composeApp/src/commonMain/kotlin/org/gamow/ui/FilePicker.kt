package org.gamow.ui

import androidx.compose.runtime.Composable

/** Returns a function that asks the user for a file and delivers its name and bytes (Android: document picker; desktop: file dialog). */
@Composable
expect fun rememberFilePicker(onFile: (name: String, bytes: ByteArray) -> Unit): () -> Unit
