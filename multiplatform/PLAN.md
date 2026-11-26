# Android / Linux / Windows: plan to feature parity with the iOS app

Status on 2026-11-26 (updated): phases 1–3 are done (✅ below); phase 4 is mostly done; tests on real Linux, Windows and Android devices are still open. All physics is ported to Kotlin and checked against the Swift code through six shared
reference files (`Shared/reference_*.json`, about 1 600 cases and 26 000 values, 10⁻⁹ relative). The remaining work is
interface work on top of tested physics. This file tracks it; tick items as they land.

## Rules for every step

- **Physics stays shared.** Any physics a screen needs that is not in `org.gamow.core` is ported from Swift with a
  reference case added on the Swift side (`Reference*Tests.swift`, `GAMOW_WRITE_REFERENCE=1`) and reproduced by the
  Kotlin test. No formula is written only in a screen.
- **Screen pattern.** Answer first (hero value), then the two to four inputs that matter, then the plot; everything
  else in `MoreOptions` with a one-line summary. Choices from a list are pickers (`PickerField`, `NuclidePickerDialog`,
  `MaterialPickerDialog`, unit menus), never free text.
- **Done means:** compiles for desktop and Android, `desktopTest` green, a render in `RenderScreens` checked by eye,
  numbers spot-checked against the iOS app for one case, README status table updated.

## Phase 1: missing tools (physics already ported)

| # | Tool | Content | Core API | Effort |
|---|---|---|---|---|
| ✅ 1.1 | Rutherford scattering | dσ/dΩ lab and c.m. vs angle (both branches for heavy beams), monitor counts per µC from the target layer | `astro.RutherfordScattering`, `RunState` target | S |
| ✅ 1.2 | Gamma Doppler | shift and broadening at a detector angle and opening, capture primary or residual level as E₀ | `spectra.GammaDoppler`, `InBeamGamma` | S |
| ✅ 1.3 | Beam current | µA ↔ particles/s for a charge state, integrated charge → particles, power on target | `runplanning.Beam` | S |
| ✅ 1.4 | Detector response | resolution model (presets or own parameters), efficiency points table and ln–ln fit with χ², curve plot; the fitted curve replaces the example curve in Yield and Detector spectrum | `spectra.ResolutionModel`, `EfficiencyCurve` | M |
| ✅ 1.5 | Reference | CODATA constants, unit converter (energy, T₉ ↔ kT, barn, length, areal density, activity, time, charge), formula sheet | port `Reference` data from `ToolkitUI/Screens/Reference` | M |

## Phase 2: depth of existing tools

| # | Tool | Missing | Effort |
|---|---|---|---|
| ✅ 2.1 | Stopping & energy loss | layers before and after the target (windows, backings) with `LayerStack.transport`; gas targets from pressure, temperature and cell length (`GasTarget`); energy-vs-depth plot with ±σ band | M |
| ✅ 2.2 | EXFOR | per-table page (reference, institute, facility, final state, points table, link to the IAEA entry); “Use as S(E) in Reaction Rate”; on a nuclide page, every channel measured on it; CSV export of the shown data | M |
| ✅ 2.3 | Nuclides | ENSDF levels and γ rays from `LiveChartClient` (cached, offline fallback), level picker for the residual excitation in Setup | M |
| ✅ 2.4 | Calibration sources | dose rate (air kerma at a distance) — port `AirKerma` with reference cases | S |
| ✅ 2.5 | Resonance strength | ωγ from J, j₁, j₂ and partial widths (`NarrowResonance.spinFactor`, `strength`) | S |
| ✅ 2.6 | Notebook | CSV and text-file export through the platform share sheet / save dialog | S |

Phase 2 notes: Nuclides has level search and CSV copy; the EXFOR table page has its own plot.

## Phase 3: app-level features

| # | Feature | Content | Effort |
|---|---|---|---|
| ✅ 3.1 | Settings | keV/MeV display, thickness unit, EXFOR and LiveChart cache size and clearing, about/licences (SRIM non-commercial terms, EXFOR CC BY-SA, data references) | S |
| ✅ 3.2 | Experiments | named setups (reaction, energies, target, detector, spectrum settings) saved and restored; run log with charge and live time; JSON export compatible with the iOS `ExperimentSetup` format | M |
| ✅ 3.3 | Persistence of spectrum settings | `SpectrumState` (contaminants, sources, detector) survives restarts like the iOS `SpectrumSetup` | S |
| ✅ 3.4 | Tools home | pinned tools and search, as on iOS | S |

Phase 3 notes: the keV/MeV display switch of iOS is not ported (all screens show keV). Experiments import iOS
`ExperimentSetup` exports (tested with `Shared/sample_ios_experiment.json`) and write the shared fields under the same
keys; the iOS app has no import, so Android exports are read back by Android/desktop only. Target material and
detector settings stay per platform. Spectrum foils are
kept for the session only.

## Phase 4: release

| # | Item | Effort |
|---|---|---|
| ✅ 4.1 | GitHub workflow green on Linux (`.deb`), Windows (`.msi`), macOS (`.dmg`) and the APK job (commit 400e3bc). Still open: install the `.deb` on a Linux machine and the `.msi` on Windows | S–M |
| ◐ 4.2 | Android emulator (API 35, 1080×2400): APK installs and launches; Kinematics, Stopping, Detector spectrum and EXFOR (online download) open without crashes; Back works. Still open: a real phone, a small screen, the file picker, dark theme | S |
| ✅ 4.3 | Release signing from `keystore.properties` or `GAMOW_KEYSTORE*` environment variables, both gitignored (tested with a throwaway key). Versions: Android `versionName` 0.1.0 / `versionCode` 1, the same as iOS `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`; for now they are kept in step by hand | S |
| ✅ 4.4 | Accessibility: rows, the reaction header and plot margins reflow at 200 % font (desktop render test `largeFonts` and the emulator); screen-reader descriptions on plots, the pin and remove buttons, and the expand/collapse state of `MoreOptions` | M |

S ≈ under an hour, M ≈ a few hours. Phases 1 and 2 are one working session; 3 and 4 a second.

## Known items to watch

- The EXFOR table O2597-002 (¹²C(p,γ), Skowronski et al., PRC 107, L062801, 2023) is stored in EXFOR with MeV
  instead of keV energies; both apps show it as stored. To be reported to the IAEA NDS.
- Kotlin's error function is a port of fdlibm (no `erf` in common Kotlin); peak-area uncertainties are compared to 1 %
  and calibration residuals to 10⁻⁸ keV for that reason (`ReferenceSpectraTest`).
- Linux and Windows installers can only be built on those systems (Compose `jpackage`); the workflow does it.
