import Foundation
import Testing
@testable import NucPhysKit

private func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt"))
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite("EXFOR index")
struct ExforIndexTests {
    let index = ExforIndex.bundled

    @Test func bundledIndexIsPinned() {
        // Numbers printed by Tools/build_exfor_index.py for the 2026-09-11 snapshot.
        #expect(index.commit == "f9c2d73f780b576cf1276b8e4018fddd1430fee8")
        #expect(index.date == "2026-09-11")
        #expect(index.count == 51871)
    }

    @Test func everyIndexEntryParses() {
        let all = index.allDatasets()
        #expect(all.count == index.count)
        #expect(all.allSatisfy { $0 != nil })
    }

    @Test func findsAl27ProtonCapture() throws {
        let r = try Reaction(notation: "27Al(p,g)28Si")
        let ds = index.datasets(for: r)
        // One subentry gives three tables: the ground-state transition and the transitions to levels 1 and 2.
        #expect(Set(ds.filter { $0.entry == "D6305" && $0.subentry == "002" }.map(\.level)) == [0, 1, 2])
        let chakrabarty = try #require(ds.first { $0.entry == "D6305" && $0.directory == "p/Al-27/p-g" })
        #expect(chakrabarty.author == "D.R.Chakrabarty")
        #expect(chakrabarty.year == 2017)
        #expect(chakrabarty.level == 0)
        #expect(chakrabarty.channel.label == "(p,γ)")
        let lyons = try #require(ds.first { $0.entry == "F1188" })
        #expect(lyons.level == nil)
        #expect(lyons.product == "Si-28")
        // Partial cross sections to excited levels live in p-g-L<n> directories of the same channel.
        #expect(ds.contains { ($0.level ?? 0) > 0 })
        #expect(ds.allSatisfy { $0.projectile == "p" && $0.outgoing == "g" })
    }

    @Test func findsCarbonBurning() throws {
        let ds = index.datasets(for: try Reaction(notation: "12C(12C,a)20Ne"))
        #expect(!ds.isEmpty)
        #expect(ds.allSatisfy { $0.directory.hasPrefix("ion/C-12/C-12/a") })
        #expect(ds.first?.channel.label == "(¹²C,α)")
    }

    @Test func elasticMapsToElAndInl() throws {
        #expect(ExforChannel.outgoingCodes(try Reaction(notation: "12C(p,p)12C")) == ["el", "inl"])
        #expect(ExforChannel.outgoingCodes(try Reaction(notation: "6Li(p,3He)4He")) == ["he3", "h"])
        #expect(ExforChannel.outgoingCodes(try Reaction(notation: "13C(a,n)16O")) == ["n"])
    }

    @Test func channelsOfN14() throws {
        let n14 = try #require(MassTable.ame2020.nuclide(named: "14N"))
        let channels = index.channels(target: n14)
        #expect(channels.first?.channel.projectile == "p")
        let pg = try #require(channels.first { $0.channel.label == "(p,γ)" })
        #expect(pg.datasets.contains { $0.entry == "F0810" })
        // newest first
        #expect(zip(pg.datasets, pg.datasets.dropFirst()).allSatisfy { $0.year >= $1.year })
    }

    @Test(arguments: [
        // 3 fields (no product), author with a space and a hyphen
        ("ion/Ag-107/C-12/f", "Ag-107_6-c-12-f_Kuen-Bey Chen-A0592-002-0-1994.txt", "Kuen-Bey Chen", "A0592", nil as String?),
        // isomer label with "/" inside the product
        ("a/Pt-195/a-x", "Pt-195_a-x_Au-196-M2/T_N.Otuka-E2811-011-2-2025.txt", "N.Otuka", "E2811", "Au-196-M2/T"),
        ("p/N-14/p-inl-L9", "N-14_p-inl-L9_N-14_T.H.Curtis-D5055-026-0-1971.txt", "T.H.Curtis", "D5055", "N-14"),
    ])
    func parsesFileNames(dir: String, file: String, author: String, entry: String, product: String?) throws {
        let d = try #require(ExforDataset(directory: dir, fileName: file))
        #expect(d.author == author)
        #expect(d.entry == entry)
        #expect(d.product == product)
        #expect(d.path == dir + "/xs/" + file)
    }

    @Test func projectileNuclides() throws {
        let tab = MassTable.ame2020
        for (code, z, a) in [("p", 1, 1), ("d", 1, 2), ("t", 1, 3), ("h", 2, 3), ("a", 2, 4), ("C-12", 6, 12), ("O-16", 8, 16)] {
            let n = try #require(ExforChannel(projectile: code, target: "C-12", outgoing: "g").projectileNuclide(in: tab))
            #expect(n.z == z && n.a == a)
        }
        let c12 = try #require(tab.nuclide(named: "12C"))
        let ch = try #require(ExforChannel(projectile: "a", target: "C-12", outgoing: "g").entranceChannel(target: c12))
        #expect(ch.z1 == 2 && ch.z2 == 6)
    }

    @Test func levelFromDirectoryAndCode() throws {
        let d = try #require(ExforDataset(directory: "p/N-14/p-inl-L9", fileName: "N-14_p-inl-L9_N-14_T.H.Curtis-D5055-026-0-1971.txt"))
        #expect(d.level == 9)
        #expect(d.outgoing == "inl")
        #expect(d.channel.label == "(p,p′)")
        #expect(d.exforID == "D5055-026")
    }

    @Test func rejectsMalformedNames() {
        #expect(ExforDataset(directory: "p/Al-27/p-g", fileName: "Al-27_p-g.txt") == nil)
        #expect(ExforDataset(directory: "n/Al-27/n-g", fileName: "Al-27_n-g_Al-28_X-12345-001-0-2000.txt") == nil)
        #expect(ExforDataset(directory: "p/Al-27/p-g", fileName: "Si-28_p-g_Si-29_X-12345-001-0-2000.txt") == nil)
    }

    @Test func urlIsPercentEncodedAndPinned() throws {
        let d = try #require(ExforDataset(directory: "ion/Ag-107/C-12/f", fileName: "Ag-107_6-c-12-f_Kuen-Bey Chen-A0592-002-0-1994.txt"))
        let url = ExforClient.url(for: d, commit: "abc").absoluteString
        #expect(url == "https://raw.githubusercontent.com/IAEA-NDS/exfortables_py/abc/ion/Ag-107/C-12/f/xs/Ag-107_6-c-12-f_Kuen-Bey%20Chen-A0592-002-0-1994.txt")
    }
}

@Suite("EXFOR tables")
struct ExforTableTests {
    @Test func parsesCrossSectionInBarn() throws {
        let t = try ExforTable.parse(fixture("exfor_al27pg_chakrabarty"))
        #expect(t.quantity == .crossSection && t.frame == .lab && t.qualifier == .value)
        #expect(t.points.count == 3)
        // First row: 7.9600E+00 MeV, 2.4200E-05 B ± 1.4000E-06 B; dE = 0 means not given.
        #expect(t.points[0].energy == 7960)
        #expect(t.points[0].energyUncertainty == nil)
        #expect(abs(t.points[0].value - 2.42e-5) < 1e-15)
        #expect(abs(t.points[0].uncertainty! - 1.4e-6) < 1e-15)
        #expect(t.firstAuthor == "D.R.Chakrabarty")
        #expect(t.reference == "(J,PR/C,95,014614,2017)")
        #expect(t.residual == "14-SI-28")
        #expect(t.levelEnergy == 0)
        #expect(t.entryID == "D6305-002-0 (entry-subentry-pointer)")
    }

    @Test func parsesSFactorInCentreOfMass() throws {
        let t = try ExforTable.parse(fixture("exfor_n14pg_formicola"))
        #expect(t.quantity == .sFactor && t.frame == .cm)
        #expect(t.points.count == 69)
        // 2.0880E-01 MeV ± 9.0000E-03 MeV, 4.3443E+02 b eV ± 4.1176E+02 b eV
        #expect(abs(t.points[0].energy - 208.8) < 1e-9)
        #expect(abs(t.points[0].energyUncertainty! - 9) < 1e-9)
        #expect(abs(t.points[0].value - 0.43443) < 1e-12)
        #expect(abs(t.points[0].uncertainty! - 0.41176) < 1e-12)
    }

    @Test func dropsNaNRows() throws {
        let t = try ExforTable.parse(fixture("exfor_n14px_sah_nan"))
        #expect(t.points.count == 1)
        #expect(t.missingValues == 5)
        #expect(abs(t.points[0].value - 4.6e-3) < 1e-15)
    }

    @Test func convertsSFactorToCrossSectionAndBack() throws {
        let t = try ExforTable.parse(fixture("exfor_n14pg_formicola"))
        let tab = MassTable.ame2020
        let c = ChargedChannel(projectile: try #require(tab.nuclide(named: "p")), target: try #require(tab.nuclide(named: "14N")))
        let sigmaLab = t.points(as: .crossSection, frame: .lab, channel: c)
        #expect(sigmaLab.count == t.points.count)
        // σ from the existing S → σ conversion at the same c.m. energy
        let p0 = t.points[0]
        #expect(abs(sigmaLab[0].value / c.crossSection(sFactor: p0.value, energy: p0.energy) - 1) < 1e-12)
        #expect(abs(sigmaLab[0].energy - c.labEnergy(cm: p0.energy)) < 1e-9)
        // relative uncertainty is kept
        #expect(abs(sigmaLab[0].uncertainty! / sigmaLab[0].value - p0.uncertainty! / p0.value) < 1e-12)
        // round trip
        let back = ExforTable(quantity: .crossSection, frame: .lab, qualifier: .value, points: sigmaLab, missingValues: 0,
                              title: "", reactionCode: "", residual: "", levelEnergy: nil, firstAuthor: "", year: "",
                              reference: "", institute: "", facility: "", entryID: "")
            .points(as: .sFactor, frame: .cm, channel: c)
        for (a, b) in zip(back, t.points) {
            #expect(abs(a.value / b.value - 1) < 1e-9)
            #expect(abs(a.energy / b.energy - 1) < 1e-12)
        }
    }

    @Test(arguments: [("B", 1.0), ("MB", 1e-3), ("MICRO-B", 1e-6), ("NB", 1e-9)])
    func crossSectionUnits(unit: String, barn: Double) throws {
        let (q, f) = try ExforTable.dataUnit(unit)
        #expect(q == .crossSection && f == barn)
    }

    @Test func sFactorUnits() throws {
        #expect(try ExforTable.dataUnit("B*EV") == (.sFactor, 1e-3))
        #expect(try ExforTable.dataUnit("B*MEV") == (.sFactor, 1e3))
        #expect(try ExforTable.dataUnit("MB*KEV") == (.sFactor, 1e-3))
        #expect(throws: ExforTable.ParseError.self) { try ExforTable.dataUnit("ARB-UNITS") }
    }
}

/// Downloads from GitHub; run with `GAMOW_NETWORK_TESTS=1 ./Tools/test.sh`.
@Suite("EXFOR download", .enabled(if: ProcessInfo.processInfo.environment["GAMOW_NETWORK_TESTS"] == "1"))
struct ExforDownloadTests {
    @Test func downloadsAndCachesPinnedTable() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("exfor-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: cache) }
        let client = ExforClient(cacheDirectory: cache)
        let d = try #require(ExforIndex.bundled.datasets(for: try Reaction(notation: "27Al(p,g)28Si"))
            .first { $0.entry == "D6305" && $0.directory == "p/Al-27/p-g" })
        #expect(await !client.isCached(d))
        let text = try await client.text(d)
        #expect(text == (try fixture("exfor_al27pg_chakrabarty")))
        #expect(await client.isCached(d))
        // A file name with a space must survive the percent encoding.
        let space = try #require(ExforDataset(directory: "a/Ni-58/a-p", fileName: "Ni-58_a-p_Cu-61_Abhishek Yadav-D6067-002-0-2008.txt"))
        #expect(ExforIndex.bundled.allDatasets().contains(space))
        #expect(try await client.table(space).points.count > 0)
    }
}

@Suite("EXFOR S(0) rows")
struct ExforZeroEnergyTests {
    @Test func zeroEnergyRowsAreKeptButNotConverted() throws {
        let text = """
        #   Reference:  (J,TEST,1,1,2000)
        #    E_in_cm(MeV)     dE_in_cm(MeV)        data(B*EV)       ddata(B*EV)
                0.0000E+00        0.0000E+00        1.6100E+03        1.7000E+02
                1.0000E-01        0.0000E+00        1.7000E+03        1.0000E+02
        """
        let t = try ExforTable.parse(text)
        #expect(t.points.count == 2)
        #expect(t.zeroEnergyPoints.count == 1)
        #expect(t.zeroEnergyPoints[0].value == 1.61)
        let tab = MassTable.ame2020
        let c = ChargedChannel(projectile: try #require(tab.nuclide(named: "p")), target: try #require(tab.nuclide(named: "14N")))
        #expect(t.points(as: .crossSection, frame: .lab, channel: c).count == 1)
        #expect(t.points(as: .sFactor, frame: .cm, channel: c).count == 1)
    }
}

/// Answers every request with a fixture after a delay, and counts the requests.
private final class SlowFixtureProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@Suite("EXFOR client", .serialized)
struct ExforClientTests {
    /// SwiftUI cancels a view's task when the view disappears; that must not turn a download into an error.
    @Test func cancellingTheCallerDoesNotAbortTheDownload() async throws {
        SlowFixtureProtocol.body = Data(try fixture("exfor_al27pg_chakrabarty").utf8)
        SlowFixtureProtocol.requests = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SlowFixtureProtocol.self]
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("exfor-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: cache) }
        let client = ExforClient(session: URLSession(configuration: config), cacheDirectory: cache, commit: "test")
        let d = try #require(ExforDataset(directory: "p/Al-27/p-g", fileName: "Al-27_p-g-L0_Al-27_D.R.Chakrabarty-D6305-002-0-2017.txt"))

        let first = Task { try await client.text(d) }
        try await Task.sleep(for: .milliseconds(50))      // the download is running
        first.cancel()
        let second = try await client.text(d)              // joins the same download
        #expect(try await first.value == second)           // the cancelled caller still gets the table
        #expect(second.contains("D.R.Chakrabarty"))
        #expect(SlowFixtureProtocol.requests == 1)
        #expect(await client.isCached(d))
    }
}
