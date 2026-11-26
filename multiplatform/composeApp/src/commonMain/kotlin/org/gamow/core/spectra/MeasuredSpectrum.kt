package org.gamow.core.spectra

import org.gamow.core.CalibrationSource
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

// Import

class SpectrumImportException(val kind: Kind, val detail: String = "") : Exception() {
    enum class Kind { EMPTY, UNREADABLE }

    override val message: String
        get() = when (kind) {
            Kind.EMPTY -> "The file has no channel data."
            Kind.UNREADABLE -> "Could not read the spectrum: $detail."
        }
}

/** A measured histogram: counts per channel, with an optional energy calibration. */
data class MeasuredSpectrum(
    val name: String,
    val counts: List<Double>,
    val liveTime: Double? = null,
    val realTime: Double? = null,
    /** Calibration found in the file (ORTEC $ENER_FIT / $MCA_CAL), if any. */
    val fileCalibration: EnergyCalibration? = null,
) {
    companion object {
        /** Foundation's CharacterSet.newlines: every one of these characters ends a line ("\r\n" gives an empty line). */
        private fun lines(text: String): List<String> =
            text.split('\n', '\r', '\u000B', '\u000C', '\u0085', ' ', ' ')

        /** Foundation's CharacterSet.whitespaces: space, tab and the other Unicode space separators. */
        private fun trimSpaces(s: String): String = s.trim { it == ' ' || it == '\t' || it.category == CharCategory.SPACE_SEPARATOR }

        private fun words(s: String): List<String> = s.split(' ').filter { it.isNotEmpty() }

        /**
         * Reads ORTEC .Spe (text) and .Chn (binary), or plain text: one column of counts, or two columns (channel or
         * energy, counts) separated by commas, semicolons, tabs or spaces. Lines starting with # and non-numeric headers
         * are skipped. A two-column file whose first column is not 0, 1, 2… is taken as calibrated energies (keV) and
         * gives a linear calibration from its first and last rows. Throws [SpectrumImportException].
         */
        fun read(data: ByteArray, name: String): MeasuredSpectrum {
            if (name.lowercase().endsWith(".chn")) return chn(data, name)
            val raw = try {
                data.decodeToString(throwOnInvalidSequence = true)
            } catch (e: CharacterCodingException) {
                String(CharArray(data.size) { (data[it].toInt() and 0xFF).toChar() })      // ISO Latin-1
            }
            // Windows line endings (files from DAQ PCs).
            val text = raw.replace("\r\n", "\n").replace('\r', '\n')
            if ("\$DATA:" in text) return spe(text, name)
            return columns(text, name)
        }

        internal fun spe(text: String, name: String): MeasuredSpectrum {
            val lines = lines(text).map { trimSpaces(it) }
            var counts: List<Double> = emptyList()
            var live: Double? = null
            var real: Double? = null
            var cal: EnergyCalibration? = null
            var i = 0
            while (i < lines.size) {
                when (lines[i]) {
                    "\$MEAS_TIM:" -> {
                        val t = lines.getOrNull(i + 1)?.let { words(it).mapNotNull(SpecMath::parseDouble) } ?: emptyList()
                        if (t.size >= 2) { live = t[0]; real = t[1] }
                        i += 2
                    }
                    "\$DATA:" -> {
                        val range = lines.getOrNull(i + 1)?.let { words(it).mapNotNull(SpecMath::parseInt) } ?: emptyList()
                        if (range.size < 2 || range[1] < range[0]) throw SpectrumImportException(SpectrumImportException.Kind.UNREADABLE, "bad \$DATA range")
                        val n = range[1] - range[0] + 1
                        counts = (0 until n).mapNotNull { k -> lines.getOrNull(i + 2 + k)?.let(SpecMath::parseDouble) }
                        i += 2 + n
                    }
                    "\$ENER_FIT:", "\$MCA_CAL:" -> {
                        val isFit = lines[i] == "\$ENER_FIT:"
                        // $MCA_CAL: first line is the number of terms.
                        val row = (if (isFit) lines.getOrNull(i + 1) else lines.getOrNull(i + 2)) ?: ""
                        val c = words(row).mapNotNull(SpecMath::parseDouble)
                        if (c.size >= 2 && c[1] != 0.0 && cal == null) cal = EnergyCalibration(c.take(3))
                        i += if (isFit) 2 else 3
                    }
                    else -> i += 1
                }
            }
            if (counts.isEmpty()) throw SpectrumImportException(SpectrumImportException.Kind.EMPTY)
            return MeasuredSpectrum(name, counts, live, real, cal)
        }

        /** ORTEC .Chn: 32-byte header (type −1, live and real time in 20 ms ticks, start channel, length), then 32-bit channel contents. */
        internal fun chn(data: ByteArray, name: String): MeasuredSpectrum {
            if (data.size <= 32) throw SpectrumImportException(SpectrumImportException.Kind.UNREADABLE, "file too short for .Chn")
            fun b(o: Int) = data[o].toInt() and 0xFF
            fun i16(o: Int): Int = (b(o) or (b(o + 1) shl 8)).toShort().toInt()
            fun u32(o: Int): Long = (b(o).toLong() or (b(o + 1).toLong() shl 8) or (b(o + 2).toLong() shl 16) or (b(o + 3).toLong() shl 24))
            if (i16(0) != -1) throw SpectrumImportException(SpectrumImportException.Kind.UNREADABLE, "not an ORTEC .Chn file")
            val real = u32(8).toDouble() * 0.02
            val live = u32(12).toDouble() * 0.02
            val n = b(30) or (b(31) shl 8)
            if (n <= 0 || data.size < 32 + 4 * n) throw SpectrumImportException(SpectrumImportException.Kind.UNREADABLE, "channel count does not match the file size")
            val counts = (0 until n).map { u32(32 + 4 * it).toDouble() }
            return MeasuredSpectrum(name, counts, live, real)
        }

        internal fun columns(text: String, name: String): MeasuredSpectrum {
            var rows = ArrayList<List<Double>>()
            for (raw in lines(text)) {
                val line = trimSpaces(raw)
                if (line.isEmpty() || line.startsWith("#")) continue
                val tokens = line.split(',', ';', '\t', ' ').filter { it.isNotEmpty() }
                val fields = tokens.mapNotNull(SpecMath::parseDouble)
                // Header or comment lines ("Live time: 100") have a non-numeric token: skip them whole.
                if (fields.isEmpty() || fields.size != tokens.size) continue
                rows.add(fields)
            }
            if (rows.isEmpty()) throw SpectrumImportException(SpectrumImportException.Kind.EMPTY)
            // The most common row width is the data layout (ties: the narrower).
            val widths = rows.groupingBy { it.size }.eachCount()
            val width = widths.entries.sortedWith(compareBy({ -it.value }, { it.key })).first().key
            rows = ArrayList(rows.filter { it.size >= width })
            if (width == 1) return MeasuredSpectrum(name, rows.map { it[0] })
            // Energies may be listed high to low; store channels in increasing energy.
            if (rows.size > 1 && rows[0][0] > rows[rows.size - 1][0]) rows.reverse()
            val x = rows.map { it[0] }
            val y = rows.map { it[1] }
            val isChannels = x.withIndex().all { (i, v) -> abs(v - i.toDouble() - x[0]) < 1e-9 }
            if (isChannels) {
                // Channel numbers may start at 0 or 1; pad so that index = channel.
                val start = max(0, x[0].toInt())
                return MeasuredSpectrum(name, List(start) { 0.0 } + y)
            }
            var cal: EnergyCalibration? = null
            val first = x.first()
            val last = x.last()
            if (x.size > 1 && last != first) cal = EnergyCalibration(listOf(first, (last - first) / (x.size - 1)))
            return MeasuredSpectrum(name, y, fileCalibration = cal)
        }
    }
}

// Calibration

/** E(ch) = c₀ + c₁ ch + c₂ ch², keV. */
data class EnergyCalibration(val coefficients: List<Double>) {
    fun energy(channel: Double): Double {
        var s = 0.0
        coefficients.forEachIndexed { k, c -> s += c * channel.pow(k.toDouble()) }
        return s
    }

    /** Channel for an energy (inverse; Newton from the linear guess). */
    fun channel(energy: Double): Double {
        val c0 = coefficients.getOrNull(0) ?: 0.0
        val c1 = coefficients.getOrNull(1) ?: 1.0
        var ch = (energy - c0) / c1
        repeat(8) {
            var slope = 0.0
            for (k in 1..max(1, coefficients.size - 1)) slope += k.toDouble() * (coefficients.getOrNull(k) ?: 0.0) * ch.pow((k - 1).toDouble())
            if (slope == 0.0) return ch
            ch -= (energy(ch) - energy) / slope
        }
        return ch
    }

    val gain: Double get() = coefficients.getOrNull(1) ?: 1.0
}

// Peak search

data class FoundPeak(
    /** Channel (fractional), with its statistical uncertainty. */
    val centroid: Double,
    val centroidUncertainty: Double,
    /** FWHM, channels. */
    val fwhm: Double,
    /** Net area above the SNIP background, counts. */
    val area: Double,
    val areaUncertainty: Double,
    /** Significance of the second-derivative response. */
    val significance: Double,
) {
    val id: Int get() = SpecMath.roundHalfAway(centroid * 100).toInt()
}

object PeakSearch {
    /** SNIP background (Morháč) on the LLS-transformed spectrum, clipping window up to `iterations` channels. */
    fun snipBackground(counts: List<Double>, iterations: Int): List<Double> {
        val n = counts.size
        if (n <= 2 || iterations <= 0) return counts
        var v = DoubleArray(n) { ln(ln(sqrt(max(0.0, counts[it]) + 1) + 1) + 1) }   // LLS: ln(ln(√(y+1)+1)+1)
        val w = v.copyOf()
        var p = min(iterations, n / 2)
        while (p >= 1) {
            for (i in p until n - p) w[i] = min(v[i], 0.5 * (v[i - p] + v[i + p]))
            v = w.copyOf()
            p--
        }
        return v.map { val a = exp(exp(it) - 1) - 1; max(0.0, a * a - 1) }
    }

    /**
     * Peaks of `counts` with a smoothed second-derivative filter matched to `fwhm` channels (Mariscotti). The zero-sum
     * kernel cancels a linearly varying background; candidates above `threshold` standard deviations are refined with
     * moments of the net counts above the SNIP background.
     */
    fun find(counts: List<Double>, fwhm: Double, threshold: Double = 4.0): List<FoundPeak> {
        val n = counts.size
        if (n <= 16 || !(fwhm > 0.5)) return emptyList()
        val sigma = fwhm / 2.354_820_045
        val half = max(2, ceil(3 * sigma).toInt())
        if (n < 2 * half + 3) return emptyList()                    // the filter needs room on both sides
        val raw = DoubleArray(2 * half + 1) {
            val x = (it - half).toDouble() / sigma
            (1 - x * x) * exp(-0.5 * x * x)
        }
        var total = 0.0
        for (k in raw) total += k
        val mean = total / raw.size
        val kernel = DoubleArray(raw.size) { raw[it] - mean }
        val response = DoubleArray(n)
        val sig = DoubleArray(n)
        for (i in half until n - half) {
            var r = 0.0
            var v = 0.0
            for (k in kernel.indices) {
                val w = kernel[k]
                val c = max(0.0, counts[i + k - half])
                r += w * c; v += w * w * c
            }
            response[i] = r
            sig[i] = if (v > 0) r / sqrt(v) else 0.0
        }
        val background = snipBackground(counts, max(4, SpecMath.roundHalfAway(2.5 * fwhm).toInt()))
        val peaks = ArrayList<FoundPeak>()
        for (i in (half + 1) until (n - half - 1)) {
            if (!(sig[i] > threshold && response[i] >= response[i - 1] && response[i] > response[i + 1])) continue
            // Moments of the net counts within ±1.5 FWHM, re-centred once.
            var centre = i.toDouble()
            var area = 0.0; var m1 = 0.0; var m2 = 0.0; var variance = 0.0
            for (pass in 0 until 2) {
                val lo = max(0, SpecMath.roundHalfAway(centre - 1.5 * fwhm).toInt())
                val hi = min(n - 1, SpecMath.roundHalfAway(centre + 1.5 * fwhm).toInt())
                area = 0.0; m1 = 0.0; m2 = 0.0; variance = 0.0
                for (j in lo..hi) {
                    val net = counts[j] - background[j]
                    // A channel the SNIP background leaves unchanged has net ≈ 0 to rounding; skip it deterministically.
                    if (!(net > 1e-9 * max(counts[j], 1.0))) continue
                    area += net; m1 += net * j.toDouble(); m2 += net * j.toDouble() * j.toDouble()
                    variance += max(counts[j], 0.0) + background[j]
                }
                if (!(area > 0)) break
                centre = m1 / area
            }
            if (!(area > 0)) continue
            val s2 = max(0.25, m2 / area - centre * centre)
            // A second moment truncated at ±1.5 FWHM (±3.53 σ) is 0.994 σ²; undo that.
            val width = 2.354_820_045 * sqrt(s2 / 0.994)
            peaks.add(FoundPeak(centre, sqrt(s2 / area), width, area, sqrt(variance), sig[i]))
        }
        // Merge candidates closer than one FWHM (keep the more significant).
        val merged = ArrayList<FoundPeak>()
        for (p in peaks.sortedByDescending { it.significance }) {
            if (merged.none { abs(it.centroid - p.centroid) < fwhm }) merged.add(p)
        }
        return merged.sortedBy { it.centroid }
    }
}

// Automatic calibration

data class CalibrationLine(
    val energy: Double,
    /** Relative weight for matching (emission intensity × rough efficiency); larger = more important. */
    val weight: Double = 1.0,
    val label: String,
) {
    val id: String get() = "$label-${SpecMath.swiftDescription(energy)}"
}

data class CalibrationResult(
    val calibration: EnergyCalibration,
    val matches: List<Match>,
    /** RMS of the residuals, keV. */
    val rms: Double,
) {
    data class Match(val peak: FoundPeak, val line: CalibrationLine, val fitted: Double) {
        val residual: Double get() = fitted - line.energy
        val id: String get() = "${peak.id}-${line.id}"
    }
}

object AutoCalibration {
    /**
     * Matches the strongest peaks to the reference lines by voting over (gain, offset) hypotheses from every pair of
     * peaks and pair of lines, then refines by least squares (quadratic with `quadratic` and ≥ 4 matches). `gainRange`
     * (keV per channel) and `maxOffset` (keV) bound the hypotheses.
     */
    fun calibrate(
        peaks: List<FoundPeak>, lines: List<CalibrationLine>, quadratic: Boolean = false,
        gainRange: ClosedFloatingPointRange<Double> = 0.01..100.0, maxOffset: Double = 100.0, tolerance: Double? = null,
    ): CalibrationResult? {
        val ps = peaks.sortedByDescending { it.significance }.take(20)
        val ls = lines.sortedByDescending { it.weight }.take(20)
        if (ps.size < 2 || ls.size < 2) return null
        val byWeight = ls.sortedByDescending { it.weight }
        val medianFwhm = ps.map { it.fwhm }.sorted()[ps.size / 2]

        fun assign(cal: EnergyCalibration, tol: Double): List<CalibrationResult.Match> {
            val used = HashSet<Int>()
            val out = ArrayList<CalibrationResult.Match>()
            for (l in byWeight) {
                var best: Int = -1
                var bestE = 0.0
                for ((i, p) in ps.withIndex()) {
                    if (i in used) continue
                    val e = cal.energy(p.centroid)
                    if (best < 0 || abs(e - l.energy) < abs(bestE - l.energy)) { best = i; bestE = e }
                }
                if (best >= 0 && abs(bestE - l.energy) <= tol) {
                    used.add(best)
                    out.add(CalibrationResult.Match(ps[best], l, bestE))
                }
            }
            return out
        }

        var bestScore = 0.0
        var bestRms = 0.0
        var bestCal: EnergyCalibration? = null
        for (i in ps.indices) {
            for (j in i + 1 until ps.size) {
                val (a, b) = if (ps[i].centroid < ps[j].centroid) ps[i] to ps[j] else ps[j] to ps[i]
                if (!(b.centroid - a.centroid > 1)) continue
                for (k in ls.indices) {
                    for (m in k + 1 until ls.size) {
                        val (la, lb) = if (ls[k].energy < ls[m].energy) ls[k] to ls[m] else ls[m] to ls[k]
                        val gain = (lb.energy - la.energy) / (b.centroid - a.centroid)
                        if (!(gain >= gainRange.start && gain <= gainRange.endInclusive)) continue
                        val offset = la.energy - gain * a.centroid
                        if (!(abs(offset) <= maxOffset)) continue
                        val cal = EnergyCalibration(listOf(offset, gain))
                        // Tolerance: given, or two FWHM of the peaks in keV with a 1 keV floor.
                        val fw = medianFwhm * gain
                        val matched = assign(cal, tolerance ?: max(1.0, 2 * fw))
                        if (matched.size < 2) continue
                        var score = 0.0
                        for (mt in matched) score += mt.line.weight + 1
                        var ss = 0.0
                        for (mt in matched) ss += mt.residual * mt.residual
                        val rms = sqrt(ss / matched.size)
                        if (bestCal == null || score > bestScore + 1e-9 || (abs(score - bestScore) < 1e-9 && rms < bestRms)) {
                            bestScore = score; bestRms = rms; bestCal = cal
                        }
                    }
                }
            }
        }
        var cal = bestCal ?: return null
        // Refine: weighted least squares on the matched pairs, then re-match with a tighter tolerance.
        var matches: List<CalibrationResult.Match> = emptyList()
        for (pass in 0 until 3) {
            val fw = medianFwhm * cal.gain
            matches = assign(cal, tolerance ?: max(0.5, (if (pass == 0) 2.0 else 1.5) * fw))
            if (matches.size < 2) return null
            val order = if (quadratic && matches.size >= 4) 2 else 1
            val c = fit(matches.map { Triple(it.peak.centroid, it.line.energy, max(1e-3, it.peak.centroidUncertainty)) }, order) ?: break
            cal = EnergyCalibration(c)
        }
        val final = matches.map { CalibrationResult.Match(it.peak, it.line, cal.energy(it.peak.centroid)) }
        var ss = 0.0
        for (f in final) ss += f.residual * f.residual
        val rms = sqrt(ss / final.size)
        return CalibrationResult(cal, final.sortedBy { it.line.energy }, rms)
    }

    /** Weighted polynomial least squares E = Σ cₖ chᵏ, weights 1/σ_ch²; points are (channel, energy, σ_channel). */
    fun fit(points: List<Triple<Double, Double, Double>>, order: Int): List<Double>? {
        val m = order + 1
        if (points.size < m) return null
        // Centre the channels for conditioning, then expand back.
        var sum = 0.0
        for (p in points) sum += p.first
        val c0 = sum / points.size
        val a = Array(m) { DoubleArray(m) }
        val b = DoubleArray(m)
        for (p in points) {
            val w = 1 / (p.third * p.third)
            val x = p.first - c0
            val row = DoubleArray(m) { x.pow(it.toDouble()) }
            for (r in 0 until m) {
                b[r] += w * row[r] * p.second
                for (c in 0 until m) a[r][c] += w * row[r] * row[c]
            }
        }
        val q = EfficiencyCurve.solve(a.map { it.toList() }, b.toList()) ?: return null
        // Σ qₖ (ch − c0)ᵏ → coefficients in ch.
        val out = DoubleArray(m)
        for (k in 0 until m) for (j in 0..k) out[j] += q[k] * binomial(k, j).toDouble() * (-c0).pow((k - j).toDouble())
        return out.toList()
    }

    private fun binomial(n: Int, k: Int): Int {
        if (!(k > 0 && k < n)) return 1
        var r = 1
        for (i in 1..k) r = r * (n - i + 1) / i
        return r
    }

    /** Reference lines of calibration sources, weighted by intensity (%) and a rough 1/E efficiency. */
    fun lines(sources: List<CalibrationSource>, minIntensity: Double = 2.0): List<CalibrationLine> = sources.flatMap { s ->
        s.prominentLines(minIntensity).filter { it.kind == "gamma" && it.energy > 40 }.map {
            CalibrationLine(it.energy, it.intensity * 1000 / max(it.energy, 100.0), s.label)
        }
    }
}
