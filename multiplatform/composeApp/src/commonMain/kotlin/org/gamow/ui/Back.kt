package org.gamow.ui

import androidx.compose.runtime.Composable

/** The system Back gesture on Android; nothing on desktop. */
@Composable
expect fun PlatformBackHandler(enabled: Boolean, onBack: () -> Unit)
