# Gamow — Privacy Policy

_Last updated: 26 November 2026_

Gamow is a calculator and reference app for nuclear physics. It is designed to collect nothing. This policy covers
the iPhone, iPad and Mac apps and the Android, Linux and Windows versions built from `multiplatform/`.

- **No data collection.** Gamow has no account, no analytics, no advertising, no tracking and no third-party SDKs.
- **On-device storage.** Your inputs, saved sources and notebook entries are stored only on your device: UserDefaults and SwiftData on iPhone, iPad and Mac; SharedPreferences on Android; Java preferences and a cache folder in your home directory on Linux, Windows and macOS desktop builds. They are included in your device backups like the data of any other app and are deleted when you delete the app (on desktop systems, the cache folder may need to be removed by hand).
- **Network access.** Gamow contacts two servers, and only for data you open:
  - the IAEA Nuclear Data Section (`nds.iaea.org`), to download level and γ-ray data for the nuclide you open. The request contains the nuclide name (for example `28si`) and a generic app identifier, nothing about you. You can switch automatic loading off in Settings (iPhone, iPad and Mac).
  - GitHub (`raw.githubusercontent.com`), to download the EXFOR cross-section tables of a reaction you open. The request contains the table's file name (target, reaction, first author, EXFOR entry) and a generic app identifier, nothing about you. Downloaded tables are cached on the device; on iPhone, iPad and Mac, Settings shows their size and can delete them.

  The IAEA's and GitHub's own privacy terms apply to their servers.
- **Sharing.** Files and text leave the device only when you export them through the system share sheet or a save dialog. The Mac app reads only the spectrum files you open or drop on its window.
- **Widgets and Shortcuts** (iPhone and iPad) run on your device with the values you enter in them.

For questions, contact the developer through the App Store listing.

For App Store Connect: _Data Not Collected_ is the correct privacy label (iOS and macOS).
