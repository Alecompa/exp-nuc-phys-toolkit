import NucPhysKit
import SwiftUI

struct AboutView: View {
    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(LinearGradient(colors: [Color(red: 0.35, green: 0.07, blue: 0.2), .accent],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    Text("Gamow").font(.title.weight(.bold))
                    Text("Version \(Self.version)").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }
            Section {
                Text("A pocket toolkit for experimental nuclear physics and nuclear astrophysics: reaction Q values and kinematics, SRIM stopping powers and target stacks, Gamow windows, S factors, resonance strengths and reaction rates, run planning, detectors, calibration sources and nuclear data.")
                    .font(.subheadline)
            }
            Section("Conventions") {
                LabeledContent("Energies", value: "keV, lab unless marked c.m.")
                LabeledContent("Kinematics", value: "Relativistic, ion masses")
                LabeledContent("Rates", value: "Nₐ⟨σv⟩, cm³ mol⁻¹ s⁻¹")
                LabeledContent("Q uncertainties", value: "AME, in quadrature")
            }
            Section {
                Text("Results are for planning and education. Check numbers that matter for an experiment, a safety assessment or a publication against the primary references; dose rates are no substitute for a survey meter.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .groupedList()
        .navigationTitle("About")
        .inlineTitle()
    }
}

struct LicencesView: View {
    private struct Source: Identifiable {
        let name: String
        let detail: String
        let licence: String
        let url: String
        var id: String { name }
    }

    private let sources: [Source] = [
        .init(name: "AME2020 atomic masses",
              detail: "M. Wang et al., Chin. Phys. C 45, 030003 (2021)",
              licence: "Published evaluation, distributed by the AMDC (IAEA/IMP). Cite when used.",
              url: "https://doi.org/10.1088/1674-1137/abddaf"),
        .init(name: "NUBASE2020 nuclear properties",
              detail: "F. G. Kondev et al., Chin. Phys. C 45, 030001 (2021)",
              licence: "Published evaluation, distributed by the AMDC. Cite when used.",
              url: "https://doi.org/10.1088/1674-1137/abddae"),
        .init(name: "ENSDF via the IAEA LiveChart of Nuclides",
              detail: "Levels, γ rays and decay radiations; Evaluated Nuclear Structure Data File (NNDC/IAEA)",
              licence: "Public nuclear data; retrieved from the IAEA API. Cite the ENSDF evaluation shown with the data.",
              url: "https://www-nds.iaea.org/relnsd/vcharthtml/VChartHTML.html"),
        .init(name: "EXFOR experimental nuclear reaction data",
              detail: "N. Otuka et al., Nucl. Data Sheets 120, 272 (2014). Tables from IAEA-NDS/exfortables_py (S. Okumura, G. Schnabel, A. Koning, IAEA)",
              licence: "exfortables_py and the index of it bundled in Gamow: Creative Commons Attribution-ShareAlike 4.0. Cite the original measurement shown with each table.",
              url: "https://doi.org/10.1016/j.nds.2014.07.065"),
        .init(name: "SRIM-2013 stopping powers",
              detail: "J. F. Ziegler, M. D. Ziegler, J. P. Biersack, Nucl. Instrum. Methods B 268, 1818 (2010)",
              licence: "SRIM is free for non-commercial use. For this reason Gamow is, and stays, free.",
              url: "http://www.srim.org"),
        .init(name: "LunaSRIM",
              detail: "J. Skowronski: Python implementation of the SRIM stopping module, ported to Swift",
              licence: "MIT License",
              url: "https://github.com/skowrons94/LunaSRIM"),
        .init(name: "NIST X-ray mass energy-absorption coefficients",
              detail: "J. H. Hubbell and S. M. Seltzer, NISTIR 5632 (air, for dose rates)",
              licence: "US Government work, public domain.",
              url: "https://physics.nist.gov/PhysRefData/XrayMassCoef/"),
        .init(name: "CODATA 2018 constants",
              detail: "E. Tiesinga et al., Rev. Mod. Phys. 93, 025010 (2021)",
              licence: "Public domain (NIST).",
              url: "https://physics.nist.gov/cuu/Constants/"),
    ]

    var body: some View {
        List {
            ForEach(sources) { s in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.name).font(.body.weight(.semibold))
                        Text(s.detail).font(.subheadline).foregroundStyle(.secondary)
                        Text(s.licence).font(.footnote)
                    }
                    .padding(.vertical, 2)
                    if let url = URL(string: s.url) {
                        Link(destination: url) { Label("Open reference", systemImage: "arrow.up.right.square") }
                            .font(.callout)
                    }
                }
            }
            Section {
                Text("Coulomb penetrabilities are computed by integrating the Coulomb equation inward from WKB solutions, checked against mpmath. Astrophysics conventions follow C. Iliadis, Nuclear Physics of Stars (Wiley, 2015).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .groupedList()
        .navigationTitle("Data & Licences")
        .inlineTitle()
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Label("No account, no tracking, no analytics, no ads.", systemImage: "hand.raised.fill")
                Label("Your inputs, sources and notebook stay on this device.", systemImage: "iphone")
                Label("Network requests go to the IAEA Nuclear Data Section, for the level scheme of the nuclide you open, and to GitHub, for the EXFOR tables of the reaction you open. They contain the nuclide or table name and nothing about you.", systemImage: "network")
                Label("Files you export leave the device only through the share sheet, when you choose.", systemImage: "square.and.arrow.up")
            }
            .labelStyle(PrivacyLabelStyle())
            Section {
                Text("If iCloud device backup is on, iOS includes the app's data in your backup like any other app. Deleting the app deletes all its data.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .groupedList()
        .navigationTitle("Privacy")
        .inlineTitle()
    }
}

private struct PrivacyLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.icon.foregroundStyle(Color.accent).frame(width: 24)
            configuration.title
        }
        .padding(.vertical, 2)
    }
}

enum LiveChartCache {
    static func clear() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("LiveChart")
        try? FileManager.default.removeItem(at: dir)
    }
}
