# Gamow — Privacy Policy

_Last updated: 8 November 2026_

Gamow is a calculator and reference app for nuclear physics. It is designed to collect nothing.

- **No data collection.** Gamow has no account, no analytics, no advertising, no tracking and no third-party SDKs.
- **On-device storage.** Your inputs, saved sources and notebook entries are stored only on your device (UserDefaults and SwiftData). They are included in your device backups like the data of any other app and are deleted when you delete the app.
- **Network access.** Gamow contacts two servers, and only for data you open:
  - the IAEA Nuclear Data Section (`nds.iaea.org`), to download level and γ-ray data for the nuclide you open. The request contains the nuclide name (for example `28si`) and a generic app identifier, nothing about you. You can switch automatic loading off in Settings.
  - GitHub (`raw.githubusercontent.com`), to download the EXFOR cross-section tables of a reaction you open. The request contains the table's file name (target, reaction, first author, EXFOR entry) and a generic app identifier, nothing about you. Downloaded tables are cached on the device; Settings shows their size and can delete them.

  The IAEA's and GitHub's own privacy terms apply to their servers.
- **Sharing.** Files and text leave the device only when you export them through the system share sheet.
- **Widgets and Shortcuts** run on your device with the values you enter in them.

For questions, contact the developer through the App Store listing.

For App Store Connect: _Data Not Collected_ is the correct privacy label.
