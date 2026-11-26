package org.gamow.ui

import androidx.compose.runtime.Composable

/** Returns a function that asks the user for a file and delivers its name and bytes (Android: document picker; desktop: file dialog). */
@Composable
expect fun rememberFilePicker(onFile: (name: String, bytes: ByteArray) -> Unit): () -> Unit

/** Returns a function that hands a text file to the user (Android: share sheet; desktop: save dialog). */
@Composable
expect fun rememberTextExporter(): (fileName: String, text: String) -> Unit
