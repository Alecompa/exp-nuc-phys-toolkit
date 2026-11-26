package org.gamow

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.use
import org.gamow.ui.App
import org.gamow.ui.Tool
import org.jetbrains.skia.EncodedImageFormat
import java.io.File
import kotlin.test.Test

/** Renders screens to PNG for a visual check when GAMOW_RENDER_DIR is set (skipped otherwise). */
class RenderScreens {
    private val dir = System.getenv("GAMOW_RENDER_DIR")?.let(::File)

    private fun render(name: String, w: Int, h: Int, tool: Tool?, waitMs: Long = 0, fontScale: Float = 1f) {
        val out = dir ?: return
        ImageComposeScene(w * 2, h * 2, density = Density(2f, fontScale)) { App(tool) }.use { scene ->
            scene.render()                       // first frame: layout, starts downloads
            var t = 1_000_000_000L
            val until = System.currentTimeMillis() + waitMs
            while (System.currentTimeMillis() < until) { Thread.sleep(250); scene.render(t); t += 250_000_000L }
            val img = scene.render(t + 1_000_000_000L)
            File(out, "$name.png").writeBytes(img.encodeToData(EncodedImageFormat.PNG)!!.bytes)
        }
    }

    @Test fun phoneScreens() {
        render("android_home", 412, 900, null)
        render("android_kinematics", 412, 1400, Tool.Kinematics)
        render("android_sfactor", 412, 1300, Tool.SFactor)
    }

    @Test fun newTools() {
        render("android_decay", 412, 1100, Tool.Decay)
        render("android_sources", 412, 1500, Tool.Sources)
        render("android_stopping", 412, 1500, Tool.Stopping)
        render("linux_exfor", 1200, 1000, Tool.Exfor, waitMs = 15_000)
    }

    @Test fun astroTools() {
        render("android_rate", 412, 1700, Tool.Rate)
        render("android_yield", 412, 1900, Tool.Yield)
        render("android_nuclides", 412, 1400, Tool.Nuclides)
    }

    @Test fun spectrumTools() {
        render("android_spectrum", 412, 1900, Tool.Spectrum, waitMs = 3000)
        // Spectrum Analysis with the synthetic ¹⁵²Eu + ⁶⁰Co test file, auto-calibrated as the button would do.
        val f = File("../../_claude/2026-11-25_screenshots/synthetic_Eu152_Co60.Spe")
        if (f.exists()) {
            val sp = org.gamow.core.spectra.MeasuredSpectrum.read(f.readBytes(), f.name)
            org.gamow.ui.AnalysisState.spectrum = sp
            val peaks = org.gamow.core.spectra.PeakSearch.find(sp.counts, 6.0, 5.0)
            val lines = org.gamow.core.spectra.AutoCalibration.lines(org.gamow.core.CalibrationSources.all.filter { it.id in setOf("60Co", "137Cs", "152Eu") })
            org.gamow.core.spectra.AutoCalibration.calibrate(peaks, lines)?.let { org.gamow.ui.AnalysisState.result = it; org.gamow.ui.AnalysisState.calibration = it.calibration }
            render("linux_analysis", 1200, 1300, Tool.Analysis, waitMs = 1500)
        }
    }

    @Test fun phaseOneTools() {
        render("android_rutherford", 412, 1500, Tool.Rutherford)
        render("android_doppler", 412, 1400, Tool.Doppler)
        render("android_detector", 412, 1500, Tool.Detector)
        render("android_units", 412, 1200, Tool.Units)
        render("linux_constants", 1200, 900, Tool.Constants)
    }

    @Test fun phaseThree() {
        render("android_home_pinned", 412, 1500, null)
        render("android_experiments", 412, 1000, Tool.Experiments)
        render("android_settings", 412, 1500, Tool.Settings)
    }

    /** Android's largest font setting (200 %): check that nothing overflows or overlaps. */
    @Test fun largeFonts() {
        render("a11y_kinematics_font200", 412, 2600, Tool.Kinematics, fontScale = 2f)
        render("a11y_yield_font200", 412, 3600, Tool.Yield, fontScale = 2f)
        render("a11y_home_font200", 412, 2000, null, fontScale = 2f)
    }

    @Test fun desktopScreens() {
        render("linux_gamow", 1200, 820, Tool.Gamow)
        render("linux_qvalue", 1200, 820, Tool.QValue)
    }
}
