# Custom experiments and gamma spectra

## Saved experiments and run records

The **Experiments** tab saves a named copy of the shared setup: reaction, beam energy/current/charge
state, excitation, compound target, layer stack, isotope abundance, astrophysics models, detector
resolution/efficiency and spectrum/foil inputs. Add a run number, target ID, observations, measured
integrated charge (µC) and elapsed time (seconds). The record reports mean electrical current and
incident-ion count from these measured totals; it does not infer them from the planned current.
You can edit run notes/totals later without modifying the saved configuration.

Restore a record to return the calculators to that setup. Restoration replaces the current shared
inputs, so save the current configuration first if needed. Named records remain independent of
subsequent edits. Export a record as JSON for an external run archive. JSON import is not yet provided.
Per-screen calculator inputs (for example the manually entered cross section in Yield & Beam Time)
and source certificates are not part of the shared snapshot: save calculator outputs through
**Notebook** and keep certificates in **Calibration Sources**.

## Plot navigation

The spectrum plot supports channel inspection, zoom in/out around the cursor, left/right pan,
explicit energy limits, a reset button, expanded presentation, component visibility and log counts.
The ROI panel sums predicted photopeak, Compton, background and total counts over chosen limits.
Partial boundary channels are weighted by their overlap; this is not measured-spectrum peak fitting.
Log plots use a display floor of 0.01 counts, without modifying readouts, ROI sums or exported values.

Overview plots retain channel extrema within energy buckets to keep narrow peaks visible with fewer
drawn points. Zooming reveals individual channels. Analysis and CSV export always use all channels.
Kinematics and stopping-power plots also have expanded views and focused ranges. Use the search box
on Tools to find a calculator by name or description.

## Isotopes and tilted targets

Explicit formulas such as `Ta2[17O]5` now retain their isotope identities. An explicit isotope
contributes only to its own reaction channel; the user-entered isotope-abundance percentage applies
only to untagged elemental components. This allows mixtures such as `[16O][17O]O2` without counting
all oxygen as the same target isotope. Old records without explicit tags can recover isotope identity
when their mass differs clearly from the natural mass; for older majority-isotope entries such as
`[16O]`, re-enter the formula once because that intent was not stored unambiguously.

Thin-target areal density now includes the beam-path factor `1/cos(angle)`. Yield & Beam Time does
not apply the thin-target approximation when the beam is stopped upstream or inside the target,
and only offers a resonance plateau estimate when the resonance lies inside the traversed energy
interval. A resonance close to the boundary still requires a finite-width treatment beyond this model.

## Building an experiment

Everything shared lives in **Tools → Current Setup → Edit**: the reaction (builder fields or notation),
beam energy and residual Eₓ, and the target — material (formula, compound library or mixture), thickness,
tilt and isotope abundance. The sheet warns when the material does not contain the reaction's target
element. Backings and covers stay in the **Energy Loss** tool.

**Detector Spectrum** adapts to the exit channel:

- **Particles** (default for a charged ejectile): the ejectile and the beam elastically scattered by each
  element of the target material, at the detector's laboratory angle. Energies come from relativistic
  two-body kinematics; absorber foils slow them with SRIM stopping and straggling, and a particle that stops
  in a foil is flagged. Peak widths add the detector resolution, foil straggling and the kinematic spread over
  the detector opening. Peaks are drawn with equal areas; energy loss in the target is not included.
- **γ rays** (default for capture and neutron channels): offers the reaction's own lines — the primary
  capture γ and the residual level → ground state — plus custom lines and calibration-source templates.
  A channel with no γ ray (e.g. (p,α) to the ground state) says so instead of showing a placeholder.

Gamma Doppler and Yield & Beam Time follow the same rule: with a charged ejectile and Eₓ = 0 the yield
counts the particle itself (efficiency = solid-angle fraction) and the Doppler tool notes that no γ is emitted.

## γ response model

- Photopeaks are Gaussian, integrated over each channel using the selected energy-dependent FWHM.
- The continuum is the free-electron Klein–Nishina single-scatter distribution in deposited energy,
  broadened at the deposited energy. Its integrated area relative to the peak is a user input.
- Each incident line is attenuated by `exp(-Σ (μ/ρ) ρ t / cos θ)` before constructing its detector
  response. NIST **total mass attenuation**, not mass energy absorption, is used. Compound
  coefficients are mass-fraction sums; natural-element tables approximate isotope-enriched materials.
- Log-log interpolation preserves both sides of absorption edges; at an exact edge the upper side
  is selected. No extrapolation beyond 1 keV–20 MeV is allowed.
- Background is a flat, recorded counts/keV contribution, not attenuated by the foils. Spectrum
  values are expected counts, not random Poisson realizations. Counts outside the displayed window
  (including broadening below zero) are lost, never redistributed into it.
- Multiple scattering, foil fluorescence/scatter-in, target self-absorption, escape peaks, pair
  production response, coincidence summing, pile-up and Doppler broadening are omitted. The model
  cannot determine detector efficiency or continuum/peak ratio from crystal material alone.

CSV export includes channel centers, total, photopeak, Compton and background counts. Changing the
channel width changes counts per channel, while a fully contained peak retains its integrated area.

## Data and validation

The [NIST elemental tables](https://physics.nist.gov/PhysRefData/XrayMassCoef/tab3.html), Hubbell and
Seltzer, NISTIR 5632, are bundled for Z=1–92. Source HTML is retained under `Data/NIST`.
Rebuild the JSON offline with `python3 Tools/fetch_photon_attenuation.py`; add `--download` to refresh.
The [NIST attenuation definition](https://physics.nist.gov/PhysRefData/XrayMassCoef/chap2.html) and
[Geant4 Klein–Nishina reference](https://geant4.web.cern.ch/documentation/pipelines/master/prm_html/PhysicsReferenceManual/electromagnetic/gamma_incident/compton/compton.html)
document the underlying formulas; this implementation does not use Geant4 transport.

Tests cover NIST reference values and absorption edges, all 92 bundled elements, compound mass
fractions, foil angle/path length, Gaussian area/centroid/width, additive contaminant lines,
background, Compton edge and continuum area, cropped windows, invalid inputs and Codable round trips.
