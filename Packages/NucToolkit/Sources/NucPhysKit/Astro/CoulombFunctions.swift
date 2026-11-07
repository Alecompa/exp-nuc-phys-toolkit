import Foundation

/// Regular and irregular Coulomb functions F_ℓ, G_ℓ through F² + G², for penetrabilities and shift
/// factors deep below the barrier.
///
/// Method: two independent solutions of u'' = (ℓ(ℓ+1)/ρ² + 2η/ρ − 1)u start far beyond the turning point
/// as WKB waves p^−½ sin φ and p^−½ cos φ (Wronskian 1, like F and G) and are integrated inward with RK4.
/// Any rotation of (F, G) leaves F² + G² unchanged, so their phase does not matter; under the barrier G
/// dominates and is the growing direction of the inward integration, so the result is stable. Values are
/// rescaled as they grow, and the penetrability is also returned as a logarithm.
public enum CoulombFunctions {
    public struct Result: Hashable, Sendable {
        /// P_ℓ = ρ/(F² + G²); 0 when it underflows (see `lnP`).
        public let penetrability: Double
        /// ln P_ℓ.
        public let lnP: Double
        /// Shift factor S_ℓ = ρ(FF' + GG')/(F² + G²).
        public let shift: Double
        public let rho: Double
        public let eta: Double
    }

    /// Integration step in units of the local wavelength scale 1/√|q|.
    static let step = 0.08
    static let maxStep = 0.2

    public static func penetrability(l: Int, eta: Double, rho: Double) -> Result {
        precondition(l >= 0 && rho > 0)
        let L = Double(l * (l + 1))
        func q(_ r: Double) -> Double { L / (r * r) + 2 * eta / r - 1 }

        let turning = eta + (eta * eta + L).squareRoot()
        // Far enough out for first-order WKB to be accurate to ~1e-5 even for large η.
        let start = max(2 * turning + 1000, rho + 1000, 30 * turning)
        let p2 = -q(start)
        let p = p2.squareRoot()
        let dp = (eta / (start * start) + L / (start * start * start)) / p
        // u = p^−½ sin φ and p^−½ cos φ with φ' = p.
        var y = SIMD4<Double>(0, p.squareRoot(),                       // F-like, F'
                              1 / p.squareRoot(), -dp / (2 * pow(p, 1.5)))   // G-like, G'
        var logScale = 0.0
        var r = start

        @inline(__always) func f(_ r: Double, _ y: SIMD4<Double>) -> SIMD4<Double> {
            let k = q(r)
            return SIMD4(y[1], k * y[0], y[3], k * y[2])
        }
        while r > rho {
            let local = max(1, abs(q(r)).squareRoot())
            var h = min(step / local, maxStep)
            if r - h < rho { h = r - rho }
            // Inward step: dr = −h.
            let k1 = f(r, y)
            let k2 = f(r - h / 2, y - h / 2 * k1)
            let k3 = f(r - h / 2, y - h / 2 * k2)
            let k4 = f(r - h, y - h * k3)
            y -= h / 6 * (k1 + 2 * k2 + 2 * k3 + k4)
            r -= h
            if max(abs(y[0]), abs(y[2])) > 1e100 {
                y *= 1e-100
                logScale += 100 * log(10.0)
            }
        }
        let sum = y[0] * y[0] + y[2] * y[2]
        let lnP = log(rho) - log(sum) - 2 * logScale
        let shift = rho * (y[0] * y[1] + y[2] * y[3]) / sum
        return Result(penetrability: exp(lnP), lnP: lnP, shift: shift, rho: rho, eta: eta)
    }
}
