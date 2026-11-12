import Foundation
import NucPhysKit

/// Versioned snapshot of shared physics inputs, independent of future workbench edits.
struct ExperimentSetup: Codable, Equatable, Sendable {
    var version: Int = 1
    var reactionText: String
    var beamEnergy: Double
    var residualExcitation: Double
    var customTarget: StoppingTarget?
    var layerThickness: Double
    var layerAngle: Double
    var layersBefore: [StackLayer]
    var layersAfter: [StackLayer]
    var useTargetMeanEnergy: Bool
    var temperatureT9: Double
    var sFactorModel: SFactorModel
    var resonances: [NarrowResonance]
    var screeningPotential: Double
    var isotopicAbundance: Double
    var channelRadiusR0: Double
    var beamCurrent: Double
    var chargeState: Int
    var spectrumSetup: SpectrumSetup
    var resolutionModel: ResolutionModel
    var efficiencyCurve: EfficiencyCurve

    @MainActor init(_ workbench: Workbench) {
        reactionText = workbench.reactionText
        beamEnergy = workbench.beamEnergy
        residualExcitation = workbench.residualExcitation
        customTarget = workbench.customTarget
        layerThickness = workbench.layerThickness
        layerAngle = workbench.layerAngle
        layersBefore = workbench.layersBefore
        layersAfter = workbench.layersAfter
        useTargetMeanEnergy = workbench.useTargetMeanEnergy
        temperatureT9 = workbench.temperatureT9
        sFactorModel = workbench.sFactorModel
        resonances = workbench.resonances
        screeningPotential = workbench.screeningPotential
        isotopicAbundance = workbench.isotopicAbundance
        channelRadiusR0 = workbench.channelRadiusR0
        beamCurrent = workbench.beamCurrent
        chargeState = workbench.chargeState
        spectrumSetup = workbench.spectrumSetup
        resolutionModel = workbench.resolutionModel
        efficiencyCurve = workbench.efficiencyCurve
    }

    @MainActor func restore(to workbench: Workbench) throws {
        guard version == 1 else { throw ExperimentError.unsupportedVersion }
        _ = try Reaction(notation: reactionText)
        workbench.reactionText = reactionText
        workbench.beamEnergy = beamEnergy
        workbench.residualExcitation = residualExcitation
        workbench.customTarget = customTarget
        workbench.layerThickness = layerThickness
        workbench.layerAngle = layerAngle
        workbench.layersBefore = layersBefore
        workbench.layersAfter = layersAfter
        workbench.useTargetMeanEnergy = useTargetMeanEnergy
        workbench.temperatureT9 = temperatureT9
        workbench.sFactorModel = sFactorModel
        workbench.resonances = resonances
        workbench.screeningPotential = screeningPotential
        workbench.isotopicAbundance = isotopicAbundance
        workbench.channelRadiusR0 = channelRadiusR0
        workbench.beamCurrent = beamCurrent
        workbench.chargeState = chargeState
        workbench.spectrumSetup = spectrumSetup
        workbench.resolutionModel = resolutionModel
        workbench.efficiencyCurve = efficiencyCurve
    }
}

enum ExperimentError: LocalizedError {
    case unsupportedVersion
    var errorDescription: String? { "This saved setup uses an unsupported format version." }
}
