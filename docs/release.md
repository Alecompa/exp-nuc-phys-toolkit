# Building a release

## On your own iPhone (free)
1. Open `Gamow.xcodeproj` in Xcode (regenerate with `xcodegen generate` after editing `project.yml`).
2. Xcode ▸ Settings ▸ Accounts: add your Apple ID.
3. Select the **Gamow** target ▸ Signing & Capabilities ▸ Team: your Personal Team. Do the same for **GamowWidgets**.
   Or put your Team ID into `DEVELOPMENT_TEAM` for both targets in `project.yml`.
4. Plug in the iPhone, enable Developer Mode (Settings ▸ Privacy & Security), choose it as the run destination, press Run.
   With a free account the app must be re-installed every 7 days; with the paid Developer Program it lasts a year (or use TestFlight).

## App Store / TestFlight
1. Set `MARKETING_VERSION` (user-visible) and bump `CURRENT_PROJECT_VERSION` (build number) for all targets
   (Gamow, GamowWidgets, GamowMac) in `project.yml`, then `xcodegen generate`.
2. Product ▸ Archive with the **Release** configuration (whole-module optimisation, dSYMs).
3. Organizer ▸ Distribute App ▸ App Store Connect ▸ Upload.
4. In App Store Connect: privacy label "Data Not Collected" (see `privacy.md`; host it and give its URL),
   export compliance is already answered (`ITSAppUsesNonExemptEncryption = NO`), category Education or Reference,
   price **Free** (required by the SRIM non-commercial licence).
5. Screenshots: 6.9" iPhone and 13" iPad.

## Mac app (GamowMac)
1. Select the **GamowMac** scheme ▸ Signing & Capabilities ▸ choose your team (bundle id `com.acompagnucci.gamow.mac`).
2. The app is sandboxed: outgoing network (EXFOR, ENSDF) and user-selected files only (`MacApp/GamowMac.entitlements`).
3. Product ▸ Archive, then distribute through App Store Connect (Mac App Store or TestFlight for Mac) or
   *Direct Distribution* (Developer ID, notarised) for a downloadable `.app`.
4. Mac App Store screenshots: 1280 × 800 or larger.

## Android, Linux and Windows (`multiplatform/`)
1. Set `versionName`/`versionCode` in `multiplatform/composeApp/build.gradle.kts` to match `MARKETING_VERSION`.
   The desktop `packageVersion` must have a major version above 0 for the installers (currently `1.0.0`).
2. Push: `.github/workflows/multiplatform.yml` runs `desktopTest` and builds the debug APK, `.deb`, `.msi` and `.dmg`
   as workflow artifacts. Linux and Windows packages can only be built on those systems, so use the workflow.
3. A release APK needs a signing keystore kept outside the repository (planned, `multiplatform/PLAN.md` 4.3).
4. Test the APK on a phone (`adb install …`) and the installers on Linux and Windows before publishing them.

## Checklist before a release
- `./Tools/test.sh` passes, and `cd multiplatform && ./gradlew :composeApp:desktopTest` passes against the same
  `Shared/reference_*.json`.
- Debug-only roadmap rows do not appear (they are compiled out in Release).
- Data credits in Settings ▸ Data Sources & Licences are current.
