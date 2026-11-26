import Foundation
import Testing
@testable import NucPhysKit

/// EXFOR reference values shared with the Kotlin port: `Shared/reference_exfor.json` (index lookups, file-name
/// grammar, URLs, parsed tables and σ ↔ S, lab ↔ c.m. conversions). This suite checks that the Swift code still
/// reproduces the file; the Kotlin test `ReferenceExforTest` reads the same file and must reproduce it too.
/// Regenerate after a deliberate change with `GAMOW_WRITE_REFERENCE=1 ./Tools/test.sh --filter ReferenceExfor`.
@Suite("Shared EXFOR reference values")
struct ReferenceExforTests {
    struct Point: Codable { var e: Double; var de: Double?; var v: Double; var dv: Double? }

    struct Dataset: Codable {
        var path, directory, fileName, projectile, target, outgoing, author, entry, subentry, pointer: String
        var level: Int?
        var product: String?
        var year: Int
        var exforID, exforURL, finalStateLabel, channelID, label, kind, url: String
    }

    struct Index: Codable {
        var commit, date: String
        var count, parsed, withLevel, withProduct, yearSum: Int
        var byProjectile: [String: Int]
    }

    struct ReactionCase: Codable {
        var reaction, projectileCode: String
        var outgoingCodes: [String]
        var swapped: String?
        var filedUnder: String?
        var paths: [String]
        var first: Dataset?
    }

    struct Channel: Codable {
        var id, label, projectileLabel, outgoingLabel, kind: String
        var projectileZ, projectileA: Int
        var paths: [String]
    }

    struct ChannelCase: Codable {
        var target: String
        var channels: [Channel]
    }

    struct NameCase: Codable {
        var directory, fileName: String
        var dataset: Dataset?
    }

    struct UnitCase: Codable {
        var unit: String
        var quantity: String?
        var factor: Double?
    }

    struct Conversion: Codable {
        var quantity, frame: String
        var points: [Point]
    }

    struct TableCase: Codable {
        /// File in Tests/NucPhysKitTests/Resources, or nil for `text`.
        var file: String?
        var text: String?
        var projectile, target: String
        var quantity, frame, qualifier: String
        var missing, zeroEnergy: Int
        var levelEnergy: Double?
        var title, reactionCode, residual, firstAuthor, year, reference, institute, facility, entryID: String
        var points: [Point]
        var conversions: [Conversion]
    }

    struct Reference: Codable {
        var index: Index
        var reactions: [ReactionCase]
        var channels: [ChannelCase]
        var names: [NameCase]
        var units: [UnitCase]
        var tables: [TableCase]
    }

    static let fileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Shared/reference_exfor.json")

    static let s0Table = """
    #   Reference:  (J,TEST,1,1,2000)
    #    E_in_cm(MeV)     dE_in_cm(MeV)        data(B*EV)       ddata(B*EV)
            0.0000E+00        0.0000E+00        1.6100E+03        1.7000E+02
            1.0000E-01        0.0000E+00        1.7000E+03        1.0000E+02
            5.0000E-02        1.0000E-03        1.6500E+03        1.2000E+02
    """

    static func dataset(_ d: ExforDataset) -> Dataset {
        Dataset(path: d.path, directory: d.directory, fileName: d.fileName, projectile: d.projectile, target: d.target,
                outgoing: d.outgoing, author: d.author, entry: d.entry, subentry: d.subentry, pointer: d.pointer,
                level: d.level, product: d.product, year: d.year, exforID: d.exforID, exforURL: d.exforURL.absoluteString,
                finalStateLabel: d.finalStateLabel, channelID: d.channel.id, label: d.channel.label, kind: d.channel.kind,
                url: ExforClient.url(for: d, commit: "f9c2d73f780b576cf1276b8e4018fddd1430fee8").absoluteString)
    }

    static func point(_ p: ExforTable.Point) -> Point {
        Point(e: p.energy, de: p.energyUncertainty, v: p.value, dv: p.uncertainty)
    }

    /// Channel order with ties (same projectile and number of tables) broken by id: Swift leaves ties in dictionary
    /// order, the Kotlin port breaks them by id.
    static func deterministic(_ c: [(channel: ExforChannel, datasets: [ExforDataset])]) -> [(channel: ExforChannel, datasets: [ExforDataset])] {
        let order = ["p": 0, "a": 1, "d": 2, "h": 3, "t": 4]
        return c.sorted {
            let a = order[$0.channel.projectile] ?? 9, b = order[$1.channel.projectile] ?? 9
            if a != b { return a < b }
            if $0.channel.projectile != $1.channel.projectile { return $0.channel.projectile < $1.channel.projectile }
            if $0.datasets.count != $1.datasets.count { return $0.datasets.count > $1.datasets.count }
            return $0.channel.id < $1.channel.id
        }
    }

    static func compute() throws -> Reference {
        let index = ExforIndex.bundled
        let tab = MassTable.ame2020
        let all = index.allDatasets().compactMap { $0 }
        let idx = Index(commit: index.commit, date: index.date, count: index.count, parsed: all.count,
                        withLevel: all.filter { $0.level != nil }.count, withProduct: all.filter { $0.product != nil }.count,
                        yearSum: all.reduce(0) { $0 + $1.year },
                        byProjectile: Dictionary(grouping: all, by: \.projectile).mapValues(\.count))

        let reactionNames = ["14N(p,g)15O", "12C(12C,a)20Ne", "7Be(p,g)8B", "p(7Be,g)8B", "3He(a,g)7Be", "27Al(p,g)28Si",
                             "13C(a,n)16O", "12C(p,p)12C", "6Li(p,3He)4He", "7Li(p,a)4He", "22Ne(a,n)25Mg", "12C(a,g)16O",
                             "d(p,g)3He", "p(12C,g)13N"]
        var reactions: [ReactionCase] = []
        for n in reactionNames {
            let r = try Reaction(notation: n)
            // As the EXFOR screen: normal kinematics first, then the swapped reaction for inverse kinematics.
            var found = index.datasets(for: r)
            var under: Reaction? = found.isEmpty ? nil : r
            if found.isEmpty, let s = r.swappedBeamAndTarget {
                let other = index.datasets(for: s)
                if !other.isEmpty { found = other; under = s }
            }
            reactions.append(ReactionCase(reaction: n, projectileCode: ExforChannel.projectileCode(r.projectile),
                                          outgoingCodes: ExforChannel.outgoingCodes(r),
                                          swapped: r.swappedBeamAndTarget?.plainLabel, filedUnder: under?.plainLabel,
                                          paths: found.map(\.path), first: found.first.map(dataset)))
        }

        var channels: [ChannelCase] = []
        for t in ["27Al", "14N", "7Be"] {
            let target = try #require(tab.nuclide(named: t))
            let raw = index.channels(target: target)
            let sorted = deterministic(raw)
            // Swift's own order agrees with the deterministic one up to ties.
            #expect(raw.map { "\($0.channel.projectile) \($0.datasets.count)" } == sorted.map { "\($0.channel.projectile) \($0.datasets.count)" })
            channels.append(ChannelCase(target: t, channels: try sorted.map { c in
                let p = try #require(c.channel.projectileNuclide(in: tab))
                #expect(index.datasets(for: c.channel, target: target).map(\.path) == c.datasets.map(\.path))
                return Channel(id: c.channel.id, label: c.channel.label, projectileLabel: c.channel.projectileLabel,
                               outgoingLabel: c.channel.outgoingLabel, kind: c.channel.kind, projectileZ: p.z, projectileA: p.a,
                               paths: c.datasets.map(\.path))
            }))
        }

        let nameCases: [(String, String)] = [
            ("ion/Ag-107/C-12/f", "Ag-107_6-c-12-f_Kuen-Bey Chen-A0592-002-0-1994.txt"),
            ("a/Pt-195/a-x", "Pt-195_a-x_Au-196-M2/T_N.Otuka-E2811-011-2-2025.txt"),
            ("p/N-14/p-inl-L9", "N-14_p-inl-L9_N-14_T.H.Curtis-D5055-026-0-1971.txt"),
            ("a/Ni-58/a-p", "Ni-58_a-p_Cu-61_Abhishek Yadav-D6067-002-0-2008.txt"),
            ("p/Al-27/p-g", "Al-27_p-g-L0_Al-27_D.R.Chakrabarty-D6305-002-0-2017.txt"),
            ("ion/C-12/C-12/a-L1", "C-12_C-12-a-L1_Ne-20_X.Test-A1234-002-0-2020.txt"),
            ("p/Li-6/p-he3", "Li-6_p-he3_He-4_A.B+C.D-C1234-002-0-1999.txt"),
            ("p/Al-27/p-g", "Al-27_p-g.txt"),
            ("n/Al-27/n-g", "Al-27_n-g_Al-28_X-12345-001-0-2000.txt"),
            ("p/Al-27/p-g", "Si-28_p-g_Si-29_X-12345-001-0-2000.txt"),
            ("p/Al-27/a-g", "Al-27_p-g_Si-28_X-12345-001-0-2000.txt"),
            ("p/Al-27/p-g", "Al-27_p-g_Si-28_X-1234-001-0-2000.txt"),
            ("p/Al-27/p-g", "Al-27_p-g_Si-28_X-12345-001-0-20x0.txt"),
        ]
        let names = nameCases.map { NameCase(directory: $0.0, fileName: $0.1, dataset: ExforDataset(directory: $0.0, fileName: $0.1).map(dataset)) }

        let units = ["B", "MB", "MICRO-B", "MUB", "UB", "NB", "PB", "b", "mb", "B*EV", "B*KEV", "B*MEV", "MB*KEV", "MUB*MEV",
                     "ARB-UNITS", "B*EV*EV", ""].map { u -> UnitCase in
            if let (q, f) = try? ExforTable.dataUnit(u) { return UnitCase(unit: u, quantity: q.rawValue, factor: f) }
            return UnitCase(unit: u, quantity: nil, factor: nil)
        }

        var tables: [TableCase] = []
        let sources: [(String?, String?, String, String)] = [
            ("exfor_al27pg_chakrabarty", nil, "p", "27Al"), ("exfor_n14pg_formicola", nil, "p", "14N"),
            ("exfor_n14px_sah_nan", nil, "p", "14N"), (nil, s0Table, "p", "14N"),
        ]
        for (file, inline, p, t) in sources {
            let text: String
            if let file {
                let url = try #require(Bundle.module.url(forResource: file, withExtension: "txt"))
                text = try String(contentsOf: url, encoding: .utf8)
            } else {
                text = inline!
            }
            let table = try ExforTable.parse(text)
            let c = ChargedChannel(projectile: try #require(tab.nuclide(named: p)), target: try #require(tab.nuclide(named: t)))
            var conv: [Conversion] = []
            for q in ExforTable.Quantity.allCases {
                for f in ExforTable.Frame.allCases {
                    conv.append(Conversion(quantity: q.rawValue, frame: f.rawValue,
                                           points: table.points(as: q, frame: f, channel: c).map(point)))
                }
            }
            tables.append(TableCase(file: file.map { $0 + ".txt" }, text: inline, projectile: p, target: t,
                                    quantity: table.quantity.rawValue, frame: table.frame.rawValue,
                                    qualifier: table.qualifier.rawValue, missing: table.missingValues,
                                    zeroEnergy: table.zeroEnergyPoints.count, levelEnergy: table.levelEnergy,
                                    title: table.title, reactionCode: table.reactionCode, residual: table.residual,
                                    firstAuthor: table.firstAuthor, year: table.year, reference: table.reference,
                                    institute: table.institute, facility: table.facility, entryID: table.entryID,
                                    points: table.points.map(point), conversions: conv))
        }
        return Reference(index: idx, reactions: reactions, channels: channels, names: names, units: units, tables: tables)
    }

    /// Recursive comparison of two JSON values: numbers to 1e-9 relative, everything else exactly.
    static func compare(_ a: Any, _ b: Any, _ path: String, _ problems: inout [String]) {
        switch (a, b) {
        case let (x as [String: Any], y as [String: Any]):
            if Set(x.keys) != Set(y.keys) { problems.append("\(path): keys \(x.keys.sorted()) vs \(y.keys.sorted())"); return }
            for k in x.keys.sorted() { compare(x[k]!, y[k]!, path + "." + k, &problems) }
        case let (x as [Any], y as [Any]):
            if x.count != y.count { problems.append("\(path): \(x.count) vs \(y.count) elements"); return }
            for i in x.indices { compare(x[i], y[i], path + "[\(i)]", &problems) }
        case let (x as String, y as String):
            if x != y { problems.append("\(path): \(x) vs \(y)") }
        case let (x as NSNumber, y as NSNumber):
            let u = x.doubleValue, v = y.doubleValue
            if !(abs(u - v) <= 1e-9 * max(1, abs(u))) { problems.append("\(path): \(u) vs \(v)") }
        default:
            problems.append("\(path): \(a) vs \(b)")
        }
    }

    @Test func swiftReproducesSharedFile() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let computed = try enc.encode(try Self.compute())
        if ProcessInfo.processInfo.environment["GAMOW_WRITE_REFERENCE"] == "1" {
            try computed.write(to: Self.fileURL)
        }
        let stored = try Data(contentsOf: Self.fileURL)
        var problems: [String] = []
        Self.compare(try JSONSerialization.jsonObject(with: stored), try JSONSerialization.jsonObject(with: computed), "$", &problems)
        #expect(problems.isEmpty, "\(problems.prefix(20))")
        // The file covers what the Kotlin port must reproduce.
        let ref = try JSONDecoder().decode(Reference.self, from: stored)
        #expect(ref.index.count == ref.index.parsed && ref.index.count > 50000)
        // p(¹²C,γ) is filed only in normal kinematics; p(⁷Be,γ) has inverse-kinematics tables of its own.
        #expect(ref.reactions.first { $0.reaction == "p(12C,g)13N" }?.filedUnder == "12C(p,g)13N")
        #expect(ref.reactions.first { $0.reaction == "p(7Be,g)8B" }?.filedUnder == "1H(7Be,g)8B")
        #expect(ref.tables.map(\.points.count) == [3, 69, 1, 3])
    }
}
