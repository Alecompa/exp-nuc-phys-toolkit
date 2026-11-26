import Foundation

// MARK: - Import

/// A measured histogram: counts per channel, with an optional energy calibration.
public struct MeasuredSpectrum: Hashable, Sendable {
    public var name: String
    public var counts: [Double]
    public var liveTime: Double?
    public var realTime: Double?
    /// Calibration found in the file (ORTEC $ENER_FIT / $MCA_CAL), if any.
    public var fileCalibration: EnergyCalibration?

    public init(name: String, counts: [Double], liveTime: Double? = nil, realTime: Double? = nil,
                fileCalibration: EnergyCalibration? = nil) {
        self.name = name; self.counts = counts; self.liveTime = liveTime; self.realTime = realTime
        self.fileCalibration = fileCalibration
    }

    public enum ImportError: Error, LocalizedError, Equatable {
        case empty, unreadable(String)
        public var errorDescription: String? {
            switch self {
            case .empty: "The file has no channel data."
            case .unreadable(let why): "Could not read the spectrum: \(why)."
            }
        }
    }

    /// Reads ORTEC .Spe (text) and .Chn (binary), or plain text: one column of counts, or two columns
    /// (channel or energy, counts) separated by commas, semicolons, tabs or spaces. Lines starting with #
    /// and non-numeric headers are skipped. A two-column file whose first column is not 0, 1, 2… is taken as
    /// calibrated energies (keV) and gives a linear calibration from its first and last rows.
    public static func read(_ data: Data, name: String) throws -> MeasuredSpectrum {
        if name.lowercased().hasSuffix(".chn") { return try chn(data, name: name) }
        guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unreadable("not a text file")
        }
        // Windows line endings (files from DAQ PCs): "\r\n" would otherwise split into an extra empty line.
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.contains("$DATA:") { return try spe(text, name: name) }
        return try columns(text, name: name)
    }

    static func spe(_ text: String, name: String) throws -> MeasuredSpectrum {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var counts: [Double] = []
        var live: Double?, real: Double?
        var cal: EnergyCalibration?
        var i = 0
        while i < lines.count {
            switch lines[i] {
            case "$MEAS_TIM:":
                let t = lines[safe: i + 1]?.split(separator: " ").compactMap { Double($0) } ?? []
                if t.count >= 2 { live = t[0]; real = t[1] }
                i += 2
            case "$DATA:":
                let range = lines[safe: i + 1]?.split(separator: " ").compactMap { Int($0) } ?? []
                guard range.count >= 2, range[1] >= range[0] else { throw ImportError.unreadable("bad $DATA range") }
                let n = range[1] - range[0] + 1
                counts = (0..<n).compactMap { lines[safe: i + 2 + $0].flatMap { Double($0) } }
                i += 2 + n
            case "$ENER_FIT:", "$MCA_CAL:":
                let isFit = lines[i] == "$ENER_FIT:"
                var row = lines[safe: i + 1] ?? ""
                if !isFit { row = lines[safe: i + 2] ?? "" }      // $MCA_CAL: first line is the number of terms
                let c = row.split(separator: " ").compactMap { Double($0) }
                if c.count >= 2, c[1] != 0, cal == nil { cal = EnergyCalibration(coefficients: Array(c.prefix(3))) }
                i += isFit ? 2 : 3
            default:
                i += 1
            }
        }
        guard !counts.isEmpty else { throw ImportError.empty }
        return MeasuredSpectrum(name: name, counts: counts, liveTime: live, realTime: real, fileCalibration: cal)
    }

    /// ORTEC .Chn: 32-byte header (type −1, live and real time in 20 ms ticks, start channel, length),
    /// then 32-bit channel contents.
    static func chn(_ data: Data, name: String) throws -> MeasuredSpectrum {
        guard data.count > 32 else { throw ImportError.unreadable("file too short for .Chn") }
        let bytes = [UInt8](data)
        func i16(_ o: Int) -> Int { Int(Int16(bitPattern: UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8)) }
        func u32(_ o: Int) -> UInt32 {
            UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24
        }
        guard i16(0) == -1 else { throw ImportError.unreadable("not an ORTEC .Chn file") }
        let real = Double(u32(8)) * 0.02, live = Double(u32(12)) * 0.02
        let n = Int(UInt16(bytes[30]) | UInt16(bytes[31]) << 8)
        guard n > 0, data.count >= 32 + 4 * n else { throw ImportError.unreadable("channel count does not match the file size") }
        let counts = (0..<n).map { Double(u32(32 + 4 * $0)) }
        return MeasuredSpectrum(name: name, counts: counts, liveTime: live, realTime: real)
    }

    static func columns(_ text: String, name: String) throws -> MeasuredSpectrum {
        var rows: [[Double]] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let tokens = line.split(whereSeparator: { ",;\t ".contains($0) })
            let fields = tokens.compactMap { Double($0) }
            // Header or comment lines ("Live time: 100") have a non-numeric token: skip them whole.
            guard !fields.isEmpty, fields.count == tokens.count else { continue }
            rows.append(fields)
        }
        guard !rows.isEmpty else { throw ImportError.empty }
        // The most common row width is the data layout.
        let widths = Dictionary(grouping: rows.map(\.count), by: { $0 }).mapValues(\.count)
        let width = widths.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? 1
        rows = rows.filter { $0.count >= width }
        if width == 1 { return MeasuredSpectrum(name: name, counts: rows.map { $0[0] }) }
        // Energies may be listed high to low; store channels in increasing energy.
        if rows.count > 1, rows[0][0] > rows[rows.count - 1][0] { rows.reverse() }
        let x = rows.map { $0[0] }, y = rows.map { $0[1] }
        let isChannels = x.enumerated().allSatisfy { abs($0.element - Double($0.offset) - x[0]) < 1e-9 }
        if isChannels {
            // Channel numbers may start at 0 or 1; pad so that index = channel.
            let start = max(0, Int(x[0]))
            return MeasuredSpectrum(name: name, counts: [Double](repeating: 0, count: start) + y)
        }
        var cal: EnergyCalibration?
        if let first = x.first, let last = x.last, x.count > 1, last != first {
            let gain = (last - first) / Double(x.count - 1)
            cal = EnergyCalibration(coefficients: [first, gain])
        }
        return MeasuredSpectrum(name: name, counts: y, fileCalibration: cal)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Calibration

/// E(ch) = c₀ + c₁ ch + c₂ ch², keV.
public struct EnergyCalibration: Hashable, Codable, Sendable {
    public var coefficients: [Double]
    public init(coefficients: [Double]) { self.coefficients = coefficients }

    public func energy(channel c: Double) -> Double {
        coefficients.enumerated().reduce(0) { $0 + $1.element * pow(c, Double($1.offset)) }
    }

    /// Channel for an energy (inverse; Newton from the linear guess).
    public func channel(energy e: Double) -> Double {
        let c0 = coefficients[safe: 0] ?? 0, c1 = coefficients[safe: 1] ?? 1
        var ch = (e - c0) / c1
        for _ in 0..<8 {
            let slope = (1...max(1, coefficients.count - 1)).reduce(0) { s, k in
                s + Double(k) * (coefficients[safe: k] ?? 0) * pow(ch, Double(k - 1))
            }
            guard slope != 0 else { break }
            ch -= (energy(channel: ch) - e) / slope
        }
        return ch
    }

    public var gain: Double { coefficients[safe: 1] ?? 1 }
}

// MARK: - Peak search

public struct FoundPeak: Identifiable, Hashable, Sendable {
    public var id: Int { Int((centroid * 100).rounded()) }
    /// Channel (fractional), with its statistical uncertainty.
    public let centroid: Double
    public let centroidUncertainty: Double
    /// FWHM, channels.
    public let fwhm: Double
    /// Net area above the SNIP background, counts.
    public let area: Double
    public let areaUncertainty: Double
    /// Significance of the second-derivative response.
    public let significance: Double
}

public enum PeakSearch {
    /// SNIP background (Morháč) on the LLS-transformed spectrum, clipping window up to `iterations` channels.
    public static func snipBackground(_ counts: [Double], iterations: Int) -> [Double] {
        let n = counts.count
        guard n > 2, iterations > 0 else { return counts }
        var v = counts.map { log(log((max(0, $0) + 1).squareRoot() + 1) + 1) }   // LLS: ln(ln(√(y+1)+1)+1)
        var w = v
        for p in stride(from: min(iterations, n / 2), through: 1, by: -1) {
            for i in p..<(n - p) { w[i] = min(v[i], 0.5 * (v[i - p] + v[i + p])) }
            v = w
        }
        return v.map { let a = exp(exp($0) - 1) - 1; return max(0, a * a - 1) }
    }

    /// Peaks of `counts` with a smoothed second-derivative filter matched to `fwhm` channels (Mariscotti).
    /// The zero-sum kernel cancels a linearly varying background; candidates above `threshold` standard
    /// deviations are refined with moments of the net counts above the SNIP background.
    public static func find(_ counts: [Double], fwhm: Double, threshold: Double = 4) -> [FoundPeak] {
        let n = counts.count
        guard n > 16, fwhm > 0.5 else { return [] }
        let sigma = fwhm / 2.354_820_045
        let half = max(2, Int(ceil(3 * sigma)))
        guard n >= 2 * half + 3 else { return [] }               // the filter needs room on both sides
        var kernel = (-half...half).map { j -> Double in
            let x = Double(j) / sigma
            return (1 - x * x) * exp(-0.5 * x * x)
        }
        let mean = kernel.reduce(0, +) / Double(kernel.count)
        kernel = kernel.map { $0 - mean }
        var response = [Double](repeating: 0, count: n), sig = response
        for i in half..<(n - half) {
            var r = 0.0, v = 0.0
            for (k, w) in kernel.enumerated() {
                let c = max(0, counts[i + k - half])
                r += w * c; v += w * w * c
            }
            response[i] = r
            sig[i] = v > 0 ? r / v.squareRoot() : 0
        }
        let background = snipBackground(counts, iterations: max(4, Int((2.5 * fwhm).rounded())))
        var peaks: [FoundPeak] = []
        for i in (half + 1)..<(n - half - 1) where sig[i] > threshold && response[i] >= response[i - 1] && response[i] > response[i + 1] {
            // Moments of the net counts within ±1.5 FWHM, re-centred once.
            var centre = Double(i)
            var area = 0.0, m1 = 0.0, m2 = 0.0, variance = 0.0
            for _ in 0..<2 {
                let lo = max(0, Int((centre - 1.5 * fwhm).rounded())), hi = min(n - 1, Int((centre + 1.5 * fwhm).rounded()))
                area = 0; m1 = 0; m2 = 0; variance = 0
                for j in lo...hi {
                    let net = counts[j] - background[j]
                    // A channel the SNIP background leaves unchanged has net ≈ 0 to rounding; skip it deterministically.
                    guard net > 1e-9 * max(counts[j], 1) else { continue }
                    area += net; m1 += net * Double(j); m2 += net * Double(j) * Double(j)
                    variance += max(counts[j], 0) + background[j]
                }
                guard area > 0 else { break }
                centre = m1 / area
            }
            guard area > 0 else { continue }
            let s2 = max(0.25, m2 / area - centre * centre)
            // A second moment truncated at ±1.5 FWHM (±3.53 σ) is 0.994 σ²; undo that.
            let width = 2.354_820_045 * (s2 / 0.994).squareRoot()
            peaks.append(FoundPeak(centroid: centre, centroidUncertainty: (s2 / area).squareRoot(), fwhm: width,
                                   area: area, areaUncertainty: variance.squareRoot(), significance: sig[i]))
        }
        // Merge candidates closer than one FWHM (keep the more significant).
        var merged: [FoundPeak] = []
        for p in peaks.sorted(by: { $0.significance > $1.significance })
        where !merged.contains(where: { abs($0.centroid - p.centroid) < fwhm }) { merged.append(p) }
        return merged.sorted { $0.centroid < $1.centroid }
    }
}

// MARK: - Automatic calibration

public struct CalibrationLine: Hashable, Sendable, Identifiable {
    public let energy: Double
    /// Relative weight for matching (emission intensity × rough efficiency); larger = more important.
    public let weight: Double
    public let label: String
    public var id: String { "\(label)-\(energy)" }
    public init(energy: Double, weight: Double = 1, label: String) {
        self.energy = energy; self.weight = weight; self.label = label
    }
}

public struct CalibrationResult: Sendable {
    public struct Match: Hashable, Sendable, Identifiable {
        public let peak: FoundPeak
        public let line: CalibrationLine
        public let fitted: Double
        public var residual: Double { fitted - line.energy }
        public var id: String { "\(peak.id)-\(line.id)" }
    }
    public let calibration: EnergyCalibration
    public let matches: [Match]
    /// RMS of the residuals, keV.
    public let rms: Double
}

public enum AutoCalibration {
    /// Matches the strongest peaks to the reference lines by voting over (gain, offset) hypotheses from every
    /// pair of peaks and pair of lines, then refines by least squares (quadratic with `quadratic` and ≥ 4
    /// matches). `gainRange` (keV per channel) and `maxOffset` (keV) bound the hypotheses.
    public static func calibrate(peaks: [FoundPeak], lines: [CalibrationLine], quadratic: Bool = false,
                                 gainRange: ClosedRange<Double> = 0.01...100, maxOffset: Double = 100,
                                 tolerance: Double? = nil) -> CalibrationResult? {
        let ps = Array(peaks.sorted { $0.significance > $1.significance }.prefix(20))
        let ls = Array(lines.sorted { $0.weight > $1.weight }.prefix(20))
        guard ps.count >= 2, ls.count >= 2 else { return nil }

        func assign(_ cal: EnergyCalibration, tol: (Double) -> Double) -> [CalibrationResult.Match] {
            var used = Set<Int>()
            var out: [CalibrationResult.Match] = []
            for l in ls.sorted(by: { $0.weight > $1.weight }) {
                let best = ps.enumerated().filter { !used.contains($0.offset) }
                    .map { ($0.offset, $0.element, cal.energy(channel: $0.element.centroid)) }
                    .min { abs($0.2 - l.energy) < abs($1.2 - l.energy) }
                if let (i, p, e) = best, abs(e - l.energy) <= tol(l.energy) {
                    used.insert(i)
                    out.append(.init(peak: p, line: l, fitted: e))
                }
            }
            return out
        }

        var best: (score: Double, rms: Double, cal: EnergyCalibration)?
        for i in 0..<ps.count {
            for j in (i + 1)..<ps.count {
                let (a, b) = ps[i].centroid < ps[j].centroid ? (ps[i], ps[j]) : (ps[j], ps[i])
                guard b.centroid - a.centroid > 1 else { continue }
                for k in 0..<ls.count {
                    for m in (k + 1)..<ls.count {
                        let (la, lb) = ls[k].energy < ls[m].energy ? (ls[k], ls[m]) : (ls[m], ls[k])
                        let gain = (lb.energy - la.energy) / (b.centroid - a.centroid)
                        guard gainRange.contains(gain) else { continue }
                        let offset = la.energy - gain * a.centroid
                        guard abs(offset) <= maxOffset else { continue }
                        let cal = EnergyCalibration(coefficients: [offset, gain])
                        // Tolerance: given, or two FWHM of the peaks in keV with a 1 keV floor.
                        let fw = ps.map(\.fwhm).sorted()[ps.count / 2] * gain
                        let matched = assign(cal) { _ in tolerance ?? max(1, 2 * fw) }
                        guard matched.count >= 2 else { continue }
                        let score = matched.reduce(0) { $0 + $1.line.weight + 1 }
                        let rms = (matched.reduce(0) { $0 + $1.residual * $1.residual } / Double(matched.count)).squareRoot()
                        if best == nil || score > best!.score + 1e-9 || (abs(score - best!.score) < 1e-9 && rms < best!.rms) {
                            best = (score, rms, cal)
                        }
                    }
                }
            }
        }
        guard var cal = best?.cal else { return nil }
        // Refine: weighted least squares on the matched pairs, then re-match with a tighter tolerance.
        var matches: [CalibrationResult.Match] = []
        for pass in 0..<3 {
            let fw = ps.map(\.fwhm).sorted()[ps.count / 2] * cal.gain
            matches = assign(cal) { _ in tolerance ?? max(0.5, (pass == 0 ? 2 : 1.5) * fw) }
            guard matches.count >= 2 else { return nil }
            let order = quadratic && matches.count >= 4 ? 2 : 1
            guard let c = fit(matches.map { ($0.peak.centroid, $0.line.energy, max(1e-3, $0.peak.centroidUncertainty)) },
                              order: order) else { break }
            cal = EnergyCalibration(coefficients: c)
        }
        let final = matches.map { CalibrationResult.Match(peak: $0.peak, line: $0.line, fitted: cal.energy(channel: $0.peak.centroid)) }
        let rms = (final.reduce(0) { $0 + $1.residual * $1.residual } / Double(final.count)).squareRoot()
        return CalibrationResult(calibration: cal, matches: final.sorted { $0.line.energy < $1.line.energy }, rms: rms)
    }

    /// Weighted polynomial least squares E = Σ cₖ chᵏ, weights 1/σ_ch² (centroid uncertainty in channels).
    public static func fit(_ points: [(channel: Double, energy: Double, sigma: Double)], order: Int) -> [Double]? {
        let m = order + 1
        guard points.count >= m else { return nil }
        // Centre the channels for conditioning, then expand back.
        let c0 = points.map(\.channel).reduce(0, +) / Double(points.count)
        var a = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
        var b = [Double](repeating: 0, count: m)
        for p in points {
            let w = 1 / (p.sigma * p.sigma)
            let x = p.channel - c0
            let row = (0..<m).map { pow(x, Double($0)) }
            for r in 0..<m {
                b[r] += w * row[r] * p.energy
                for c in 0..<m { a[r][c] += w * row[r] * row[c] }
            }
        }
        guard let q = EfficiencyCurve.solve(a, b) else { return nil }
        // Σ qₖ (ch − c0)ᵏ → coefficients in ch.
        var out = [Double](repeating: 0, count: m)
        for k in 0..<m {
            for j in 0...k {
                out[j] += q[k] * Double(binomial(k, j)) * pow(-c0, Double(k - j))
            }
        }
        return out
    }

    private static func binomial(_ n: Int, _ k: Int) -> Int {
        guard k > 0, k < n else { return 1 }
        return (1...k).reduce(1) { $0 * (n - $1 + 1) / $1 }
    }

    /// Reference lines of calibration sources, weighted by intensity (%) and a rough 1/E efficiency.
    public static func lines(sources: [CalibrationSource], minIntensity: Double = 2) -> [CalibrationLine] {
        sources.flatMap { s in
            s.prominentLines(minIntensity: minIntensity).filter { $0.kind == .gamma && $0.energy > 40 }.map {
                CalibrationLine(energy: $0.energy, weight: $0.intensity * 1000 / max($0.energy, 100), label: s.label)
            }
        }
    }
}
