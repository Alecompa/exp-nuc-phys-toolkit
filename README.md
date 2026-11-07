# Gamow — a pocket toolkit for experimental nuclear astrophysics

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS%2026-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20Liquid%20Glass-purple)
![Tests](https://img.shields.io/badge/tests-55%20passing-brightgreen)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

Gamow is a native iPhone and iPad app for the numbers an experimental nuclear physicist needs at the
accelerator, in the counting room or in a meeting: Q values and kinematics, SRIM stopping powers through target
stacks, Gamow windows, S factors and reaction rates, beam-time estimates, detector response, calibration sources
and nuclear data. It works offline, keeps a notebook of saved calculations, and has no account, tracking or ads.

<p align="center">
  <img src="docs/screenshots/tools.png" width="200" alt="Tools home with the current reaction setup">
  <img src="docs/screenshots/kinematics.png" width="200" alt="Relativistic kinematics with an interactive chart">
  <img src="docs/screenshots/yield.png" width="200" alt="Yield and beam-time estimator">
  <img src="docs/screenshots/nuclide.png" width="200" alt="Nuclide page with ENSDF levels">
</p>

## Features

One reaction setup (for example `27Al(p,g)28Si` at 1400 keV) is shared by all tools, so changing the beam energy or
the target updates every screen.

| Area | Tools |
|---|---|
| **Reactions** | Q value with AME2020 uncertainty, threshold, Q to excited states · relativistic two-body kinematics (both branches, lab ↔ c.m., recoil, Jacobian, CSV table) · Rutherford cross section and monitor counts · γ Doppler shift and broadening over the detector opening angle |
| **Stopping & targets** | SRIM-2013 stopping powers (Swift port of LunaSRIM), ranges and straggling · any composition from a formula (`Ta2N5`, `Ca(OH)2`, `TiD2`, `Ta2[17O]5`) or the SRIM compound library, gases from pressure and temperature · layer stacks with energy loss, straggling and mean energy in the target |
| **Nuclear astrophysics** | Gamow peak and window vs T₉ · S factor ↔ σ with electron screening · resonance strength ↔ thick-target yield · Nₐ⟨σv⟩ from a polynomial or tabulated S(E) plus narrow resonances (CSV import/export) · Coulomb penetrability, shift factor, Wigner limit, θ² |
| **Run planning** | Yield, count rate and beam time for a target statistical uncertainty, with background and the Currie detection limit · beam current ↔ particles/s, charge state, power on target, integrated charge |
| **Detectors & sources** | HPGe/scintillator resolution model · weighted efficiency-curve fit to your calibration points · calibration sources: activity today with uncertainty, γ lines with expected counts, air-kerma rate · decay calculator (activity, atoms, mass, time to a fraction) |
| **Reference** | CODATA 2018 constants · unit converter (energy, T₉ ↔ kT, barns, lengths, areal density, activity, time, charge) · formula sheet |
| **Nuclides** | AME2020 masses and separation energies · NUBASE2020 half-lives, Jπ, decay modes, abundances, isomers · ENSDF levels and γ rays from the IAEA LiveChart, cached for offline use |
| **Notebook** | Save any tool's inputs and results with a note; search; export as CSV, PDF or text |
| **System** | Shortcuts / Siri actions (Q value, Gamow peak, source activity, half-life) · Home and Lock Screen widget for a source's activity today |

<p align="center">
  <img src="docs/screenshots/detector.png" width="200" alt="Detector response model">
  <img src="docs/screenshots/notebook.png" width="200" alt="Notebook of saved calculations">
</p>

## Install on your iPhone

You need a Mac with Xcode 26 and, for a free install, just an Apple ID.

```bash
git clone https://github.com/Alecompa/exp-nuc-phys-toolkit.git
```

```bash
open exp-nuc-phys-toolkit/Gamow.xcodeproj
```

1. Xcode ▸ Settings ▸ Accounts: add your Apple ID.
2. Select the **Gamow** and **GamowWidgets** targets ▸ Signing & Capabilities ▸ choose your team. If the bundle
   identifier is taken, change the prefix (`com.yourname.gamow`, `com.yourname.gamow.widgets`).
3. Connect the iPhone, enable Developer Mode on it, pick it as the run destination and press ⌘R.

With a free account the app has to be reinstalled every 7 days. [docs/release.md](docs/release.md) covers
TestFlight and the App Store.

## Project layout

| Path | Contents |
|---|---|
| `Packages/NucToolkit/Sources/NucPhysKit` | Physics only, no UI: masses, reactions, kinematics, `Stopping/` (SRIM-2013), `Astro/` (Coulomb functions, Gamow window, rates), `NuclearData/` (NUBASE, decay, LiveChart client), `RunPlanning/` (beam, statistics, detectors) |
| `Packages/NucToolkit/Sources/ToolkitUI` | All SwiftUI screens |
| `Packages/NucToolkit/Tests/NucPhysKitTests` | Swift Testing suite: Q values against AME2020, kinematics conservation, 24 SRIM SR-module reference cases, Coulomb functions against mpmath, Gamow peak, rate formulae, NUBASE, decay, efficiency fit |
| `App/` | `@main` app target and the App Intents (Shortcuts) |
| `Widgets/` | Widget extension |
| `Data/` | Source tables: AME2020, NUBASE2020, SRIM-2013 data, raw IAEA LiveChart decay data |
| `Tools/` | Converters that build the bundled data, icon generator, test scripts |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec; run `xcodegen generate` after editing it |

## Development

Run the physics tests on the Mac (needs Xcode, not only the Command Line Tools):

```bash
./Tools/test.sh
```

Regenerate the Xcode project after changing `project.yml`:

```bash
xcodegen generate
```

The bundled data are built from `Data/` by the scripts in `Tools/`, for example:

```bash
python3 -I Tools/convert_ame2020.py Data/mass_1.mas20.txt Packages/NucToolkit/Sources/NucPhysKit/Resources/ame2020.csv
```

```bash
python3 -I Tools/convert_nubase.py Data/nubase_4.mas20.txt Packages/NucToolkit/Sources/NucPhysKit/Resources/nubase2020.csv
```

```bash
python3 -I Tools/fetch_sources.py Data/LiveChart Packages/NucToolkit/Sources/NucPhysKit/Resources/calibration_sources.json --offline
```

```bash
python3 -I Tools/convert_srim.py Data/SRIM2013 Packages/NucToolkit/Sources/NucPhysKit/Resources Packages/NucToolkit/Tests/NucPhysKitTests/Resources
```

Planned work is tracked in [ROADMAP.md](ROADMAP.md).

## Conventions

- Energies are in keV internally; the display unit (keV or MeV) is a setting. Lab energies unless marked c.m.
- Q values come from AME2020 atomic mass excesses; uncertainties are added in quadrature (AME correlations neglected).
- Kinematics is fully relativistic and uses ion masses (atomic mass − Z·mₑ), so the kinematic and tabulated Q agree.
- Stopping powers follow SRIM-2013 as reconstructed by LunaSRIM: SR-module values for tables and ranges, energy
  loss by RK4 integration of dE/dx with TRIM's straggling model.
- Astrophysics: centre-of-mass energies, reduced masses in u, kT = 86.173 keV · T₉, S in keV b, ωγ and widths in eV,
  rates in cm³ mol⁻¹ s⁻¹ (bare, no stellar screening). Thick-target yields use the stopping per active nucleus,
  ε_eff = ε_compound / (element atom fraction × isotopic abundance).
- Run planning: thick-target yields integrate σ(E)/ε(E) over the target layer; counting times use
  t = (S + kB)/(S²u²); detection limits follow Currie. Dose rates are unshielded air kerma from NUBASE/ENSDF lines.

Results are meant for planning and teaching. Check numbers that matter for an experiment, a safety assessment or a
publication against the primary references.

## Data sources and credits

| Data | Reference | Terms |
|---|---|---|
| Atomic masses | AME2020, M. Wang et al., Chin. Phys. C 45, 030003 (2021) | Published evaluation (AMDC) |
| Half-lives, Jπ, isomers | NUBASE2020, F. G. Kondev et al., Chin. Phys. C 45, 030001 (2021) | Published evaluation (AMDC) |
| Levels, γ rays, decay radiations | ENSDF via the [IAEA LiveChart of Nuclides](https://www-nds.iaea.org/relnsd/vcharthtml/VChartHTML.html) | Public nuclear data |
| Stopping powers | SRIM-2013, J. F. Ziegler, M. D. Ziegler, J. P. Biersack, NIM B 268, 1818 (2010) | **Non-commercial use only** |
| Stopping code | [LunaSRIM](https://github.com/skowrons94/LunaSRIM) by J. Skowronski, ported to Swift | MIT (`Data/SRIM2013/LunaSRIM-LICENSE`) |
| Air μ_en/ρ | J. H. Hubbell and S. M. Seltzer, NISTIR 5632 | Public domain |
| Constants | CODATA 2018 | Public domain |

Because the SRIM data may only be used non-commercially, Gamow is and will stay free.

## License

The code is released under the [MIT License](LICENSE). The bundled data keep their own terms (see the table
above and [NOTICE](NOTICE)): in particular the SRIM-2013 data are for non-commercial use only, so builds that include them must stay free.

## Privacy

Gamow collects no data. The only network request goes to the IAEA Nuclear Data Section to fetch the level scheme of
the nuclide you open. See [docs/privacy.md](docs/privacy.md).
