import Foundation

/// Energy resolution (FWHM) of a γ-ray detector.
public struct ResolutionModel: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        /// FWHM² = a² + (2.355)² F w E + (c E)²: electronic noise, Fano statistics, charge collection.
        case semiconductor
        /// FWHM ∝ √E, given by the relative resolution at 662 keV.
        case scintillator
    }

    public var kind: Kind
    /// Electronic noise FWHM, keV.
    public var noise: Double
    /// Fano factor.
    public var fano: Double
    /// Energy per electron–hole pair, keV (2.96 eV for Ge).
    public var pairEnergy: Double
    /// Charge-collection term (dimensionless, FWHM fraction of E).
    public var collection: Double
    /// Scintillator: relative FWHM at 662 keV (0.07 = 7 %).
    public var resolutionAt662: Double

    public init(kind: Kind, noise: Double = 0.9, fano: Double = 0.11, pairEnergy: Double = 2.96e-3,
                collection: Double = 5e-4, resolutionAt662: Double = 0.07) {
        self.kind = kind; self.noise = noise; self.fano = fano; self.pairEnergy = pairEnergy
        self.collection = collection; self.resolutionAt662 = resolutionAt662
    }

    /// FWHM at `energy` keV, keV.
    public func fwhm(at e: Double) -> Double {
        switch kind {
        case .semiconductor:
            let stat = 2.355 * 2.355 * fano * pairEnergy * e
            return (noise * noise + stat + pow(collection * e, 2)).squareRoot()
        case .scintillator:
            return resolutionAt662 * 662 * (max(e, 0) / 662).squareRoot()
        }
    }

    public struct Preset: Hashable, Sendable, Identifiable {
        public let name: String
        public let model: ResolutionModel
        public var id: String { name }
    }

    public static let presets: [Preset] = [
        Preset(name: "HPGe coaxial (1.9 keV at 1.33 MeV)", model: ResolutionModel(kind: .semiconductor, noise: 0.9, collection: 5e-4)),
        Preset(name: "HPGe large / clover", model: ResolutionModel(kind: .semiconductor, noise: 1.1, collection: 7e-4)),
        Preset(name: "Planar HPGe / LEGe", model: ResolutionModel(kind: .semiconductor, noise: 0.45, collection: 3e-4)),
        Preset(name: "NaI(Tl), 7 % at 662 keV", model: ResolutionModel(kind: .scintillator, resolutionAt662: 0.07)),
        Preset(name: "LaBr₃(Ce), 2.8 % at 662 keV", model: ResolutionModel(kind: .scintillator, resolutionAt662: 0.028)),
        Preset(name: "BGO, 10 % at 662 keV", model: ResolutionModel(kind: .scintillator, resolutionAt662: 0.10)),
    ]
}

/// Full-energy-peak efficiency curve ln ε = Σᵢ aᵢ (ln(E/E₀))ⁱ fitted by weighted least squares.
public struct EfficiencyCurve: Hashable, Sendable, Codable {
    public struct Point: Hashable, Sendable, Codable, Identifiable {
        public var id: UUID
        /// keV
        public var energy: Double
        /// Absolute full-energy-peak efficiency (0–1).
        public var efficiency: Double
        /// Relative uncertainty (0.02 = 2 %).
        public var relativeUncertainty: Double
        public init(id: UUID = UUID(), energy: Double, efficiency: Double, relativeUncertainty: Double = 0.02) {
            self.id = id; self.energy = energy; self.efficiency = efficiency; self.relativeUncertainty = relativeUncertainty
        }
    }

    public static let referenceEnergy = 1000.0
    public var points: [Point]
    /// Polynomial order in ln E (1–4).
    public var order: Int

    public init(points: [Point], order: Int = 3) {
        self.points = points; self.order = order
    }

    public struct Fit: Hashable, Sendable {
        public let coefficients: [Double]
        public let chiSquared: Double
        public let degreesOfFreedom: Int
        public func efficiency(at e: Double) -> Double {
            let x = log(e / EfficiencyCurve.referenceEnergy)
            return exp(coefficients.enumerated().reduce(0) { $0 + $1.element * pow(x, Double($1.offset)) })
        }
        public var reducedChiSquared: Double? { degreesOfFreedom > 0 ? chiSquared / Double(degreesOfFreedom) : nil }
    }

    /// Weighted fit in ln ε; nil with fewer points than parameters.
    public func fit() -> Fit? {
        let pts = points.filter { $0.energy > 0 && $0.efficiency > 0 }
        let m = min(max(order, 1), 4) + 1
        guard pts.count >= m else { return nil }
        var ata = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
        var atb = [Double](repeating: 0, count: m)
        for p in pts {
            let x = log(p.energy / Self.referenceEnergy), y = log(p.efficiency)
            let w = 1 / pow(max(p.relativeUncertainty, 1e-4), 2)
            let row = (0..<m).map { pow(x, Double($0)) }
            for i in 0..<m {
                atb[i] += w * row[i] * y
                for j in 0..<m { ata[i][j] += w * row[i] * row[j] }
            }
        }
        guard let c = Self.solve(ata, atb) else { return nil }
        let fit = Fit(coefficients: c, chiSquared: 0, degreesOfFreedom: 0)
        let chi = pts.reduce(0) { acc, p in
            acc + pow(log(p.efficiency) - log(fit.efficiency(at: p.energy)), 2) / pow(max(p.relativeUncertainty, 1e-4), 2)
        }
        return Fit(coefficients: c, chiSquared: chi, degreesOfFreedom: pts.count - m)
    }

    /// Gaussian elimination with partial pivoting.
    static func solve(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        var a = a, b = b
        let n = b.count
        for col in 0..<n {
            guard let piv = (col..<n).max(by: { abs(a[$0][col]) < abs(a[$1][col]) }), abs(a[piv][col]) > 1e-300 else { return nil }
            a.swapAt(col, piv); b.swapAt(col, piv)
            for r in (col + 1)..<n {
                let f = a[r][col] / a[col][col]
                for k in col..<n { a[r][k] -= f * a[col][k] }
                b[r] -= f * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            x[i] = (b[i] - ((i + 1)..<n).reduce(0) { $0 + a[i][$1] * x[$1] }) / a[i][i]
        }
        return x
    }

    /// A typical 100 % relative-efficiency coaxial HPGe with a point source at 10 cm (order-of-magnitude example).
    public static let example = EfficiencyCurve(points: [
        Point(energy: 122, efficiency: 0.0245), Point(energy: 344, efficiency: 0.0142),
        Point(energy: 662, efficiency: 0.0086), Point(energy: 1173, efficiency: 0.0057),
        Point(energy: 1332, efficiency: 0.0052), Point(energy: 1408, efficiency: 0.0050),
        Point(energy: 2615, efficiency: 0.0031), Point(energy: 6129, efficiency: 0.0016),
    ], order: 3)
}

public enum Geometry {
    /// Solid angle (sr) of a disk of radius `radius` seen on axis from `distance` (same units).
    public static func diskSolidAngle(radius r: Double, distance d: Double) -> Double {
        2 * .pi * (1 - d / (d * d + r * r).squareRoot())
    }

    /// Half-opening angle (rad) of a disk of radius r at distance d.
    public static func halfOpeningAngle(radius r: Double, distance d: Double) -> Double { atan2(r, d) }
}

/// Doppler shift of γ rays emitted in flight.
public enum GammaDoppler {
    /// E = E₀ √(1 − β²) / (1 − β cos θ), θ between the emitter's velocity and the photon (lab).
    public static func energy(_ e0: Double, beta: Double, angle theta: Double) -> Double {
        e0 * (1 - beta * beta).squareRoot() / (1 - beta * cos(theta))
    }

    /// Energies seen by a detector at `angle` with half-opening `halfOpening` (rad): min…max.
    public static func range(_ e0: Double, beta: Double, angle theta: Double, halfOpening a: Double) -> ClosedRange<Double> {
        let lo = max(0, theta - a), hi = min(.pi, theta + a)
        let e1 = energy(e0, beta: beta, angle: lo), e2 = energy(e0, beta: beta, angle: hi)
        return min(e1, e2)...max(e1, e2)
    }

    /// Mean energy over a uniformly illuminated circular detector face (numerical average over the cone).
    public static func meanOverCone(_ e0: Double, beta: Double, angle theta: Double, halfOpening a: Double, samples: Int = 60) -> Double {
        guard a > 0 else { return energy(e0, beta: beta, angle: theta) }
        // Points on the cone around the detector axis, weighted by solid angle.
        var sum = 0.0, wsum = 0.0
        let axis = (sin(theta), 0.0, cos(theta))
        let u = (cos(theta), 0.0, -sin(theta)), v = (0.0, 1.0, 0.0)
        for i in 0..<samples {
            let alpha = a * (Double(i) + 0.5) / Double(samples)
            for k in 0..<36 {
                let phi = 2 * .pi * Double(k) / 36
                let dz = cos(alpha) * axis.2 + sin(alpha) * (cos(phi) * u.2 + sin(phi) * v.2)
                let w = sin(alpha)
                sum += w * energy(e0, beta: beta, angle: acos(max(-1, min(1, dz))))
                wsum += w
            }
        }
        return sum / wsum
    }

    /// Recoil-corrected γ energy for a transition of energy `transition` keV in a nucleus of mass `mass` keV:
    /// E_γ ≈ E − E²/(2Mc²).
    public static func recoilCorrected(transition e: Double, mass m: Double) -> Double { e - e * e / (2 * m) }
}
