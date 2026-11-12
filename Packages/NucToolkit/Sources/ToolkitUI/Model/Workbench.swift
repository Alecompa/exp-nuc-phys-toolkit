import Foundation
import NucPhysKit
import Observation

/// The shared experiment setup every tool reads from: reaction, beam energy, final state.
/// Defined once, so a physicist never retypes ¹²C(p,γ)¹³N at 400 keV in five places.
@MainActor
@Observable
public final class Workbench {
    public var reactionText: String {
        didSet { reparse(); defaults.set(reactionText, forKey: Keys.reaction) }
    }
    /// Projectile kinetic energy in the laboratory, keV.
    public var beamEnergy: Double {
        didSet { defaults.set(beamEnergy, forKey: Keys.beamEnergy) }
    }
    /// Excitation energy of the residual nucleus, keV.
    public var residualExcitation: Double {
        didSet { defaults.set(residualExcitation, forKey: Keys.excitation) }
    }
    public var energyUnit: EnergyUnit {
        didSet { defaults.set(energyUnit.rawValue, forKey: Keys.unit) }
    }

    /// Target material for stopping calculations; nil means the reaction's target element.
    public var customTarget: StoppingTarget? {
        didSet {
            if let t = customTarget, let data = try? JSONEncoder().encode(t) {
                defaults.set(data, forKey: Keys.target)
            } else {
                defaults.removeObject(forKey: Keys.target)
            }
        }
    }
    public var stoppingUnit: StoppingUnit {
        didSet { defaults.set(stoppingUnit.rawValue, forKey: Keys.stoppingUnit) }
    }
    /// Layer thickness for energy loss, Å (always stored in Å; `thicknessUnit` is for display).
    public var layerThickness: Double {
        didSet { defaults.set(layerThickness, forKey: Keys.thickness) }
    }
    public var thicknessUnit: ThicknessUnit {
        didSet { defaults.set(thicknessUnit.rawValue, forKey: Keys.thicknessUnit) }
    }
    /// Beam angle to the layer normal, degrees.
    public var layerAngle: Double {
        didSet { defaults.set(layerAngle, forKey: Keys.layerAngle) }
    }

    /// Layers the beam crosses before the target layer (window, dead layer…), in beam order.
    public var layersBefore: [StackLayer] {
        didSet { save(layersBefore, Keys.layersBefore) }
    }
    /// Layers behind the target layer (backing…), in beam order.
    public var layersAfter: [StackLayer] {
        didSet { save(layersAfter, Keys.layersAfter) }
    }
    /// Kinematics and Q-value screens use the mean energy in the target layer instead of the beam energy.
    public var useTargetMeanEnergy: Bool {
        didSet { defaults.set(useTargetMeanEnergy, forKey: Keys.useMean) }
    }

    // MARK: Nuclear astrophysics

    /// Temperature for the astrophysics tools, GK.
    public var temperatureT9: Double {
        didSet { defaults.set(temperatureT9, forKey: Keys.t9) }
    }
    /// Non-resonant S factor of the entrance channel.
    public var sFactorModel: SFactorModel {
        didSet { save(sFactorModel, Keys.sModel) }
    }
    /// Narrow resonances (centre-of-mass energy, ωγ) added to the rate.
    public var resonances: [NarrowResonance] {
        didSet { save(resonances, Keys.resonances) }
    }
    /// Electron-screening potential U_e, eV.
    public var screeningPotential: Double {
        didSet { defaults.set(screeningPotential, forKey: Keys.screening) }
    }
    /// Abundance of the reaction's target isotope in the target element, %.
    public var isotopicAbundance: Double {
        didSet { defaults.set(isotopicAbundance, forKey: Keys.abundance) }
    }
    /// Channel radius parameter r₀ in R = r₀(A₁^⅓ + A₂^⅓), fm.
    public var channelRadiusR0: Double {
        didSet { defaults.set(channelRadiusR0, forKey: Keys.r0) }
    }

    // MARK: Run planning, detectors, sources

    /// Electrical beam current on target, µA.
    public var beamCurrent: Double {
        didSet { defaults.set(beamCurrent, forKey: Keys.current) }
    }
    /// Beam charge state.
    public var chargeState: Int {
        didSet { defaults.set(chargeState, forKey: Keys.charge) }
    }
    public var spectrumSetup: SpectrumSetup {
        didSet { save(spectrumSetup, Keys.spectrum) }
    }
    public var resolutionModel: ResolutionModel {
        didSet { save(resolutionModel, Keys.resolution) }
    }
    public var efficiencyCurve: EfficiencyCurve {
        didSet { save(efficiencyCurve, Keys.efficiency) }
    }
    /// The lab's radioactive sources.
    public var sources: [SourceCertificate] {
        didSet { save(sources, Keys.sources) }
    }

    public private(set) var reaction: Reaction?
    public private(set) var reactionError: ReactionError?

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reactionText = defaults.string(forKey: Keys.reaction) ?? "12C(p,g)13N"
        let e = defaults.double(forKey: Keys.beamEnergy)
        beamEnergy = defaults.object(forKey: Keys.beamEnergy) == nil ? 400 : max(0, e)
        residualExcitation = defaults.double(forKey: Keys.excitation)
        energyUnit = EnergyUnit(rawValue: defaults.string(forKey: Keys.unit) ?? "") ?? .keV
        customTarget = defaults.data(forKey: Keys.target).flatMap { try? JSONDecoder().decode(StoppingTarget.self, from: $0) }
        stoppingUnit = StoppingUnit(rawValue: defaults.integer(forKey: Keys.stoppingUnit)) ?? .keVPerMicron
        let x = defaults.double(forKey: Keys.thickness)
        layerThickness = x > 0 ? x : 1000          // 100 nm
        thicknessUnit = ThicknessUnit(rawValue: defaults.string(forKey: Keys.thicknessUnit) ?? "") ?? .microgramCm2
        layerAngle = defaults.double(forKey: Keys.layerAngle)
        layersBefore = Self.load(defaults, Keys.layersBefore) ?? []
        layersAfter = Self.load(defaults, Keys.layersAfter) ?? []
        useTargetMeanEnergy = defaults.bool(forKey: Keys.useMean)
        let t9 = defaults.double(forKey: Keys.t9)
        temperatureT9 = t9 > 0 ? t9 : 0.1
        sFactorModel = Self.load(defaults, Keys.sModel) ?? SFactorModel(s0: 1.4)
        resonances = Self.load(defaults, Keys.resonances) ?? []
        screeningPotential = defaults.object(forKey: Keys.screening) as? Double ?? 0
        isotopicAbundance = defaults.object(forKey: Keys.abundance) as? Double ?? 100
        let r0 = defaults.double(forKey: Keys.r0)
        channelRadiusR0 = r0 > 0 ? r0 : 1.25
        let i = defaults.double(forKey: Keys.current)
        beamCurrent = defaults.object(forKey: Keys.current) == nil ? 100 : max(0, i)
        let q = defaults.integer(forKey: Keys.charge)
        chargeState = q > 0 ? q : 1
        spectrumSetup = Self.load(defaults, Keys.spectrum) ?? SpectrumSetup()
        resolutionModel = Self.load(defaults, Keys.resolution) ?? ResolutionModel.presets[0].model
        efficiencyCurve = Self.load(defaults, Keys.efficiency) ?? .example
        sources = Self.load(defaults, Keys.sources) ?? []
        reparse()
    }

    /// Live parse used by editors before committing.
    public static func parse(_ text: String) -> Result<Reaction, ReactionError> {
        do { return .success(try Reaction(notation: text)) } catch let e as ReactionError {
            return .failure(e)
        } catch { return .failure(.malformed) }
    }

    private func reparse() {
        switch Self.parse(reactionText) {
        case .success(let r): reaction = r; reactionError = nil
        case .failure(let e): reaction = nil; reactionError = e
        }
    }

    /// The beam ion: the reaction's projectile with its AME2020 mass.
    public var stoppingIon: StoppingIon? {
        guard let p = reaction?.projectile, (1...92).contains(p.z) else { return nil }
        return StoppingIon(nuclide: p)
    }

    /// The reaction's target element at SRIM's natural density.
    public var reactionTargetMaterial: StoppingTarget? {
        guard let t = reaction?.target, (1...92).contains(t.z) else { return nil }
        return .element(t.z)
    }

    /// The material used by the stopping tools.
    public var stoppingTarget: StoppingTarget? { customTarget ?? reactionTargetMaterial }

    public var stoppingCalculator: StoppingCalculator? {
        guard let ion = stoppingIon, let target = stoppingTarget else { return nil }
        return StoppingCalculator(ion: ion, target: target)
    }

    // MARK: Layer stack

    /// The beam's passage through the stack: layers before the target, the target layer, layers after.
    public struct StackOutcome: Sendable {
        public let before: [StoppingCalculator.EnergyLoss]
        /// nil when the beam stops before reaching the target layer.
        public let target: StoppingCalculator.EnergyLoss?
        public let after: [StoppingCalculator.EnergyLoss]
        /// Every layer the beam reaches, in order.
        public var all: [StoppingCalculator.EnergyLoss] { before + (target.map { [$0] } ?? []) + after }
    }

    public static let targetLayerID = UUID(uuidString: "00000000-0000-0000-0000-00000000007A")!

    /// The target layer, as used by the Energy Loss tool.
    public var targetLayer: StackLayer? {
        stoppingTarget.map { StackLayer(id: Self.targetLayerID, target: $0, thickness: layerThickness) }
    }

    /// All layers in beam order.
    public var allLayers: [StackLayer] { layersBefore + (targetLayer.map { [$0] } ?? []) + layersAfter }

    private struct StackKey: Hashable {
        let ion: StoppingIon
        let layers: [StackLayer]
        let energy: Double
        let angle: Double
        let before: Int
    }
    @ObservationIgnored private var stackCache: (key: StackKey, value: StackOutcome?)?

    /// The transport through all layers; memoised, since several views read it on every redraw.
    public var stackOutcome: StackOutcome? {
        guard let ion = stoppingIon, targetLayer != nil, beamEnergy > 0 else { return nil }
        let layers = allLayers
        let key = StackKey(ion: ion, layers: layers, energy: beamEnergy, angle: layerAngle, before: layersBefore.count)
        if let c = stackCache, c.key == key { return c.value }
        var value: StackOutcome?
        if let r = try? LayerStack.transport(ion: ion, layers: layers, energy: beamEnergy, angle: layerAngle) {
            let nBefore = layersBefore.filter { $0.thickness > 0 }.count
            let before = Array(r.prefix(nBefore))
            let target = r.count > nBefore ? r[nBefore] : nil
            let after = r.count > nBefore + 1 ? Array(r[(nBefore + 1)...]) : []
            value = StackOutcome(before: before, target: target, after: after)
        }
        stackCache = (key, value)
        return value
    }

    /// Energy at which the reaction is evaluated: the mean energy in the target layer when
    /// `useTargetMeanEnergy` is on and the beam reaches that layer, the beam energy otherwise.
    public var reactionEnergy: Double {
        guard useTargetMeanEnergy, let t = stackOutcome?.target else { return beamEnergy }
        return t.meanEnergy
    }

    /// True when `reactionEnergy` is the mean energy in the target rather than the beam energy.
    public var isUsingTargetMeanEnergy: Bool { useTargetMeanEnergy && stackOutcome?.target != nil }

    // MARK: Astrophysics channel

    /// The entrance channel projectile + target, when both are charged.
    public var entranceChannel: ChargedChannel? {
        guard let r = reaction else { return nil }
        let c = ChargedChannel.entrance(r)
        return c.isCharged ? c : nil
    }

    /// Centre-of-mass energy of the entrance channel at `reactionEnergy` (non-relativistic), keV.
    public var reactionEnergyCM: Double? {
        guard let r = reaction else { return nil }
        return ChargedChannel.entrance(r).cmEnergy(lab: reactionEnergy)
    }

    /// Atom fraction of the reaction's target isotope in the stopping target (element fraction ×
    /// isotopic abundance), or nil when the target material does not contain that element.
    public var activeAtomFraction: Double? {
        guard let nucleus = reaction?.target, let t = stoppingTarget else { return nil }
        let f = t.activeFraction(z: nucleus.z, a: nucleus.a, abundance: isotopicAbundance / 100)
        return f > 0 ? f : nil
    }

    /// Beam particles per second on target.
    public var particlesPerSecond: Double {
        Beam.particlesPerSecond(current: beamCurrent * 1e-6, chargeState: chargeState)
    }

    /// Active target nuclei per cm² in the Energy Loss target layer (element fraction × abundance).
    public var activeArealDensity: Double? {
        guard let t = stoppingTarget, let nucleus = reaction?.target, activeAtomFraction != nil else { return nil }
        return t.activeArealDensity(z: nucleus.z, a: nucleus.a, abundance: isotopicAbundance / 100,
                                   thickness: layerThickness, angle: layerAngle)
    }

    /// Laboratory stopping per active target nucleus, eV cm², at a laboratory energy (keV).
    public func effectiveStopping(at energy: Double) -> Double? {
        guard let calc = stoppingCalculator, let f = activeAtomFraction,
              let s = try? calc.stopping(at: energy) else { return nil }
        return s.total * 1e-15 / f
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ defaults: UserDefaults, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private enum Keys {
        static let current = "run.beamCurrent"
        static let charge = "run.chargeState"
        static let spectrum = "detector.spectrumSetup"
        static let resolution = "detector.resolution"
        static let efficiency = "detector.efficiency"
        static let sources = "sources.certificates"
        static let t9 = "astro.t9"
        static let sModel = "astro.sFactorModel"
        static let resonances = "astro.resonances"
        static let screening = "astro.screeningPotential"
        static let abundance = "astro.isotopicAbundance"
        static let r0 = "astro.r0"
        static let layersBefore = "workbench.layersBefore"
        static let layersAfter = "workbench.layersAfter"
        static let useMean = "workbench.useTargetMeanEnergy"
        static let target = "workbench.target"
        static let stoppingUnit = "settings.stoppingUnit"
        static let thickness = "workbench.layerThickness"
        static let thicknessUnit = "settings.thicknessUnit"
        static let layerAngle = "workbench.layerAngle"
        static let reaction = "workbench.reaction"
        static let beamEnergy = "workbench.beamEnergy"
        static let excitation = "workbench.residualExcitation"
        static let unit = "settings.energyUnit"
    }
}

public enum EnergyUnit: String, CaseIterable, Identifiable, Sendable {
    case keV, MeV
    public var id: String { rawValue }
    /// keV per unit.
    public var scale: Double { self == .keV ? 1 : 1000 }
    public var label: String { rawValue }
}
