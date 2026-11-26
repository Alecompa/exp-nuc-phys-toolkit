# Gamow for Android, Linux and Windows

A Kotlin Multiplatform / Compose Multiplatform version of Gamow: one Kotlin code base builds the **Android APK** and
**desktop apps for Linux (.deb, .rpm), Windows (.msi) and macOS (.dmg)**. The iPhone, iPad and Mac apps stay in
SwiftUI (`App/`, `MacApp/`, `Packages/`).

## How it stays consistent with the Swift app

- **Same data.** The build packages the Swift package's `Packages/NucToolkit/Sources/NucPhysKit/Resources`
  (AME2020, NUBASE2020, SRIM, EXFOR index): one copy of every table.
- **Same numbers.** Six files in `Shared/reference_*.json` (table below) hold about 1 600 cases. Each Swift test
  `Reference*Tests` writes and checks one; the matching Kotlin test `Reference*Test` must reproduce every value to
  10⁻⁹ relative (peak-area uncertainties to 1 % and calibration residuals to 10⁻⁸ keV, because Kotlin's error
  function is a port of fdlibm). Change the physics in both places, regenerate with
  `GAMOW_WRITE_REFERENCE=1 ./Tools/test.sh --filter Reference`, and both suites must pass. Text fields in the files
  (for example decay modes) are written with a decimal point whatever the Mac's locale.

## Status

| Area | Reference file (Swift ↔ Kotlin to 10⁻⁹) |
|---|---|
| Masses, notation, reactions and Q, relativistic kinematics, Coulomb/Gamow, S ↔ σ, screening | `reference_values.json` |
| SRIM-2013 stopping, ranges, energy loss and straggling, layer stacks, compounds, formulas, gases | `reference_stopping.json` |
| EXFOR index, tables, σ ↔ S and lab ↔ c.m., download client with cache | `reference_exfor.json` |
| NUBASE2020, decay, calibration sources and certificates | `reference_decay.json` |
| Reaction rates, narrow resonances, Coulomb functions and penetrabilities, Rutherford, yields, counting statistics | `reference_astro.json` |
| γ response (attenuation, escape peaks, Doppler boxes), in-beam γ and contaminants, particle spectra, measured spectra, peak search, auto-calibration, detector model, γ cascades | `reference_spectra.json` |

**Screens** (all platforms): Reaction setup · Q value · Kinematics · EXFOR · Stopping & energy loss · Gamow window ·
S ↔ σ · Reaction rate · Resonance strength · Penetrability · Yield & beam time · Detector spectrum (γ and particles,
contaminants) · Spectrum analysis (open a file, peaks, auto-calibration) · Calibration sources · Decay · Nuclides ·
Notebook. Apple-only features (Shortcuts, widgets) are not on Android/Linux/Windows.

**Not yet tested** on an Android phone, on Linux or on Windows; the workflow produces the installers for that.

Each screen shows the result first, then the few inputs that matter, then plots; secondary settings are folded
under “More options” style sections with a one-line summary.

The remaining work to reach parity with the iOS app is planned in [PLAN.md](PLAN.md).

## Build

Needs JDK 17+ and, for Android, the Android SDK (`ANDROID_HOME` or `local.properties` with `sdk.dir=…`).

```bash
cd multiplatform
./gradlew :composeApp:desktopTest          # physics tests against Shared/reference_*.json
./gradlew :composeApp:run                  # desktop app on this machine
./gradlew :composeApp:assembleDebug        # APK: composeApp/build/outputs/apk/debug/composeApp-debug.apk
./gradlew :composeApp:packageDeb           # Linux .deb (run on Linux; packageMsi on Windows, packageDmg on macOS)
```

Install the APK with `adb install composeApp/build/outputs/apk/debug/composeApp-debug.apk`, or copy it to the
phone and open it (allow installs from that source). The GitHub workflow `.github/workflows/multiplatform.yml`
runs the tests and builds the APK and the Linux, Windows and macOS packages on every push that touches them, and
attaches them as artifacts.

Screenshots for review can be rendered without a device:
`GAMOW_RENDER_DIR=/some/dir ./gradlew :composeApp:desktopTest --tests org.gamow.RenderScreens`.
