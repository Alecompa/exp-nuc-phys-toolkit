import Foundation

/// γ rays emitted when a level de-excites to the ground state, following the ENSDF branching of each level.
public enum GammaCascade {
    public struct Line: Hashable, Sendable, Identifiable {
        /// keV
        public let energy: Double
        /// γ rays per decay of the starting level (internal conversion neglected).
        public let intensity: Double
        public let initialLevel: Double
        public let finalLevel: Double
        public var id: String { "\(initialLevel)-\(finalLevel)-\(energy)" }
    }

    public struct Result: Sendable {
        public let lines: [Line]
        /// The ENSDF level matched to the requested excitation energy, keV; nil when none is close.
        public let startLevel: Double?
        /// Fraction of the cascade that reached a level with no γ data (other than the ground state).
        public let unresolved: Double
    }

    /// Cascade from the level nearest `excitation` (within `tolerance` keV, default max(2 keV, 0.2 %)).
    public static func from(excitation: Double, scheme: LevelScheme, tolerance: Double? = nil) -> Result {
        let levels = scheme.levels.map(\.energy).filter { $0 > 0 }.sorted()
        let tol = tolerance ?? max(2, 0.002 * excitation)
        guard excitation > 0, let start = levels.min(by: { abs($0 - excitation) < abs($1 - excitation) }),
              abs(start - excitation) <= tol else {
            return Result(lines: [], startLevel: nil, unresolved: excitation > 0 ? 1 : 0)
        }
        // Population of each level, keyed by its tabulated energy.
        var population: [Double: Double] = [start: 1]
        var lines: [Line] = []
        var unresolved = 0.0
        for level in levels.reversed() where level <= start {
            guard let p = population[level], p > 1e-9 else { continue }
            let out = scheme.gammas.filter { abs($0.initialLevel - level) < 0.5 && $0.energy > 0 }
            guard !out.isEmpty else { unresolved += p; continue }
            let weights = out.map { $0.relativeIntensity ?? 0 }
            let total = weights.reduce(0, +)
            for (g, w) in zip(out, weights) {
                let branch = total > 0 ? w / total : 1 / Double(out.count)
                guard branch > 0 else { continue }
                lines.append(Line(energy: g.energy, intensity: p * branch, initialLevel: level, finalLevel: g.finalLevel))
                // Feed the final level (nearest tabulated level; the ground state ends the cascade).
                if g.finalLevel > 0.5, let f = levels.min(by: { abs($0 - g.finalLevel) < abs($1 - g.finalLevel) }),
                   abs(f - g.finalLevel) < max(1, 0.001 * f) {
                    population[f, default: 0] += p * branch
                }
            }
        }
        return Result(lines: lines.sorted { $0.intensity > $1.intensity }, startLevel: start, unresolved: unresolved)
    }
}
