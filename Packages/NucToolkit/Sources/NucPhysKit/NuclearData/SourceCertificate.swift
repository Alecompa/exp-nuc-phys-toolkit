import Foundation

/// A radioactive source in the lab: its certificate activity at a reference date.
public struct SourceCertificate: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    /// NUBASE name, e.g. "60Co", "166mHo".
    public var nuclide: String
    /// Lab label, e.g. "PTB 2019-123".
    public var name: String
    /// Activity at the reference date, Bq.
    public var activity: Double
    /// Relative standard uncertainty of the certificate activity (0.015 = 1.5 %).
    public var relativeUncertainty: Double
    public var referenceDate: Date

    public init(id: UUID = UUID(), nuclide: String, name: String = "", activity: Double,
                relativeUncertainty: Double = 0.015, referenceDate: Date) {
        self.id = id; self.nuclide = nuclide; self.name = name; self.activity = activity
        self.relativeUncertainty = relativeUncertainty; self.referenceDate = referenceDate
    }

    public var state: NuclearState? { Nubase.nubase2020.state(named: nuclide) }

    public struct Now: Hashable, Sendable {
        public let activity: Double
        /// Combined relative uncertainty (certificate and half-life).
        public let relativeUncertainty: Double
        public let elapsed: TimeInterval
    }

    /// Activity at `date`, with the certificate and half-life uncertainties combined in quadrature.
    public func activity(at date: Date) -> Now? {
        guard let s = state, let t = s.halfLife else { return nil }
        let dt = date.timeIntervalSince(referenceDate)
        let a = RadioactiveDecay.activity(initial: activity, elapsed: dt, halfLife: t)
        let uT = s.halfLifeUncertainty.map {
            RadioactiveDecay.relativeActivityUncertainty(elapsed: dt, halfLife: t, halfLifeUncertainty: $0)
        } ?? 0
        return Now(activity: a, relativeUncertainty: (relativeUncertainty * relativeUncertainty + uT * uT).squareRoot(), elapsed: dt)
    }
}
