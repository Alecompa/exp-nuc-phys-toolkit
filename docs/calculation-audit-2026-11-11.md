# Calculation and workflow audit — 2026-11-11

Scope: target composition and yield inputs, gamma-spectrum response, plotting, shared setup
persistence and Notebook saves. This is a focused regression audit, not experimental validation of
every calculator or a replacement for detector calibration.

## Review findings and fixes

| Dimension | Assessment | Evidence and action |
|---|---|---|
| Correctness | Significant issues fixed | Thin-target areal density omitted the tilt factor; constant-σ yields ignored upstream stopping; plateau estimates ignored whether the resonance was crossed. Explicit target isotopes were combined by element. See `StoppingTarget.activeFraction/activeArealDensity`, `Workbench`, and `YieldEstimateView`. |
| Data reliability | Save behavior corrected | Notebook swallowed persistence errors and displayed success; multiline CSV values were not quoted. `Notebook.swift` now reports save errors and escapes line breaks. Zero beam current/energy survive reloading. |
| Performance | Plot workload reduced | Spectrum drawing uses a bounded extrema envelope, retaining narrow peaks. Full channels remain available for analysis and CSV. Existing cancelled/debounced spectrum calculations stay off the main actor. |
| Maintainability | Regression coverage expanded | Shared experiment snapshots have an explicit format version. Physics and workflow tests cover independent references, serialization, restoration and coexistence of Notebook/run records. |
| Security | No new issue found in inspected paths | Saved experiments are local SwiftData records; export is user initiated. This change adds no external upload or runtime data download. This is not a full security audit. |

Useful existing safeguards remain: reaction charge/mass-number conservation, AME2020 Q-value checks,
SRIM reference cases, Coulomb-function comparisons and EXFOR parsing tests. These support regression
testing while leaving the model assumptions visible.

## Numerical cross-checks

- **Compton shape:** an independent Python quadrature over one million uniform `cos(theta)` bins
  weights each by `k²(k + 1/k − sin²(theta))`, where `k = 1/[1 + E/(m_ec²)(1−cos(theta))]`.
  At 1000 keV, the continuum fractions below 100, 300 and 600 keV are respectively
  0.11768590492544741, 0.336624955465574 and 0.6535815585810707. The production implementation
  integrates in deposited energy, and agrees within 0.0003 absolute fraction for a narrow response.
  The formula is documented in the [Geant4 physics reference](https://geant4.web.cern.ch/documentation/pipelines/master/prm_html/PhysicsReferenceManual/electromagnetic/gamma_incident/compton/compton.html).
- **Compound photon attenuation:** computed water at 1 MeV agrees with the independently published
  [NIST water coefficient](https://physics.nist.gov/PhysRefData/XrayMassCoef/ComTab/water.html),
  0.07072 cm²/g, within 0.00005 cm²/g (rounded input tables/atomic weights).
- **Target geometry:** a 60° tilt doubles the active areal density for a completely traversed layer.
  Carbon areal density is also checked dimensionally against mass thickness / atomic mass × Avogadro constant.
- **Beam units:** 1 µA of charge-state-2 ions at 1 MeV gives 0.5 W for complete energy deposition.
- **Statistics:** signal 2/s and background 3/s, with an equal-time background measurement, require
  200 s for 10% net-signal uncertainty; the inverse calculation reproduces 10%.
- **Spectra:** earlier tests continue to check Gaussian area, centroid and variance, channel/window
  effects, Compton edge, absorption-edge handling, foil angle/path, all 92 NIST elements and additive lines.
- **Isotopes:** enriched, mixed and natural components, explicit majority-isotope labels, legacy
  decoding, and zero-active-isotope behavior are covered.
- **Workflow:** versioned setup round trips, independent snapshots, unsupported-version rejection,
  saved zero values, and SwiftData coexistence of run records and Notebook entries are tested.

## Verification and remaining limits

Run `./Tools/test.sh` for physics and workflow regressions. Build the full app with Xcode for the
iOS Simulator destination. In this environment the inherited Conda `LD` overrides Xcode's linker;
unset `LD`, `LDPLUSPLUS`, `CC`, `CXX` and `CPP` for the command-line Xcode build.

Interactive device verification remains outstanding: the installed simulator runtime is iOS 18.3,
while this app targets iOS 26+. The previous macOS preview could not be inspected through the UI tool.
The persistence tests use an in-memory store; existing-device SwiftData migration should be checked
before distributing a release. Preserve a copy of valuable Notebook data before release testing.

Gamma response is still a single-scatter planning model. It does not infer efficiencies or reaction
gamma cascades, and does not include escape peaks, pile-up or a detector transport Monte Carlo.
Foils currently model photon attenuation; charged-particle detector foils are a separate future feature.

## Next substantial additions

1. Measured spectrum CSV import, energy calibration and reviewed peak/sideband analysis.
2. Multiple detector configurations per run, including geometry, calibration provenance and live time.
3. Charged-particle transport from the reaction target through detector foils and dead layers.
4. A finite-width resonance integration and measured cross-section yield integration.
