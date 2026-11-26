package org.gamow.core.spectra

import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** Expected areas in a region; these are model components, not a background-subtracted measurement. */
data class SpectrumRegion(
    val photopeak: Double = 0.0,
    val compton: Double = 0.0,
    val background: Double = 0.0,
    val escape: Double = 0.0,
) {
    val total: Double get() = photopeak + compton + background + escape

    companion object {
        /**
         * Partially intersected channels contribute in proportion to their overlap with the ROI. This assumes uniform
         * counts within each channel; it does not re-integrate the response model.
         */
        fun integrate(bins: List<SpectrumBin>, binWidth: Double, lower: Double, upper: Double): SpectrumRegion {
            if (!binWidth.isFinite() || !(binWidth > 0) || !lower.isFinite() || !upper.isFinite() || !(upper > lower)) return SpectrumRegion()
            var p = 0.0; var c = 0.0; var b = 0.0; var e = 0.0
            for (bin in bins) {
                val overlap = max(0.0, min(upper, bin.energy + binWidth / 2) - max(lower, bin.energy - binWidth / 2))
                val fraction = min(1.0, overlap / binWidth)
                p += fraction * bin.photopeak
                c += fraction * bin.compton
                b += fraction * bin.background
                e += fraction * bin.escape
            }
            return SpectrumRegion(p, c, b, e)
        }
    }
}

/** Display-only reduction: retain extrema in energy buckets so narrow peaks do not disappear. */
object SpectrumPlotSampling {
    /** Analysis and CSV export must always use the original channels. */
    fun envelope(bins: List<SpectrumBin>, budget: Int = 1200): List<SpectrumBin> {
        if (budget < 8 || bins.size <= budget) return bins
        val buckets = max(1, budget / 8)
        val size = ceil(bins.size.toDouble() / buckets).toInt()
        val indices = HashSet<Int>()
        val keys: List<(SpectrumBin) -> Double> = listOf({ it.total }, { it.photopeak }, { it.compton }, { it.escape })
        var start = 0
        while (start < bins.size) {
            val end = min(bins.size, start + size)
            indices.add(start); indices.add(end - 1)
            for (key in keys) {
                var low = start
                var high = start
                for (i in start until end) {
                    if (key(bins[i]) < key(bins[low])) low = i
                    if (key(bins[i]) > key(bins[high])) high = i
                }
                indices.add(low); indices.add(high)
            }
            start += size
        }
        return indices.sorted().map { bins[it] }
    }
}
