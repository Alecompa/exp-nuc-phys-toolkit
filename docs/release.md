# Building a release

## On your own iPhone (free)
1. Open `Gamow.xcodeproj` in Xcode (regenerate with `xcodegen generate` after editing `project.yml`).
2. Xcode ▸ Settings ▸ Accounts: add your Apple ID.
3. Select the **Gamow** target ▸ Signing & Capabilities ▸ Team: your Personal Team. Do the same for **GamowWidgets**.
   Or put your Team ID into `DEVELOPMENT_TEAM` for both targets in `project.yml`.
4. Plug in the iPhone, enable Developer Mode (Settings ▸ Privacy & Security), choose it as the run destination, press Run.
   With a free account the app must be re-installed every 7 days; with the paid Developer Program it lasts a year (or use TestFlight).

## App Store / TestFlight
1. Set `MARKETING_VERSION` (user-visible) and bump `CURRENT_PROJECT_VERSION` (build number) for both targets.
2. Product ▸ Archive with the **Release** configuration (whole-module optimisation, dSYMs).
3. Organizer ▸ Distribute App ▸ App Store Connect ▸ Upload.
4. In App Store Connect: privacy label "Data Not Collected" (see `privacy.md`; host it and give its URL),
   export compliance is already answered (`ITSAppUsesNonExemptEncryption = NO`), category Education or Reference,
   price **Free** (required by the SRIM non-commercial licence).
5. Screenshots: 6.9" iPhone and 13" iPad.

## Checklist before a release
- `./Tools/test.sh` passes.
- Debug-only roadmap rows do not appear (they are compiled out in Release).
- Data credits in Settings ▸ Data Sources & Licences are current.
