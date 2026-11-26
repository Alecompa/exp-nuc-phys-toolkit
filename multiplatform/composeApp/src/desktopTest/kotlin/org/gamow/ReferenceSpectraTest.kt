package org.gamow

import kotlinx.serialization.json.*
import org.gamow.core.*
import org.gamow.core.spectra.*
import org.gamow.core.stopping.*
import java.io.File
import kotlin.math.*
import kotlin.test.*

/**
 * The spectrum and detector port must reproduce `Shared/reference_spectra.json`, written and checked by the Swift
 * ReferenceSpectraTests: attenuation and foils, pair production and escapes, resolution, efficiency fits, Doppler,
 * simulated spectra, in-beam lines and backgrounds, particle groups, cascades, peak search, auto-calibration and
 * spectrum files. Numbers to 1e-9 relative; counts, orders and labels exactly.
 */
class ReferenceSpectraTest {
    private val cases = Json.parseToJsonElement(File("../../Shared/reference_spectra.json").readText()).jsonArray
    private val fixtures = File("../../Packages/NucToolkit/Tests/NucPhysKitTests/Resources")
    private var checked = 0

    private fun target(spec: String): StoppingTarget {
        val p = spec.split("|")
        return when (p[0]) {
            "element" -> StoppingTarget.element(p[1].toInt())
            "compound" -> StoppingTarget.compound(SRIMData.shared.compounds.first { it.id == p[1] })
            "formula" -> StoppingTarget.formula(ChemicalFormula.parse(p[1]), p[2].toDouble(), p[3] == "1")
                .copy(compoundCorrection = p[4].toDouble())
            else -> fail(spec)
        }
    }

    private fun close(want: Double, got: Double) = want == got || abs(want - got) <= 1e-9 * abs(want)

    /** Every expected key must be reproduced; with `exactKeys` the key sets must also agree. */
    private fun check(label: String, expected: JsonObject, actual: Map<String, Double>, exactKeys: Boolean = true) {
        if (exactKeys) assertEquals(expected.keys, actual.keys, "$label: keys")
        for ((k, v) in expected) {
            val want = v.jsonPrimitive.double
            val got = actual[k] ?: fail("$label: missing $k")
            // Peak-area uncertainties sum counts + background over channels with net > 0; where SNIP leaves a channel
            // unchanged, net is ±1 ulp of 0 and the last bit of exp/log decides whether the channel counts (both
            // in Swift and here), so these are compared to 1 %.
            val ok = if (label.startsWith("peaks ") && k.endsWith(".da")) abs(want - got) <= 1e-2 * abs(want)
                // Calibration residuals E_fit − E_line cancel to ~1e-4 keV: compared to 1e-9 of the line energy scale.
                else if (label.startsWith("autocal") && k.endsWith(".res")) abs(want - got) <= 1e-8
                else close(want, got)
            assertTrue(ok, "$label $k: Swift $want, Kotlin $got")
            checked++
        }
    }

    private fun nums(s: String) = if (s.isEmpty()) emptyList() else s.split(",").map { it.toDouble() }
    private fun b(x: Boolean) = if (x) 1.0 else 0.0
    private fun attempt(f: () -> Unit): Double = try { f(); 0.0 } catch (e: SpectrumException) { 1.0 }

    // Spectra

    private fun summarize(bins: List<SpectrumBin>): Map<String, Double> {
        val v = HashMap<String, Double>()
        v["n"] = bins.size.toDouble()
        v["width"] = bins[0].energy * 2
        var t = 0.0; var p = 0.0; var c = 0.0; var bg = 0.0; var e = 0.0
        for (x in bins) { t += x.total; p += x.photopeak; c += x.compton; bg += x.background; e += x.escape }
        v["sumT"] = t; v["sumP"] = p; v["sumC"] = c; v["sumB"] = bg; v["sumE"] = e
        if (t > 0) {
            var m = 0.0
            for (x in bins) m += x.energy * x.total
            val mean = m / t
            v["centroid"] = mean
            var s = 0.0
            for (x in bins) s += (x.energy - mean).pow(2) * x.total
            v["variance"] = s / t
        }
        for ((i, x) in bins.withIndex()) {
            v["c$i.t"] = x.total; v["c$i.p"] = x.photopeak; v["c$i.c"] = x.compton; v["c$i.e"] = x.escape; v["c$i.b"] = x.background
        }
        return v
    }

    private fun setups(): Map<String, SpectrumSetup> {
        val mylar = target("compound|Plastics / Polymers/Mylar (ICRU-222)")
        val s1 = SpectrumSetup(
            lines = listOf(SpectrumLine(energy = 1000.0, counts = 10000.0), SpectrumLine(energy = 1332.5, counts = 5000.0),
                SpectrumLine(energy = 6128.63, counts = 20000.0, dopplerHalfWidth = 25.0),
                SpectrumLine(energy = 300.0, counts = 100000.0, enabled = false),
                SpectrumLine(energy = 4438.94, counts = 8000.0, dopplerHalfWidth = 40.0)),
            foils = listOf(DetectorFoil(StoppingTarget.element(13), 1e6), DetectorFoil(mylar, 5e5, 30.0)),
            maximumEnergy = 8000.0, channels = 4096, continuumRatio = 2.0, background = 0.5,
            escape = EscapeModel(annihilation = 0.3),
        )
        val s2 = s1.copy(escape = s1.escape.usingTypical(DetectorCrystal.BGO), maximumEnergy = 7000.0, channels = 1024,
            continuumRatio = 1.2, background = 0.0, foils = emptyList())
        var s3 = SpectrumSetup(
            backgrounds = BackgroundLibrary.all.mapIndexed { i, s -> BackgroundEntry(s.id, 1000 + 10 * i.toDouble()) },
            geometry = GammaGeometry(angle = 90.0, halfOpening = 10.0),
            maximumEnergy = 8000.0, channels = 2048, continuumRatio = 1.5, escape = EscapeModel().usingTypical(DetectorCrystal.LABR3),
        )
        s3 = s3.copy(lines = s3.backgroundLines(400.0))
        val s4 = SpectrumSetup(lines = listOf(SpectrumLine(energy = 661.657, counts = 1000.0)), maximumEnergy = 2000.0,
            channels = 128, continuumRatio = 0.0, background = 1.25)
        val s5 = SpectrumSetup(lines = listOf(SpectrumLine(energy = 121.78, counts = 6000.0),
            SpectrumLine(energy = 1173.228, counts = 2000.0), SpectrumLine(energy = 2614.511, counts = 1500.0)),
            continuumRatio = 0.0, escape = EscapeModel(enabled = false))
        return mapOf("s1" to s1, "s2" to s2, "s3" to s3, "s4" to s4, "s5" to s5)
    }

    private fun resolution(name: String) = when (name) {
        "hpge" -> ResolutionModel.presets[0].model
        "nai" -> ResolutionModel.presets.first { it.name.startsWith("NaI") }.model
        "labr" -> ResolutionModel.presets.first { it.name.startsWith("LaBr") }.model
        else -> fail(name)
    }

    private fun spectrum(inputs: JsonObject, expected: JsonObject) {
        fun inp(k: String) = inputs[k]!!.jsonPrimitive.content
        val id = inp("setup")
        val setup = setups().getValue(id)
        val bins = GammaSpectrum.simulate(setup, resolution(inp("resolution")))
        val v = HashMap(summarize(bins))
        val w = bins[1].energy - bins[0].energy
        listOf(990.0 to 1010.0, 5600.0 to 5640.0, 0.0 to 8000.0, 500.3 to 521.7, 4300.0 to 4600.0).forEachIndexed { i, (lo, hi) ->
            val r = SpectrumRegion.integrate(bins, w, lo, hi)
            v["roi$i.p"] = r.photopeak; v["roi$i.c"] = r.compton; v["roi$i.b"] = r.background; v["roi$i.e"] = r.escape
        }
        if (id == "s5") {
            assertEquals(inp("envelope"), SpectrumPlotSampling.envelope(bins, 400).joinToString(",") { it.id.toString() })
        }
        if (id == "s4") {
            val want = inp("csv").split("\n")
            val got = GammaSpectrum.csv(bins).split("\n")
            assertEquals(want.size, got.size)
            assertEquals(want[0], got[0])
            for (k in 1 until want.size) {
                val a = want[k].split(","); val g = got[k].split(",")
                assertEquals(a[0], g[0], "csv energy"); assertEquals(a[4], g[4], "csv background")
                for (j in a.indices) assertTrue(abs(a[j].toDouble() - g[j].toDouble()) <= 1e-9 * max(1.0, abs(a[j].toDouble())), "csv $k,$j")
            }
        }
        if (id == "s3") {
            assertEquals(inp("lines"), setup.lines.joinToString("|") { it.name })
            setup.lines.forEachIndexed { i, l -> v["line$i.e"] = l.energy; v["line$i.n"] = l.counts; v["line$i.h"] = l.dopplerHalfWidth }
        }
        // Swift stores only channels above 1e-6 of the maximum (tails depend on the libm's last bits).
        val channelKeys = expected.keys.filter { it.startsWith("c") && it[1].isDigit() }
        assertTrue(channelKeys.size > 20, "$id: too few channels stored")
        check("spectrum $id", expected, v, exactKeys = false)
        assertEquals(expected.keys.count { !(it.startsWith("c") && it[1].isDigit()) },
            v.keys.count { !(it.startsWith("c") && it[1].isDigit()) }, "$id: summary keys")
    }

    // In-beam

    private fun geometry(inputs: JsonObject): GammaGeometry {
        fun inp(k: String) = inputs[k]!!.jsonPrimitive.content
        return GammaGeometry(inp("angle").toDouble(), inp("open").toDouble(), inp("stop") == "1", inp("tstop").toDouble())
    }

    private fun lineValues(l: InBeamLine, p: String, v: MutableMap<String, Double>) {
        v[p + "rest"] = l.restEnergy; v[p + "shift"] = l.shiftedEnergy; v[p + "half"] = l.halfWidth
        v[p + "frac"] = l.fractionInFlight; v[p + "int"] = l.intensity; v[p + "mean"] = l.meanEnergy
    }

    private fun sameId(want: String, got: String) {
        assertEquals(want.substringBeforeLast("-"), got.substringBeforeLast("-"))
        assertTrue(close(want.substringAfterLast("-").toDouble(), got.substringAfterLast("-").toDouble()), "id $want / $got")
    }

    // Cascades

    private val toy = LevelScheme(
        listOf(Level(0, 0.0, null, "0+", "STABLE", null), Level(1, 1000.0, null, "2+", "", null),
            Level(2, 2000.0, null, "4+", "", null), Level(3, 3000.0, null, "2+", "", null)),
        listOf(GammaTransition(3000.0, 0.0, "2+", "0+", 3000.0, null, 25.0, "E2"),
            GammaTransition(3000.0, 1000.0, "2+", "2+", 2000.0, null, 75.0, "M1"),
            GammaTransition(1000.0, 0.0, "2+", "0+", 1000.0, null, 100.0, "E2")),
        "test", 0.0)

    private val schemes: Map<String, LevelScheme> by lazy {
        val missing = toy.copy(gammas = toy.gammas + listOf(GammaTransition(3000.0, 1500.0, "2+", "", 1500.0, null, 100.0, ""),
            GammaTransition(3000.0, 500.0, "2+", "", 2500.0, null, null, "")))
        val equal = toy.copy(gammas = toy.gammas.map { GammaTransition(it.initialLevel, it.finalLevel, "", "", it.energy, null, null, "") } +
            GammaTransition(2000.0, 1000.0, "", "", 1000.0, null, 0.0, ""))
        mapOf("toy" to toy, "missing" to missing, "equal" to equal, "28Si" to silicon)
    }
    private val silicon: LevelScheme by lazy {
        LiveChartClient.parse(File(fixtures, "livechart_28si_levels.csv").readText(), File(fixtures, "livechart_28si_gammas.csv").readText(), 0.0)
    }

    private fun cascade(r: GammaCascade.Result, taus: Map<Double, Double>, v: MutableMap<String, Double>): String {
        v["n"] = r.lines.size.toDouble(); v["unresolved"] = r.unresolved; v["without"] = r.withoutIntensity.toDouble()
        r.startLevel?.let { v["start"] = it }
        r.lines.forEachIndexed { i, l -> v["e$i"] = l.energy; v["i$i"] = l.intensity; v["from$i"] = l.initialLevel; v["to$i"] = l.finalLevel }
        val times = GammaCascade.meanDecayTimes(r.lines) { taus[it] }
        val keys = times.keys.sortedDescending()
        keys.forEachIndexed { i, k -> v["t$i"] = times.getValue(k) }
        return keys.joinToString(",") { it.toString() }
    }

    // Measured spectra

    private fun synthetic(lines: List<Pair<Double, Double>>, channels: Int = 8192, gain: Double = 0.5, offset: Double = 2.0, seed: ULong = 7uL): List<Double> {
        var state = seed
        fun uniform(): Double {
            state = state * 6364136223846793005uL + 1442695040888963407uL
            return ((state shr 11).toLong().toDouble() + 0.5) / (1L shl 53).toDouble()
        }
        fun poisson(mean: Double): Double {
            if (!(mean > 0)) return 0.0
            val z = sqrt(-2 * ln(uniform())) * cos(2 * PI * uniform())
            val x = mean + z * sqrt(mean)
            val t = truncate(x)
            val r = if (abs(x - t) == 0.5) t + sign(x) else round(x)
            return max(0.0, r)
        }
        return (0 until channels).map { ch ->
            val e = offset + gain * ch
            var mean = 200 * exp(-e / 800) + 5
            for ((energy, area) in lines) {
                val s = sqrt(1 + 0.002 * energy) / 2.3548 / gain
                val x = (ch - (energy - offset) / gain) / s
                mean += area / (s * sqrt(2 * PI)) * exp(-0.5 * x * x)
            }
            poisson(mean)
        }
    }

    private val europiumCobalt = listOf(121.78 to 60000.0, 244.70 to 15000.0, 344.28 to 40000.0, 778.90 to 12000.0, 964.08 to 12000.0,
        1085.84 to 8000.0, 1112.08 to 11000.0, 1408.01 to 16000.0, 1173.228 to 20000.0, 1332.492 to 20000.0)
    private val spectra: Map<String, List<Double>> by lazy {
        val eu = synthetic(europiumCobalt)
        mapOf("cobalt" to synthetic(listOf(1173.228 to 20000.0, 1332.492 to 20000.0)), "eu" to eu, "eu-default" to eu,
            "eu2" to synthetic(europiumCobalt, 4096, 0.75, -5.0, 13uL), "eu-wide" to eu)
    }

    private fun peakValues(peaks: List<FoundPeak>, v: MutableMap<String, Double>) {
        v["peaks"] = peaks.size.toDouble()
        peaks.forEachIndexed { i, p ->
            v["p$i.c"] = p.centroid; v["p$i.dc"] = p.centroidUncertainty; v["p$i.w"] = p.fwhm
            v["p$i.a"] = p.area; v["p$i.da"] = p.areaUncertainty; v["p$i.s"] = p.significance
        }
    }

    private fun hex(s: String) = ByteArray(s.length / 2) { s.substring(2 * it, 2 * it + 2).toInt(16).toByte() }

    @Test fun reproducesEverySwiftCase() {
        val counts = HashMap<String, Int>()
        val refLines = AutoCalibration.lines(listOf(CalibrationSources.source("152Eu")!!, CalibrationSources.source("60Co")!!))
        for (c in cases) {
            val o = c.jsonObject
            val name = o["name"]!!.jsonPrimitive.content
            counts[name] = (counts[name] ?: 0) + 1
            val inputs = o["inputs"]!!.jsonObject
            fun inp(k: String) = inputs[k]!!.jsonPrimitive.content
            val expected = o["values"]!!.jsonObject
            val label = "$name $inputs"
            if (name == "spectrum") { spectrum(inputs, expected); continue }
            val v = HashMap<String, Double>()
            when (name) {
                "attenuation" -> nums(inp("energies")).forEachIndexed { i, e -> v["mu$i"] = PhotonAttenuation.massCoefficient(inp("z").toInt(), e) }
                "attenuation-error" -> v["error"] = attempt { PhotonAttenuation.massCoefficient(inp("z").toInt(), inp("energy").toDouble()) }
                "foil" -> {
                    val m = target(inp("material"))
                    val es = nums(inp("energies"))
                    es.forEachIndexed { i, e -> v["mu$i"] = PhotonAttenuation.massCoefficient(m, e) }
                    listOf(1e5 to 0.0, 1e6 to 30.0, 5e6 to 60.0, 0.0 to 0.0, 2e7 to 89.0).forEachIndexed { j, (t, a) ->
                        val f = DetectorFoil(m, t, a)
                        es.forEachIndexed { i, e -> v["T$j.$i"] = f.transmission(e) }
                    }
                }
                "foil-error" -> {
                    val f = when (inp("foil")) {
                        "angle90" -> DetectorFoil(angle = 90.0); "negative" -> DetectorFoil(thickness = -1.0)
                        else -> DetectorFoil(thickness = Double.NaN)
                    }
                    v["error"] = attempt { f.transmission(1000.0) }
                }
                "spectrum-error" -> {
                    val s4 = setups().getValue("s4")
                    val s = when (inp("setup")) {
                        "nan" -> s4.copy(lines = listOf(s4.lines[0].copy(energy = Double.NaN)))
                        "foil90" -> s4.copy(foils = listOf(DetectorFoil(angle = 90.0)))
                        "channels0" -> s4.copy(channels = 0)
                        else -> s4.copy(escape = s4.escape.copy(annihilation = 30.0))
                    }
                    v["error"] = attempt { GammaSpectrum.simulate(s, ResolutionModel.presets[0].model) }
                }
                "pair" -> {
                    val crystal = DetectorCrystal.entries.first { it.id == inp("crystal") }
                    assertEquals(inp("name"), crystal.displayName)
                    v["typS"] = crystal.typicalEscape.first; v["typD"] = crystal.typicalEscape.second
                    val typical = EscapeModel().usingTypical(crystal)
                    val custom = EscapeModel(crystal = crystal, singleAtReference = 15.0, doubleAtReference = 30.0)
                    val off = typical.copy(enabled = false)
                    nums(inp("energies")).forEachIndexed { i, e ->
                        v["f$i"] = PairProduction.fraction(crystal, e)
                        val r = typical.ratios(e); val cu = custom.ratios(e); val of = off.ratios(e)
                        v["s$i"] = r.first; v["d$i"] = r.second; v["cs$i"] = cu.first; v["cd$i"] = cu.second
                        v["os$i"] = of.first; v["od$i"] = of.second
                    }
                }
                "crystal-match" -> {
                    val names = inp("names").split("|")
                    assertEquals(ResolutionModel.presets.map { it.name }, names.take(ResolutionModel.presets.size))
                    assertEquals(inp("crystals"), names.joinToString("|") { DetectorCrystal.matching(it)?.id ?: "none" })
                    v["n"] = names.size.toDouble()
                }
                "resolution" -> {
                    val i = inp("index").toInt()
                    val m = when {
                        i < ResolutionModel.presets.size -> ResolutionModel.presets[i].also { assertEquals(inp("name"), it.name) }.model
                        inp("name") == "custom" -> ResolutionModel(ResolutionModel.Kind.SEMICONDUCTOR, noise = 2.0, fano = 0.13, pairEnergy = 3e-3, collection = 1e-3)
                        else -> ResolutionModel(ResolutionModel.Kind.SCINTILLATOR, resolutionAt662 = 0.035)
                    }
                    nums(inp("energies")).forEachIndexed { j, e -> v["fwhm$j"] = m.fwhm(e) }
                }
                "efficiency" -> {
                    val ex = EfficiencyCurve.example
                    val id = inp("curve")
                    val curve = when {
                        id.startsWith("example-") -> ex.copy(order = id.removePrefix("example-").toInt())
                        id == "weighted" -> ex.copy(points = ex.points.mapIndexed { i, p -> p.copy(relativeUncertainty = 0.01 + 0.005 * i) })
                        id == "few" -> EfficiencyCurve(ex.points.take(3), 3)
                        else -> EfficiencyCurve(ex.points + listOf(EfficiencyCurve.Point(-5.0, 0.1), EfficiencyCurve.Point(500.0, 0.0),
                            EfficiencyCurve.Point(800.0, 0.0065, 0.0)), 2)
                    }
                    val fit = curve.fit()
                    if (fit == null) v["nil"] = 1.0 else {
                        fit.coefficients.forEachIndexed { i, x -> v["a$i"] = x }
                        v["chi2"] = fit.chiSquared; v["dof"] = fit.degreesOfFreedom.toDouble()
                        fit.reducedChiSquared?.let { v["reduced"] = it }
                        nums(inp("energies")).forEachIndexed { i, e -> v["eff$i"] = fit.efficiency(e) }
                    }
                }
                "solve" -> if (inp("system") == "3x3") {
                    val x = EfficiencyCurve.solve(listOf(listOf(4.0, -2.0, 1.0), listOf(-2.0, 4.0, -2.0), listOf(1.0, -2.0, 3.0)), listOf(11.0, -16.0, 17.0))!!
                    v["x0"] = x[0]; v["x1"] = x[1]; v["x2"] = x[2]
                } else v["nil"] = b(EfficiencyCurve.solve(listOf(listOf(1.0, 2.0), listOf(2.0, 4.0)), listOf(1.0, 2.0)) == null)
                "doppler" -> {
                    listOf(1.0 to 0.0, 0.01 to 10.0, 2.5 to 5.0, 4.0 to 1.0).forEachIndexed { i, (r, d) ->
                        v["omega$i"] = Geometry.diskSolidAngle(r, d); v["half$i"] = Geometry.halfOpeningAngle(r, d)
                    }
                    listOf(listOf(1000.0, 0.01, 0.0, 0.2), listOf(6128.63, 0.006, 0.96, 0.17), listOf(4438.94, 0.03, 2.4, 0.5),
                        listOf(511.0, 0.002, PI / 2, 0.0)).forEachIndexed { i, (e0, beta, th, op) ->
                        v["E$i"] = GammaDoppler.energy(e0, beta, th)
                        val r = GammaDoppler.range(e0, beta, th, op)
                        v["lo$i"] = r.start; v["hi$i"] = r.endInclusive
                        v["mean$i"] = GammaDoppler.meanOverCone(e0, beta, th, op)
                        v["mean20_$i"] = GammaDoppler.meanOverCone(e0, beta, th, op, 20)
                    }
                    v["recoil"] = GammaDoppler.recoilCorrected(1779.0, 28 * 931494.0)
                }
                "primary" -> {
                    val l = InBeamGamma.primary(Reaction.parse(inp("reaction")), inp("beam").toDouble(), inp("final").toDouble(), geometry(inputs))
                    if (l == null) v["nil"] = 1.0 else { lineValues(l, "", v); assertEquals(inp("label"), l.label) }
                }
                "level" -> {
                    val l = InBeamGamma.residualLevel(Reaction.parse(inp("reaction")), inp("beam").toDouble(), inp("level").toDouble(),
                        inp("transition").toDoubleOrNull(), inp("final").toDouble(), inp("tau").toDoubleOrNull(), inp("intensity").toDouble(),
                        geometry(inputs), inp("custom").ifEmpty { null })
                    if (l == null) v["nil"] = 1.0 else {
                        lineValues(l, "", v); assertEquals(inp("label"), l.label)
                        val sl = l.spectrumLines(1000.0)
                        v["nsl"] = sl.size.toDouble()
                        sl.forEachIndexed { i, s -> v["sl$i.e"] = s.energy; v["sl$i.n"] = s.counts; v["sl$i.h"] = s.dopplerHalfWidth }
                        assertEquals(inp("slnames"), sl.joinToString("|") { it.name })
                    }
                }
                "background" -> {
                    val source = BackgroundLibrary.source(inp("source"))!!
                    val e = inp("beam").toDouble()
                    val lines = source.lines(e, geometry(inputs))
                    val table = MassTable.ame2020
                    v["n"] = lines.size.toDouble()
                    v["appliesP"] = b(source.applies(table.nuclide("p")!!, e)); v["appliesA"] = b(source.applies(table.nuclide("a")!!, e))
                    lines.forEachIndexed { i, l -> lineValues(l, "l$i.", v) }
                    assertEquals(inp("labels"), lines.joinToString("|") { it.label })
                    val ids = inp("ids").split("|")
                    if (lines.isNotEmpty()) lines.forEachIndexed { i, l -> sameId(ids[i], l.id) }
                }
                "background-lines" -> {
                    val setup = SpectrumSetup(
                        backgrounds = BackgroundLibrary.all.mapIndexed { i, s -> BackgroundEntry(s.id, 1000 + 10 * i.toDouble(), i != 3) } +
                            BackgroundEntry("unknown"),
                        geometry = GammaGeometry(angle = 120.0))
                    val lines = setup.backgroundLines(inp("beam").toDouble())
                    v["n"] = lines.size.toDouble()
                    lines.forEachIndexed { i, l -> v["l$i.e"] = l.energy; v["l$i.n"] = l.counts; v["l$i.h"] = l.dopplerHalfWidth }
                    assertEquals(inp("names"), lines.joinToString("|") { it.name })
                }
                "particle" -> {
                    val mylar = target("compound|Plastics / Polymers/Mylar (ICRU-222)")
                    val al15 = DetectorFoil(StoppingTarget.element(13), 1.5e5)
                    val s = when (inp("case")) {
                        "li-noelastic" -> ParticleDetectorSetup(showElastic = false)
                        "li-al" -> ParticleDetectorSetup(foils = listOf(al15))
                        "li-two-foils" -> ParticleDetectorSetup(angle = 150.0, foils = listOf(DetectorFoil(mylar, 2e4, 20.0),
                            DetectorFoil(StoppingTarget.element(13), 0.0), al15))
                        "cu-2" -> ParticleDetectorSetup(resolution = 2.0)
                        "ta2o5" -> ParticleDetectorSetup(angle = 160.0, foils = listOf(DetectorFoil(mylar, 1e4)))
                        "ta2o5-thick" -> ParticleDetectorSetup(angle = 160.0, foils = listOf(DetectorFoil(mylar, 1e6)))
                        "c13-mix" -> ParticleDetectorSetup(angle = 150.0, resolution = 1.0, halfOpening = 0.0)
                        "au" -> ParticleDetectorSetup(angle = 170.0)
                        "heavy-on-h" -> ParticleDetectorSetup(angle = 3.0, halfOpening = 0.0)
                        "neutron" -> ParticleDetectorSetup(angle = 30.0, foils = listOf(al15))
                        "inelastic" -> ParticleDetectorSetup(angle = 90.0)
                        "mylar-target" -> ParticleDetectorSetup(angle = 120.0)
                        "bad-angle" -> ParticleDetectorSetup(angle = 180.0)
                        else -> ParticleDetectorSetup()
                    }
                    val groups = ParticleSpectrum.groups(Reaction.parse(inp("reaction")), inp("beam").toDouble(), inp("excitation").toDouble(),
                        inp("material").ifEmpty { null }?.let { target(it) }, s)
                    v["n"] = groups.size.toDouble()
                    groups.forEachIndexed { i, g ->
                        v["emitted$i"] = g.emitted; v["fwhm$i"] = g.fwhm; v["neutral$i"] = b(g.neutral)
                        g.detected?.let { v["detected$i"] = it }
                        g.stoppedIn?.let { v["stopped$i"] = it.toDouble() }
                        g.rutherford?.let { v["ruth$i"] = it }
                    }
                    assertEquals(inp("ids"), groups.joinToString("|") { it.id })
                    assertEquals(inp("origins"), groups.joinToString("|") { it.origin })
                    assertEquals(inp("particles"), groups.joinToString("|") { it.particle })
                    assertEquals(inp("kinds"), groups.joinToString("|") { if (it.kind == ParticleGroup.Kind.REACTION) "reaction" else "elastic" })
                }
                "isotopes" -> {
                    val iso = ParticleSpectrum.naturalIsotopes(inp("z").toInt())
                    v["n"] = iso.size.toDouble()
                    iso.forEachIndexed { i, (n, ab) -> v["a$i"] = n.a.toDouble(); v["ab$i"] = ab }
                }
                "cascade" -> {
                    val id = inp("scheme")
                    val scheme = schemes.getValue(id)
                    val taus = if (id == "28Si") silicon.levels.filter { it.halfLifeSeconds != null }
                        .associate { it.energy to it.halfLifeSeconds!! / ln(2.0) }
                    else mapOf(3000.0 to 10e-12, 1000.0 to 50e-15, 2000.0 to 1e-12)
                    val r = GammaCascade.from(inp("excitation").toDouble(), scheme, inputs["tolerance"]?.jsonPrimitive?.content?.toDouble())
                    val keys = cascade(r, taus, v)
                    assertEquals(nums(inp("timeLevels")), nums(keys))
                }
                "livechart" -> {
                    val si = silicon
                    v["levels"] = si.levels.size.toDouble(); v["gammas"] = si.gammas.size.toDouble()
                    si.levels.take(12).forEachIndexed { i, l ->
                        v["E$i"] = l.energy; v["idx$i"] = l.index.toDouble()
                        l.energyUncertainty?.let { v["dE$i"] = it }; l.halfLifeSeconds?.let { v["T$i"] = it }
                    }
                    si.gammas.take(12).forEachIndexed { i, g ->
                        v["g$i"] = g.energy; v["gi$i"] = g.initialLevel; v["gf$i"] = g.finalLevel
                        g.energyUncertainty?.let { v["gu$i"] = it }; g.relativeIntensity?.let { v["gr$i"] = it }
                    }
                    assertEquals(inp("reference"), si.reference)
                    assertEquals(inp("jp"), si.levels.take(12).joinToString("|") { it.spinParity })
                    assertEquals(inp("halfLives"), si.levels.take(12).joinToString("|") { it.halfLife })
                    assertEquals(inp("multipolarities"), si.gammas.take(12).joinToString("|") { it.multipolarity })
                    assertEquals(inp("gjp"), si.gammas.take(12).joinToString("|") { it.initialSpinParity + ">" + it.finalSpinParity })
                }
                "peaks" -> {
                    val counts0 = spectra.getValue(inp("spectrum"))
                    v["sum"] = counts0.sum(); v["channels"] = counts0.size.toDouble()
                    var m = 0.0
                    counts0.forEachIndexed { i, x -> m += i * x }
                    v["moment"] = m
                    peakValues(PeakSearch.find(counts0, inp("fwhm").toDouble(), inp("threshold").toDouble()), v)
                }
                "snip" -> {
                    val bg = PeakSearch.snipBackground(spectra.getValue("eu"), inp("iterations").toInt())
                    v["sum"] = bg.sum()
                    for (ch in listOf(0, 3, 100, 240, 500, 1000, 2660, 4000, 8000, 8191)) v["c$ch"] = bg[ch]
                }
                "peaks-short" -> {
                    v["flat17"] = PeakSearch.find(List(17) { 5.0 }, 6.0).size.toDouble()
                    v["wide"] = PeakSearch.find(List(1024) { 5.0 }, 500.0).size.toDouble()
                    v["snip2"] = PeakSearch.snipBackground(listOf(3.0, 4.0), 5).sum()
                }
                "calibration-lines" -> {
                    v["n"] = refLines.size.toDouble()
                    refLines.forEachIndexed { i, l -> v["e$i"] = l.energy; v["w$i"] = l.weight }
                    assertEquals(inp("labels"), refLines.joinToString("|") { it.label })
                    assertEquals(inp("ids"), refLines.joinToString("|") { it.id })
                }
                "autocal" -> {
                    val eu = PeakSearch.find(spectra.getValue("eu"), 4.0, 5.0)
                    val (peaks, quad, range, off, tol) = when (inp("variant")) {
                        "linear" -> listOf(eu, false, 0.01..100.0, 100.0, null)
                        "quadratic" -> listOf(eu, true, 0.01..100.0, 100.0, null)
                        "tolerance" -> listOf(eu, false, 0.01..100.0, 100.0, 1.5)
                        "narrow" -> listOf(eu, false, 0.4..0.6, 10.0, null)
                        "eu2" -> listOf(PeakSearch.find(spectra.getValue("eu2"), 3.0, 5.0), false, 0.01..100.0, 100.0, null)
                        "excluded" -> listOf(eu, false, 1.0..2.0, 100.0, null)
                        else -> listOf(eu.take(1), false, 0.01..100.0, 100.0, null)
                    }
                    @Suppress("UNCHECKED_CAST")
                    val r = AutoCalibration.calibrate(peaks as List<FoundPeak>, refLines, quad as Boolean,
                        range as ClosedFloatingPointRange<Double>, off as Double, tol as Double?)
                    if (r == null) v["nil"] = 1.0 else {
                        r.calibration.coefficients.forEachIndexed { i, x -> v["k$i"] = x }
                        v["gain"] = r.calibration.gain; v["rms"] = r.rms; v["matches"] = r.matches.size.toDouble()
                        r.matches.forEachIndexed { i, mt ->
                            v["m$i.line"] = mt.line.energy; v["m$i.peak"] = mt.peak.centroid; v["m$i.fit"] = mt.fitted; v["m$i.res"] = mt.residual
                        }
                    }
                }
                "calibration" -> {
                    val cal = EnergyCalibration(listOf(1.5, 0.4, 2e-6))
                    listOf(0.0, 100.0, 1332.492, 3000.0, 10000.0).forEachIndexed { i, e ->
                        v["ch$i"] = cal.channel(e); v["lin$i"] = EnergyCalibration(listOf(-3.0, 0.25)).channel(e)
                        v["flat$i"] = EnergyCalibration(listOf(5.0)).channel(e)
                    }
                    listOf(0.0, 1.0, 2500.5, 8191.0).forEachIndexed { i, ch -> v["E$i"] = cal.energy(ch) }
                    val pts = listOf(100.0, 1000.0, 2500.0, 4000.0, 6000.0).map { Triple(it, cal.energy(it) + 0.01 * sin(it), 0.1 + it / 1e5) }
                    for (order in 1..3) AutoCalibration.fit(pts, order)?.forEachIndexed { i, x -> v["fit$order.$i"] = x }
                    v["fitNil"] = b(AutoCalibration.fit(pts.take(2), 2) == null)
                }
                "parse" -> {
                    val data = inputs["hex"]?.let { hex(it.jsonPrimitive.content) } ?: inp("text").encodeToByteArray()
                    try {
                        val s = MeasuredSpectrum.read(data, inp("name"))
                        v["n"] = s.counts.size.toDouble()
                        s.counts.take(12).forEachIndexed { i, x -> v["c$i"] = x }
                        s.liveTime?.let { v["live"] = it }; s.realTime?.let { v["real"] = it }
                        s.fileCalibration?.coefficients?.forEachIndexed { i, x -> v["k$i"] = x }
                    } catch (e: SpectrumImportException) {
                        v["error"] = if (e.kind == SpectrumImportException.Kind.EMPTY) 1.0 else 2.0
                    }
                }
                else -> fail("unknown case $name")
            }
            check(label, expected, v)
        }
        assertEquals(cases.size, counts.values.sum())
        assertTrue(checked > 10000, "checked $checked values")
        println("ReferenceSpectraTest: ${cases.size} cases, $checked values, $counts")
    }

    @Test fun liveChartClientUsesCacheAndFetch() {
        val dir = kotlin.io.path.createTempDirectory("livechart").toFile()
        try {
            val levels = File(fixtures, "livechart_28si_levels.csv").readText()
            val gammas = File(fixtures, "livechart_28si_gammas.csv").readText()
            var calls = 0
            val client = LiveChartClient(dir.path) { url ->
                calls++
                assertTrue("nuclides=28si" in url)
                org.gamow.core.exfor.HttpResponse(200, (if ("fields=levels" in url) levels else gammas).encodeToByteArray())
            }
            val s = kotlinx.coroutines.runBlocking { client.levelScheme(14, 28) }
            assertEquals(2, calls)
            assertEquals(silicon.levels, s.levels)
            assertEquals(silicon.gammas, s.gammas)
            kotlinx.coroutines.runBlocking { client.levelScheme(14, 28) }
            assertEquals(2, calls)                                       // fresh cache: no network
            assertEquals(silicon.levels, client.cached(14, 28)!!.levels)
            val failing = LiveChartClient(dir.path) { throw org.gamow.core.exfor.ExforClient.Failure.Offline() }
            assertEquals(silicon.levels, kotlinx.coroutines.runBlocking { failing.levelScheme(14, 28, forceRefresh = true) }.levels)
            assertFailsWith<LiveChartClient.Failure.Offline> { kotlinx.coroutines.runBlocking { failing.levelScheme(6, 12) } }
        } finally {
            dir.deleteRecursively()
        }
    }
}
