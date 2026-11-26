package org.gamow.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.*

/** One data set of a plot. */
data class PlotSeries(
    val points: List<Pair<Double, Double>>,
    val color: Color,
    /** Draw a line through the points (else markers). */
    val line: Boolean = true,
    val dashed: Boolean = false,
)

/**
 * A small scientific plot: linear or logarithmic axes with 1-2-5 or decade ticks, lines and markers, an optional
 * shaded x band and a vertical cursor. Touch, drag or (desktop) hover reports the x value under the pointer.
 */
@Composable
fun Plot(
    series: List<PlotSeries>,
    modifier: Modifier = Modifier,
    xLog: Boolean = false,
    yLog: Boolean = false,
    xLabel: String = "",
    yLabel: String = "",
    band: ClosedFloatingPointRange<Double>? = null,
    cursor: Double? = null,
    height: Dp = 260.dp,
    onPointer: ((Double) -> Unit)? = null,
    /** Spoken by screen readers; defaults to the axes and what the plot shows. */
    description: String? = null,
) {
    val measurer = rememberTextMeasurer()
    val axisColor = MaterialTheme.colorScheme.onSurfaceVariant
    val gridColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
    val accent = MaterialTheme.colorScheme.primary
    val labelStyle = TextStyle(color = axisColor, fontSize = 11.sp)

    val pts = series.flatMap { it.points }.filter { (x, y) -> x.isFinite() && y.isFinite() && (!xLog || x > 0) && (!yLog || y > 0) }
    if (pts.isEmpty()) return
    var x0 = pts.minOf { it.first }; var x1 = pts.maxOf { it.first }
    var y0 = pts.minOf { it.second }; var y1 = pts.maxOf { it.second }
    band?.let { if (!xLog || it.start > 0) { x0 = min(x0, it.start); x1 = max(x1, it.endInclusive) } }
    if (x1 <= x0) { x1 = x0 + if (x0 == 0.0) 1.0 else abs(x0) * 0.1 }
    if (y1 <= y0) { y1 = y0 + if (y0 == 0.0) 1.0 else abs(y0) * 0.1 }
    if (yLog) { y0 /= 1.5; y1 *= 1.5 } else { val pad = 0.06 * (y1 - y0); y0 -= pad; y1 += pad }
    fun tx(v: Double) = if (xLog) log10(v) else v
    fun ty(v: Double) = if (yLog) log10(v) else v
    val ax0 = tx(x0); val ax1 = tx(x1); val ay0 = ty(y0); val ay1 = ty(y1)

    // Margins follow the measured tick and axis labels, which grow with the user's font size.
    val density = androidx.compose.ui.platform.LocalDensity.current
    val yTickWidth = ticks(y0, y1, yLog).maxOfOrNull { measurer.measure(tickLabel(it), labelStyle).size.width } ?: 0
    val tickHeight = measurer.measure("0", labelStyle).size.height
    val axisHeight = if (xLabel.isEmpty()) 0 else measurer.measure(xLabel, labelStyle).size.height
    val leftPx = yTickWidth + with(density) { 10.dp.toPx() }
    val bottomPx = tickHeight + axisHeight + with(density) { 10.dp.toPx() }
    Canvas(
        modifier.fillMaxWidth().height(height).semantics {
            contentDescription = description ?: buildString {
                append("Plot of ${yLabel.ifEmpty { "values" }} versus ${xLabel.ifEmpty { "x" }}")
                append(", ${tickLabel(x0)} to ${tickLabel(x1)}")
                if (cursor != null) append(", cursor at ${tickLabel(cursor)}")
                if (onPointer != null) append(". Touch and drag to read values")
            }
        }.pointerInput(xLog, x0, x1, leftPx) {
            if (onPointer == null) return@pointerInput
            awaitPointerEventScope {
                while (true) {
                    val e = awaitPointerEvent()
                    val p = e.changes.firstOrNull()?.position ?: continue
                    val left = leftPx; val right = size.width - 12.dp.toPx()
                    if (p.x < left || p.x > right) continue
                    val f = (p.x - left) / (right - left)
                    val a = ax0 + f * (ax1 - ax0)
                    onPointer(if (xLog) 10.0.pow(a) else a)
                }
            }
        }
    ) {
        val left = leftPx; val right = size.width - 12.dp.toPx()
        val top = 8.dp.toPx(); val bottom = size.height - bottomPx
        fun px(v: Double) = (left + (tx(v) - ax0) / (ax1 - ax0) * (right - left)).toFloat()
        fun py(v: Double) = (bottom - (ty(v) - ay0) / (ay1 - ay0) * (bottom - top)).toFloat()

        band?.let {
            val a = px(max(it.start, x0)); val b = px(min(it.endInclusive, x1))
            if (b > a) drawRect(accent.copy(alpha = 0.13f), Offset(a, top), Size(b - a, bottom - top))
        }
        for (t in ticks(x0, x1, xLog)) {
            val x = px(t)
            drawLine(gridColor, Offset(x, top), Offset(x, bottom), 1f)
            val tl = measurer.measure(tickLabel(t), labelStyle)
            drawText(tl, topLeft = Offset((x - tl.size.width / 2).coerceIn(left - 20, right - tl.size.width.toFloat()), bottom + 4))
        }
        for (t in ticks(y0, y1, yLog)) {
            val y = py(t)
            drawLine(gridColor, Offset(left, y), Offset(right, y), 1f)
            val tl = measurer.measure(tickLabel(t), labelStyle)
            drawText(tl, topLeft = Offset(left - tl.size.width - 6, y - tl.size.height / 2))
        }
        drawRect(axisColor, Offset(left, top), Size(right - left, bottom - top), style = Stroke(1f))
        if (xLabel.isNotEmpty()) {
            val tl = measurer.measure(xLabel, labelStyle)
            drawText(tl, topLeft = Offset(right - tl.size.width, size.height - tl.size.height))
        }
        if (yLabel.isNotEmpty()) {
            val tl = measurer.measure(yLabel, labelStyle)
            drawText(tl, topLeft = Offset(left + 6, top + 2))
        }
        clipRectSafe(left, top, right, bottom) {
            for (s in series) {
                val valid = s.points.filter { (x, y) -> x.isFinite() && y.isFinite() && (!xLog || x > 0) && (!yLog || y > 0) }
                if (s.line && valid.size > 1) {
                    val path = Path()
                    valid.forEachIndexed { i, (x, y) -> if (i == 0) path.moveTo(px(x), py(y)) else path.lineTo(px(x), py(y)) }
                    drawPath(path, s.color, style = Stroke(2.dp.toPx(),
                        pathEffect = if (s.dashed) PathEffect.dashPathEffect(floatArrayOf(10f, 6f)) else null))
                } else {
                    for ((x, y) in valid) drawCircle(s.color, 3.dp.toPx(), Offset(px(x), py(y)))
                }
            }
            cursor?.let { if (it in x0..x1) drawLine(accent, Offset(px(it), top), Offset(px(it), bottom), 1.5f) }
        }
    }
}

private inline fun androidx.compose.ui.graphics.drawscope.DrawScope.clipRectSafe(
    l: Float, t: Float, r: Float, b: Float, block: androidx.compose.ui.graphics.drawscope.DrawScope.() -> Unit,
) = drawContext.canvas.let { c -> c.save(); c.clipRect(l, t, r, b); block(); c.restore() }

/** 1-2-5 ticks on a linear axis, decades (or 1-2-5 within a short log range) on a log axis. */
fun ticks(lo: Double, hi: Double, log: Boolean): List<Double> {
    if (log) {
        val a = floor(log10(lo)).toInt(); val b = ceil(log10(hi)).toInt()
        val span = b - a
        val steps = when { span > 12 -> listOf(1.0); span >= 3 -> listOf(1.0); else -> listOf(1.0, 2.0, 5.0) }
        val all = (a..b).flatMap { e -> steps.map { it * 10.0.pow(e) } }.filter { it in lo..hi }
        val every = max(1, all.size / 7)
        return all.filterIndexed { i, _ -> i % every == 0 }
    }
    val raw = (hi - lo) / 5
    val mag = 10.0.pow(floor(log10(raw)))
    val step = listOf(1.0, 2.0, 5.0, 10.0).map { it * mag }.first { it >= raw }
    val start = ceil(lo / step) * step
    return generateSequence(start) { it + step }.takeWhile { it <= hi + step * 1e-9 }.toList()
}

fun tickLabel(v: Double): String {
    val a = abs(v)
    if (a == 0.0) return "0"
    if (a >= 0.01 && a < 1e5) {
        val s = Fmt.fixed(v, if (a >= 100) 0 else if (a >= 1) 1 else 3)
        return if (s.contains('.')) s.trimEnd('0').trimEnd('.') else s
    }
    val e = floor(log10(a)).toInt()
    val m = v / 10.0.pow(e)
    val sup = org.gamow.core.Superscript.string(e.toString())
    return if (abs(m - 1) < 1e-6) "10$sup" else "${Fmt.fixed(m, 0)}×10$sup"
}
