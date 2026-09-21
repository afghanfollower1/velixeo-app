# VELIXEO incremental Android updates

VELIXEO keeps the existing signed-APK updater for **full releases** and adds Shorebird as the **small OTA patch** path for Flutter/Dart changes.

## What this solves

- Backend/Admin/content changes need **no APK update**.
- Dart UI and business-logic changes can be shipped as a small Shorebird patch instead of downloading the full APK.
- Android/Kotlin changes, Flutter engine changes, and asset additions/removals still require a new full APK release.
- The AFN/USD/Toman provider/display-currency work is server driven, so exchange-rate and provider-currency changes do not require an app rebuild.

## One-time setup

1. Create a Shorebird account/application for VELIXEO.
2. In GitHub repository **Settings → Secrets and variables → Actions**:
   - secret: `SHOREBIRD_TOKEN`
   - variable: `SHOREBIRD_APP_ID`
3. Run **Shorebird VELIXEO Android Release** once.
4. Install/distribute that newly generated APK once. Older standard-Flutter APKs cannot consume Shorebird patches.

After this base APK is installed, use **Shorebird VELIXEO Android Patch** for Dart-only changes. Keep using a full release when the patch workflow reports native or asset differences.

The current GitHub-release APK updater remains available as the fallback for full/native releases.
