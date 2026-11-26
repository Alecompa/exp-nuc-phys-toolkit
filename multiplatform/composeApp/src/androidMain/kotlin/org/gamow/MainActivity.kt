package org.gamow

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.Box
import androidx.compose.ui.Modifier
import org.gamow.core.Prefs
import org.gamow.ui.App

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Prefs.context = applicationContext
        enableEdgeToEdge()
        setContent { Box(Modifier.safeDrawingPadding()) { App() } }
    }
}
