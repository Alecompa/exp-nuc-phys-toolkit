# NIST photon attenuation data

Elemental HTML tables downloaded 2026-11-11 from the official NIST host:
`https://pml.nist.gov/PhysRefData/XrayMassCoef/ElemTab/zNN.html`, Z=1–92.

J. H. Hubbell and S. M. Seltzer, NISTIR 5632, Tables of X-Ray Mass Attenuation
Coefficients and Mass Energy-Absorption Coefficients (1995).
Public-domain US government data. Original source pages retained for provenance.

`Tools/fetch_photon_attenuation.py` extracts total μ/ρ (cm²/g), converts energies
from MeV to keV with decimal arithmetic, and retains duplicate absorption-edge
energies in their original order. μ_en/ρ is not used by the foil model.
