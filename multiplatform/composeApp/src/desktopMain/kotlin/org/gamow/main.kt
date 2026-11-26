package org.gamow

import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import org.gamow.ui.App

fun main() = application {
    Window(onCloseRequest = ::exitApplication, title = "Gamow", state = rememberWindowState(size = DpSize(1200.dp, 820.dp))) {
        App()
    }
}
