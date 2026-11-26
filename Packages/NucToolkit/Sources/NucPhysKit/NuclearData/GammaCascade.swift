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
        /// Fraction of the cascade that reached a level with no γ data (other than the ground state), or a final
        /// level that is not in the level list.
        public let unresolved: Double
        /// Transitions left out because ENSDF gives no intensity for them while their siblings have one.
        public var withoutIntensity = 0
    }

    /// Cascade from the level nearest `excitation` (within `tolerance` keV, default max(2 keV, 0.2 %)).
    public static func from(excitation: Double, scheme: LevelScheme, tolerance: Double? = nil) -> Result {
        let levels = scheme.levels.map(\.energy).filter { $0 > 0 }.sorted()
        let tol = tolerance ?? max(2, 0.002 * excitation)
        guard excitation > 0, let start = levels.min(by: { abs($0 - excitation) < abs($1 - excitation) }),
              abs(start - excitation) <= tol else {
            return Result(lines: [], startLevel: nil, unresolved: excitation > 0 ? 1 : 0, withoutIntensity: 0)
        }
        // Population of each level, keyed by its tabulated energy.
        var population: [Double: Double] = [start: 1]
        var lines: [Line] = []
        var unresolved = 0.0
        var withoutIntensity = 0
        for level in levels.reversed() where level <= start {
            guard let p = population[level], p > 1e-9 else { continue }
            let out = scheme.gammas.filter { abs($0.initialLevel - level) < 0.5 && $0.energy > 0 }
            guard !out.isEmpty else { unresolved += p; continue }
            let weights = out.map { $0.relativeIntensity ?? 0 }
            let total = weights.reduce(0, +)
            if total > 0 { withoutIntensity += out.filter { $0.relativeIntensity == nil }.count }
            for (g, w) in zip(out, weights) {
                let branch = total > 0 ? w / total : 1 / Double(out.count)
                guard branch > 0 else { continue }
                lines.append(Line(energy: g.energy, intensity: p * branch, initialLevel: level, finalLevel: g.finalLevel))
                // Feed the final level (nearest tabulated level; the ground state ends the cascade).
                if g.finalLevel > 0.5 {
                    if let f = levels.min(by: { abs($0 - g.finalLevel) < abs($1 - g.finalLevel) }),
                       abs(f - g.finalLevel) < max(1, 0.001 * f) {
                        population[f, default: 0] += p * branch
                    } else {
                        unresolved += p * branch          // the final level is missing from the list: report, don't drop
                    }
                }
            }
        }
        return Result(lines: lines.sorted { $0.intensity > $1.intensity }, startLevel: start, unresolved: unresolved,
                      withoutIntensity: withoutIntensity)
    }

    /// Mean time from the reaction to the decay of each level of a cascade, s: the level's own mean life plus
    /// the intensity-weighted mean time of the levels feeding it. A short-lived level fed by a long-lived one
    /// therefore decays late (at rest in a solid target). Keyed by the initial-level energies of `lines`.
    public static func meanDecayTimes(_ lines: [Line], meanLife: (Double) -> Double?) -> [Double: Double] {
        let levels = Set(lines.map(\.initialLevel)).sorted(by: >)
        var times: [Double: Double] = [:]
        for level in levels {
            let feeders = lines.filter { abs($0.finalLevel - level) < max(1, 0.001 * level) && $0.initialLevel > level }
            let fed = feeders.reduce(0) { $0 + $1.intensity }
            let delay = fed > 0 ? feeders.reduce(0) { $0 + $1.intensity * (times[$1.initialLevel] ?? 0) } / fed : 0
            times[level] = delay + (meanLife(level) ?? 0)
        }
        return times
    }
}
