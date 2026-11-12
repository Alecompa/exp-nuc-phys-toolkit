import Foundation
import Testing
@testable import NucPhysKit

@Suite("Gamma spectrum and detector foils")
struct GammaSpectrumTests {
    let hpge = ResolutionModel.presets[0].model

    @Test func nistReferenceAndEdges() throws {
        #expect(abs(try PhotonAttenuation.massCoefficient(z: 13, energy: 1000) - 0.06146) < 1e-12)
        let below = try PhotonAttenuation.massCoefficient(z: 13, energy: 1.559599)
        let above = try PhotonAttenuation.massCoefficient(z: 13, energy: 1.5596)
        #expect(below < 363 && above == 3957)
        for z in 1...92 {
            #expect(try PhotonAttenuation.massCoefficient(z: z, energy: 1) > 0)
            #expect(try PhotonAttenuation.massCoefficient(z: z, energy: 20000) > 0)
        }
        #expect(throws: SpectrumError.self) { try PhotonAttenuation.massCoefficient(z: 13, energy: 20001) }
    }

    @Test func compoundMassFractionsAndFoilPath() throws {
        let water = StoppingTarget(name: "Water", components: [
            .init(z: 1, stoichiometry: 2, mass: 1), .init(z: 8, stoichiometry: 1, mass: 16)
        ], density: 1)
        let h = try PhotonAttenuation.massCoefficient(z: 1, energy: 100)
        let o = try PhotonAttenuation.massCoefficient(z: 8, energy: 100)
        let mixture = try PhotonAttenuation.massCoefficient(material: water, energy: 100)
        #expect(abs(mixture - (2 * h + 16 * o) / 18) < 1e-12)
        var foil = DetectorFoil(material: water, thickness: 1e8)
        let normal = try foil.transmission(at: 100)
        #expect(abs(normal - exp(-mixture)) < 1e-12)
        foil.angle = 60
        #expect(abs(try foil.transmission(at: 100) - normal * normal) < 1e-12)
        foil.thickness = 0
        #expect(try foil.transmission(at: 100) == 1)
    }

    @Test func peakAreaCentroidAndResolution() throws {
        var setup = SpectrumSetup()
        setup.lines = [.init(energy: 1000, counts: 10000)]
        setup.maximumEnergy = 2000; setup.channels = 8192; setup.continuumRatio = 0
        for resolution in [hpge, ResolutionModel(kind: .scintillator, resolutionAt662: 0.10)] {
            let bins = try GammaSpectrum.simulate(setup, resolution: resolution)
            let area = bins.reduce(0) { $0 + $1.total }
            let mean = bins.reduce(0) { $0 + $1.energy * $1.total } / area
            let variance = bins.reduce(0) { $0 + pow($1.energy - mean, 2) * $1.total } / area
            #expect(abs(area - 10000) < 0.001)
            #expect(abs(mean - 1000) < 0.001)
            let expectedVariance = pow(resolution.fwhm(at: 1000) / 2.354820045, 2)
            #expect(abs(variance - expectedVariance) < 0.01)
        }
    }

    @Test func contaminantsFoilsAndBackground() throws {
        var setup = SpectrumSetup()
        setup.lines = [.init(energy: 1000, counts: 1000), .init(energy: 1500, counts: 500),
                       .init(energy: 300, counts: 100000, enabled: false)]
        setup.foils = [.init(material: .element(13), thickness: 1e6)]
        setup.continuumRatio = 0; setup.background = 2
        let bins = try GammaSpectrum.simulate(setup, resolution: hpge)
        let expected = try 1000 * setup.foils[0].transmission(at: 1000) + 500 * setup.foils[0].transmission(at: 1500)
        #expect(abs(bins.reduce(0) { $0 + $1.photopeak } - expected) < 0.001)
        #expect(abs(bins.reduce(0) { $0 + $1.background } - 6000) < 1e-8)
        #expect(GammaSpectrum.csv(bins).components(separatedBy: "\n").count == setup.channels + 1)
    }

    @Test func comptonEdgeAreaAndWindowClipping() throws {
        #expect(abs(GammaSpectrum.comptonEdge(energy: 661.657) - 477.334) < 0.01)
        var setup = SpectrumSetup()
        setup.lines = [.init(energy: 1000, counts: 1000)]
        setup.continuumRatio = 2
        let bins = try GammaSpectrum.simulate(setup, resolution: hpge)
        let continuum = bins.reduce(0) { $0 + $1.compton }
        // Broadening loses a small number of counts below zero.
        #expect(continuum > 1995 && continuum <= 2000)
        #expect(bins.filter { $0.energy > 810 }.allSatisfy { $0.compton == 0 })
        setup.maximumEnergy = 500
        let clipped = try GammaSpectrum.simulate(setup, resolution: hpge)
        #expect(clipped.allSatisfy { $0.photopeak == 0 })
        #expect(clipped.reduce(0) { $0 + $1.compton } < continuum)
    }

    @Test func invalidInputsAndPersistence() throws {
        var setup = SpectrumSetup()
        setup.lines = [.init(energy: 661.657, counts: 10000)]
        setup.foils = [.init()]
        let decoded = try JSONDecoder().decode(SpectrumSetup.self, from: JSONEncoder().encode(setup))
        #expect(decoded == setup)
        setup.lines[0].energy = .nan
        #expect(throws: SpectrumError.self) { try GammaSpectrum.simulate(setup, resolution: hpge) }
        setup.lines[0].energy = 1000
        setup.foils[0].angle = 90
        #expect(throws: SpectrumError.self) { try GammaSpectrum.simulate(setup, resolution: hpge) }
        setup.foils = []; setup.channels = 0
        #expect(throws: SpectrumError.self) { try GammaSpectrum.simulate(setup, resolution: hpge) }
    }
}
