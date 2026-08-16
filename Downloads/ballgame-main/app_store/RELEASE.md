# App Store release runbook

## Confirmed release values

1. Bundle ID: `meteorsvsplanets.kozmosoft.com`
2. Apple Developer Team ID: `W7AVB28F28`
3. Version/build: `1.0.0 (3)`
4. Devices: iPhone only, portrait only
5. Primary language: English (U.S.); Turkish store localization is optional
6. Price: Free
7. Made for Kids: No
8. Privacy Policy URL: `https://cinematchsocial.web.app/meteors-vs-planets-privacy-policy`
9. Review contact: Çınar Atakul, `team@cinematchsocial.com`, `+90 507 352 70 12`

This first build intentionally uses Google's iOS test App ID and test interstitial ID because production AdMob IDs are not available yet. Test ads generate no revenue and visibly identify themselves as test ads. Replace both IDs before monetized public distribution.

## One-time Apple setup

1. Join the Apple Developer Program and accept pending agreements.
2. In App Store Connect, create a new iOS app record with the exact Bundle ID.
3. Use `METEORS-VS-PLANETS-IOS-001` as the SKU unless that SKU already exists.
4. In Xcode > Settings > Accounts, sign in with the Apple ID that belongs to the developer team.
5. Open `ios/Runner.xcworkspace`, select Runner, and verify team `W7AVB28F28` with Automatically manage signing enabled.

Signing is now working with Apple Developer Team `W7AVB28F28`. The signed archive and IPA were produced successfully for version `1.0.0` build `3`.

The published privacy page is reachable and includes a contact email, but that page currently lists `kozmosoftgames@gmail.com`. A dedicated support page using `team@cinematchsocial.com` is prepared as `app_store/support-page.html`; publish it over HTTPS and replace the temporary Support URL in both metadata files when convenient.

## Preflight

Run from the repository root:

```bash
flutter doctor -v
flutter clean
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter analyze
flutter test
plutil -lint ios/Runner/Info.plist ios/ExportOptions.plist
```

## Archive and create the IPA

Every uploaded build number must be unique. No build has been uploaded yet, so the first upload uses version `1.0.0`, build `3`.

```bash
flutter build ipa \
  --release \
  --build-name=1.0.0 \
  --build-number=3 \
  --export-options-plist=ios/ExportOptions.plist
```

Expected output:

- Archive: `build/ios/archive/Runner.xcarchive`
- IPA: `build/ios/ipa/*.ipa`

If automatic signing needs to create or download a provisioning profile, first open Xcode and archive once through Product > Archive.

## Validate and upload — recommended UI flow

```bash
open build/ios/archive/Runner.xcarchive
```

In Xcode Organizer:

1. Select the archive.
2. Click Distribute App.
3. Choose App Store Connect, then Upload.
4. Keep automatic signing and symbol upload enabled.
5. Resolve validation issues, then upload.

## Upload from Terminal — API key flow

Create an App Store Connect API key with sufficient access, download its `.p8` file once, and keep it outside the repository.

```bash
xcrun altool --validate-app \
  --type ios \
  --file build/ios/ipa/*.ipa \
  --apiKey YOUR_KEY_ID \
  --apiIssuer YOUR_ISSUER_ID

xcrun altool --upload-app \
  --type ios \
  --file build/ios/ipa/*.ipa \
  --apiKey YOUR_KEY_ID \
  --apiIssuer YOUR_ISSUER_ID
```

The private key must be available where `altool` expects it, or supplied using the authentication method documented by the installed Xcode version.

## App Store Connect submission

1. Wait for Apple to finish processing the uploaded build.
2. Complete App Information, age rating, content rights, pricing/availability, and Digital Services Act status.
3. Complete App Privacy using `privacy-labels.md` and publish the answers.
4. Add the privacy policy and support URLs.
5. Add one to ten real iPhone gameplay screenshots. The project is configured for iPhone only.
6. Paste the metadata and review notes from this directory.
7. Select the processed build, answer export-compliance questions, and save.
8. Choose manual or automatic release, then Add for Review and Submit to App Review.

## Screenshot sizes

Use screenshots with no alpha channel. A practical current set is:

- iPhone 6.9-inch: `1320 × 2868`, `1290 × 2796`, or `1260 × 2736` portrait
Capture actual gameplay, level selection, tutorial, and the coin-only shop. Do not show debug banners, test ads, placeholder content, or device frames that obscure the UI.
