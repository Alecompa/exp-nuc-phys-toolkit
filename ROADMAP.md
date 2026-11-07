# Gamow — roadmap

Gamow is an iOS/iPadOS toolkit for experimental nuclear (astro)physicists. This file is the single place where
planned work is tracked: tick items as they land, and note decisions that are not obvious from the code.

Status: `[x]` done · `[~]` in progress · `[ ]` planned

## Overview

| Milestone | Scope | Status |
|---|---|---|
| 1 | Core: masses, Q values, relativistic kinematics, app shell | ✅ done (accessibility pass and device testing open) |
| 2 | Stopping powers and targets (LunaSRIM port, compounds, layer stacks) | ✅ done (CAB correction, exit-path loss, target profiles open) |
| 3 | Nuclear astrophysics (Gamow window, S factor, resonances, rates, penetrabilities) | ✅ done (broad resonances, rate uncertainties, stellar screening open) |
| 4 | Run planning, detectors, sources | ✅ done |
| 5 | Data and productivity (NUBASE, ENSDF, notebook, exports, reference, Shortcuts, widget) | ✅ done (iPad pass, Mac, iCloud open) |
| 6 | Release: first TestFlight / App Store version | ⏳ next |
| 7 | Ideas for later | 💡 open |

## Milestone 1 — Core (Q-value + kinematics)

- [x] `NucPhysKit` Swift package, independent of UI, tested on macOS
- [x] AME2020 atomic mass table bundled (`Data/mass_1.mas20.txt` → `ame2020.csv` via `Tools/convert_ame2020.py`)
- [x] Nuclide / reaction notation parser (`12C(p,g)13N`, `3He(a,g)`, `d(p,g)`, residual inferred)
- [x] Q-value with uncertainty, threshold (relativistic), Q to an excited final state
- [x] Relativistic two-body kinematics: both solutions, lab↔CM, recoil, Jacobian, max angle, photon (Doppler) ejectile
- [x] Compound-nucleus excitation energy for capture reactions
- [x] SwiftUI app shell: tabs (Tools, Nuclides, Settings), shared reaction setup
- [x] Q-value screen, kinematics screen with interactive chart
- [x] Xcode project via XcodeGen; builds against the iOS 27.2 SDK with no warnings
- [x] Run on the iOS Simulator and polish the design from screenshots (light + dark; normal and inverse kinematics)
- [ ] Accessibility pass: Dynamic Type up to AX5, VoiceOver on chart and angle control, Reduce Transparency / Increase Contrast
- [ ] Test on a physical device (launch time, haptics, keyboard); the simulator debug build lags 1–3 s
- [x] App icon v1 (`Tools/make_icon.swift`, light + dark); revisit with Icon Composer layers

## Milestone 2 — Stopping power & targets (LunaSRIM port)

Source: <https://github.com/skowrons94/LunaSRIM> (MIT code; SRIM data files under
Ziegler's non-commercial terms → app stays free / non-commercial, credit SRIM).

- [x] Port `stopping.py` (electronic + nuclear stopping, SCOEF03/SNUC03) to Swift (`NucPhysKit/Stopping`)
- [x] Compound targets (Bragg additivity, user-set Bragg correction, the 356-entry `Compound.dat` library), gas targets
- [x] Arbitrary compositions: chemical-formula parser (`Ta2N3`, `Ca(OH)2`, `CuSO4·5H2O`, `Ti0.5Al0.5N`, `TiD2`, `Ta2[17O]5`), per-element stoichiometry editor, dictionary density lookup
- [ ] SRIM's core-and-bond (CAB) correction derived from the `Compound.dat` bond lines. Blocked: the core and bond stopping contributions live inside SRIM's executables, not its data files, and LunaSRIM does not reconstruct them; needs the Ziegler–Manoyan (NIM B 35, 215 (1988)) tables
- [x] Energy loss through a single layer (RK4), energy straggling (TRIM model + Bohr), tilted layers
- [x] Layer stacks (windows/dead layers in front, backing behind), per-layer energies, energy spread carried from layer to layer, stack chart
- [x] Range and range straggling (SR module moment integration)
- [x] Validate against LunaSRIM's 24 SR reference cases (`tests/reference_sr`), plus its energy-loss table
- [x] Target converters: thickness ↔ µg/cm² ↔ 10¹⁵ atoms/cm², stoichiometry, density
- [x] Gas pressure + temperature (+ atoms per molecule) → density; the cell length is the layer thickness → areal density
- [x] Effective energy in a target (path-averaged), E_cm and compound Eₓ, "use as beam energy"
- [x] Feed the mean energy in the target layer into the kinematics and Q-value screens (switch)
- [x] Stopping-power (log–log, electronic/nuclear) and energy-vs-depth (±σ band) charts
- [x] Stopping-power and range table export (CSV, share sheet)
- [ ] Ejectile energy loss on the way out of the target (exit path at the detector angle)
- [ ] Target profile from a thick-target yield step (resonance scan → thickness)

## Milestone 3 — Nuclear astrophysics tools

- [x] Gamow peak & window vs T₉ (integrand + band charts, stellar-site presets); Sommerfeld parameter; Coulomb barrier
- [x] Coulomb penetrability and shift factor P_ℓ, S_ℓ (F, G by inward RK4 from WKB waves; matches mpmath to ~1e-5 in ln P, deep under the barrier)
- [x] S-factor ↔ cross section, with the electron-screening enhancement exp(πηU_e/E)
- [x] Narrow resonance: thick-target yield ↔ ωγ (ε_eff per active nucleus from the SRIM target and isotopic abundance); ωγ from J, j₁, j₂ and widths; rate contribution
- [x] Rate N_A⟨σv⟩ vs T₉: numerical integration of a polynomial or tabulated S(E) (paste or import CSV/text) plus narrow resonances; rate chart, table and CSV export
- [x] Wigner limit, single-particle width, Γ ↔ γ² ↔ θ² at a channel radius (r₀ or fixed), entrance or exit channel
- [x] Rutherford cross section (lab & CM, both solutions for heavy projectiles) and monitor counts per µC from the target layer
- [ ] Broad resonances (Breit–Wigner with energy-dependent widths) in the rate integral
- [ ] Rate uncertainties (Monte Carlo over S and ωγ, lognormal), REACLIB fit of the rate
- [ ] Stellar screening (weak/intermediate) and the stellar enhancement factor

## Milestone 4 — Run planning, detectors, sources ✓

- [x] Yield / count rate / beam-time estimator (S factor over the target, σ or resonance; efficiency, current, background, Currie limit)
- [x] Beam units: µA ↔ pps for a charge state; integrated charge → particles; power density
- [x] Gamma Doppler shift & broadening for finite detector opening angle
- [x] Calibration-source activity today (certificate date, NUBASE half-life, uncertainty incl. half-life)
- [x] Decay calculator; air-kerma rate at a distance (NIST μ_en/ρ)
- [x] HPGe/scintillator resolution model; weighted ln–ln polynomial efficiency fit
- [ ] Later: true-coincidence summing, efficiency transfer between geometries, H*(10) instead of air kerma

## Milestone 5 — Data & productivity ✓

- [x] NUBASE2020: half-lives, spins/parities, decay modes, abundances, isomers in the Nuclides tab
- [x] Levels and gamma lines from IAEA LiveChart API (online, cached 30 days, offline fallback, CSV export)
- [x] Notebook tab: saved calculations (SwiftData) from every tool, notes, search, CSV/PDF/text export
- [x] Kinematics table export (CSV), copy values (touch and hold any result)
- [x] Unit converter, constants reference, formula sheet
- [x] Shortcuts (Q value, Gamow peak, source activity, half-life); source-activity widget (Home and Lock Screen)
- [x] Release basics: automatic signing, export-compliance key, About/licences/privacy screens, docs/release.md
- [ ] iPad polish, Mac and iCloud: moved to milestones 6 and 7

## Milestone 6 — First public release

- [ ] Test on physical iPhones and iPads: launch time, memory, haptics, keyboard, widget refresh
- [ ] Accessibility pass (Dynamic Type to AX5, VoiceOver for charts and controls, Reduce Transparency / Increase Contrast)
- [ ] iPad: every tool in the sidebar layout at all window sizes; keyboard shortcuts for the common tools
- [ ] Localisation of units and number formats (decimal comma) checked in all inputs
- [ ] App Store assets: screenshots (6.9" iPhone, 13" iPad), description, privacy URL, support page
- [ ] TestFlight beta with colleagues; collect feedback in GitHub issues

## Milestone 7 — Ideas for later

### Reactions and targets

- [ ] Ejectile energy loss on the way out of the target and through detector dead layers
- [ ] Target profile and thickness from a resonance scan (thick-target yield step fit)
- [ ] Target degradation from accumulated charge (yield vs charge)
- [ ] Angular distributions: Legendre sums, attenuation coefficients Q_k for a finite detector

### Astrophysics

- [ ] Broad resonances (Breit–Wigner with energy-dependent widths) and interference in the rate integral
- [ ] Rate uncertainties by Monte Carlo (lognormal), REACLIB 7-parameter fit and export
- [ ] Stellar screening and stellar enhancement factor; inverse rates by detailed balance
- [ ] Import S-factor data from EXFOR for comparison plots

### Detectors and data

- [ ] True-coincidence summing corrections from the decay scheme and peak/total efficiency
- [ ] Efficiency transfer between source geometries; H*(10) dose rates and simple shielding
- [ ] Spectrum viewer for exported histograms (peak position, FWHM, area)
- [ ] Notebook in iCloud (CloudKit) and a widget listing the user's saved sources (needs an App Group)
- [ ] Native macOS version (the app already runs as "Designed for iPad" on Apple silicon)

## Design principles (from Apple HIG + apple-design skills)

- Liquid Glass only in the functional layer (tab bar, toolbars, floating controls); never on cards/rows.
- System text styles + Dynamic Type; monospaced/rounded digits for results; verify at AX5.
- At most one tinted (prominent) action per view; brand colour lives in the content layer.
- Springs: critically damped by default; numeric content transitions for changing values.
- Haptics only on meaningful events (preset chosen, value snapped), never continuous.
- Reduce Motion / Reduce Transparency / Increase Contrast must all look right.
