# source_sdk

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Universal Links / App Links setup

To enable automatic opening of the Source app when a user scans the QR, set up Universal Links (iOS) and App Links (Android):

- Android
	1. Add the intent filter (already added) to `android/app/src/main/AndroidManifest.xml` to handle `https://www.thelearmondcorporation.com/source/pay`.
	2. Host `assetlinks.json` at `https://www.thelearmondcorporation.com/.well-known/assetlinks.json`. A sample is included at `web/associations/assetlinks.json` — replace `package_name` and `sha256_cert_fingerprints` with your app's values.

- iOS
	1. Add the Associated Domains entitlement `applinks:www.thelearmondcorporation.com`. A sample entitlement file is included at `ios/Runner/Runner.entitlements`.
	2. Host `apple-app-site-association` at `https://www.thelearmondcorporation.com/.well-known/apple-app-site-association` or at the site root. A sample is included at `web/associations/apple-app-site-association` — replace `TEAM_ID` and bundle id accordingly.

After hosting these files and updating your app's build with the correct package/bundle IDs and signing fingerprints, tapping the QR's web URL will open the app directly if installed.
