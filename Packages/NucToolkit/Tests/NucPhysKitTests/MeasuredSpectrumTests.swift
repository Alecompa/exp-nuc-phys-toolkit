import Foundation
import Testing
@testable import NucPhysKit

/// Deterministic Poisson-like noise (Box–Muller on a seeded LCG) so the tests are reproducible.
private struct Noise {
    var state: UInt64
    mutating func uniform() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return (Double(state >> 11) + 0.5) / Double(1 << 53)
    }
    mutating func poisson(_ mean: Double) -> Double {
        guard mean > 0 else { return 0 }
        let z = (-2 * log(uniform())).squareRoot() * cos(2 * .pi * uniform())
        return max(0, (mean + z * mean.squareRoot()).rounded())
    }
}

/// Synthetic HPGe spectrum: E = 2 keV + 0.5 keV/ch · ch, FWHM(E) = √(1 + 0.002 E) keV, exponential continuum.
private func synthetic(lines: [(Double, Double)], channels: Int = 8192, gain: Double = 0.5, offset: Double = 2,
                       seed: UInt64 = 7) -> [Double] {
    var noise = Noise(state: seed)
    return (0..<channels).map { ch in
        let e = offset + gain * Double(ch)
        var mean = 200 * exp(-e / 800) + 5
        for (energy, area) in lines {
            let s = (1 + 0.002 * energy).squareRoot() / 2.3548 / gain     // channels
            let x = (Double(ch) - (energy - offset) / gain) / s
            mean += area / (s * (2 * .pi).squareRoot()) * exp(-0.5 * x * x)
        }
        return noise.poisson(mean)
    }
}

@Suite("Measured spectra: import, peak search, calibration")
struct MeasuredSpectrumTests {
    @Test func peakSearchFindsCobaltWithCentroidAndArea() throws {
        let counts = synthetic(lines: [(1173.228, 20000), (1332.492, 20000)])
        let peaks = PeakSearch.find(counts, fwhm: 4, threshold: 5)
        let p = try #require(peaks.first { abs($0.centroid - (1332.492 - 2) / 0.5) < 3 })
        #expect(abs(p.centroid - 2660.984) < 0.1)                 // (1332.492 − 2)/0.5
        #expect(abs(p.area / 20000 - 1) < 0.05)
        #expect(abs(p.fwhm - (1 + 0.002 * 1332.492).squareRoot() / 0.5) < 0.6)
    }

    @Test func autoCalibrationFromEuropiumAndCobalt() throws {
        let truth: [(Double, Double)] = [(121.78, 60000), (244.70, 15000), (344.28, 40000), (778.90, 12000), (964.08, 12000),
                                         (1085.84, 8000), (1112.08, 11000), (1408.01, 16000), (1173.228, 20000), (1332.492, 20000)]
        let counts = synthetic(lines: truth)
        let peaks = PeakSearch.find(counts, fwhm: 4, threshold: 5)
        let eu = try #require(CalibrationSources.source(named: "152Eu"))
        let co = try #require(CalibrationSources.source(named: "60Co"))
        let result = try #require(AutoCalibration.calibrate(peaks: peaks, lines: AutoCalibration.lines(sources: [eu, co])))
        #expect(abs(result.calibration.gain - 0.5) < 2e-4)
        #expect(abs(result.calibration.energy(channel: 0) - 2) < 0.2)
        #expect(result.matches.count >= 8)
        #expect(result.rms < 0.2)
    }

    @Test func calibrationRoundTripAndQuadraticFit() throws {
        let cal = EnergyCalibration(coefficients: [1.5, 0.4, 2e-6])
        #expect(abs(cal.channel(energy: cal.energy(channel: 3000)) - 3000) < 1e-9)
        let pts = [100.0, 1000, 2500, 4000, 6000].map { (channel: $0, energy: cal.energy(channel: $0), sigma: 0.1) }
        let c = try #require(AutoCalibration.fit(pts, order: 2))
        for (a, b) in zip(c, cal.coefficients) { #expect(abs(a - b) < 1e-9 * max(1, abs(b))) }
    }

    @Test func readsSpeAndColumns() throws {
        let spe = """
        $SPEC_ID:
        test
        $MEAS_TIM:
        100 120
        $DATA:
        0 4
        1
        2
        30
        2
        1
        $ENER_FIT:
        0.5 0.25
        """
        let s = try MeasuredSpectrum.read(Data(spe.utf8), name: "a.Spe")
        #expect(s.counts == [1, 2, 30, 2, 1])
        #expect(s.liveTime == 100 && s.realTime == 120)
        #expect(s.fileCalibration?.coefficients == [0.5, 0.25])

        let csv = "channel,counts\n0,5\n1,6\n2,7\n"
        #expect(try MeasuredSpectrum.read(Data(csv.utf8), name: "b.csv").counts == [5, 6, 7])
        let energies = "# keV counts\n10.0 1\n10.5 2\n11.0 3\n"
        let e = try MeasuredSpectrum.read(Data(energies.utf8), name: "c.txt")
        #expect(e.fileCalibration?.coefficients == [10, 0.5])
        #expect(throws: MeasuredSpectrum.ImportError.self) { try MeasuredSpectrum.read(Data("hello".utf8), name: "d.txt") }
    }

    @Test func readsChn() throws {
        var d = Data()
        func put16(_ v: Int16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        put16(-1); put16(1); put16(1); put16(0)          // type, MCA, segment, seconds
        put32(6000); put32(5000)                         // real, live (20 ms ticks)
        d.append(contentsOf: [UInt8](repeating: 0x30, count: 12))   // date and time
        put16(0); put16(3)                               // start channel, length
        for v: UInt32 in [7, 8, 9] { put32(v) }
        let s = try MeasuredSpectrum.read(d, name: "x.Chn")
        #expect(s.counts == [7, 8, 9])
        #expect(s.realTime == 120 && s.liveTime == 100)
    }
}

@Suite("Measured spectra: robustness")
struct MeasuredSpectrumRobustnessTests {
    @Test func shortSpectraAndWideFilterDoNotCrash() {
        #expect(PeakSearch.find([Double](repeating: 5, count: 17), fwhm: 6).isEmpty)
        #expect(PeakSearch.find([Double](repeating: 5, count: 1024), fwhm: 500).isEmpty)
    }

    @Test func headerNumbersAndDescendingEnergies() throws {
        let text = "Live time: 100\nchannel counts\n0 4\n1 5\n2 6\n3 7\n"
        #expect(try MeasuredSpectrum.read(Data(text.utf8), name: "a.txt").counts == [4, 5, 6, 7])
        let desc = "12.5 3\n12.0 2\n11.5 1\n"
        let s = try MeasuredSpectrum.read(Data(desc.utf8), name: "b.txt")
        #expect(s.counts == [1, 2, 3])
        #expect(s.fileCalibration?.coefficients == [11.5, 0.5])
    }
}
