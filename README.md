# Flutter Demo

Minimal Flutter sample with one centered button-driven text toggle and a rainbow text animation.

## Behavior

1. First tap: show `Hello World` in the center.
2. Second tap: switch to Chinese text `\u4f60\u597d \u4e16\u754c`.
3. Next taps: keep alternating between the two texts.
4. Both texts share the same rainbow-cycling style.

## Main Files

- `lib/main.dart`: UI and rainbow animation
- `test/widget_test.dart`: widget toggle test
- `.github/workflows/build-release.yml`: build test pipeline and release asset publishing
- `.github/workflows/deploy-pages.yml`: GitHub Pages deployment workflow
- `.github/workflows/build-windows-installer.yml`: build Windows installer and attach it to tag release
- `.github/workflows/build-android-packages.yml`: build Android APK/AAB and attach them to tag release
- `.github/workflows/build-macos-installer.yml`: build macOS app packages and attach them to tag release
- `.github/workflows/build-ios-package.yml`: build iOS unsigned IPA and attach it to tag release

## CI Build/Package/Release

- Push `main`:
  - run widget tests
  - build Flutter Web package (`flutter-web-build.tar.gz`)
  - build Windows 10 x64 package (`flutter-windows-x64.zip`)
  - upload both artifacts
  - trigger GitHub Pages deployment workflow

- Push tag like `v1.0.0`:
  - run the same builds
  - publish GitHub Release with two assets:
    - `flutter-web-build.tar.gz`
    - `flutter-windows-x64.zip`

- After a tag release build succeeds:
  - `build-and-release-windows-installer` runs and adds:
    - `flutter_demo-<version>-windows-x64-setup.exe`
  - `build-and-release-android-packages` runs and adds:
    - `<app-name>-<version>-android-release.apk`
    - `<app-name>-<version>-android-release.aab`
  - `build-and-release-macos-installer` runs and adds:
    - `<app-name>-<version>-macos-app.zip`
    - `<app-name>-<version>-macos.dmg`
  - `build-and-release-ios-package` runs and adds:
    - `<app-name>-<version>-ios-unsigned.ipa`

## Windows Installer

- Installer format: `.exe` (Inno Setup)
- Included runtime layout: packages the complete `build/windows/x64/runner/Release` directory structure
- Supported OS architecture: `Windows 10/11 x64`
- Not supported: `Windows x86 (32-bit)`

## Android Packages

- Package formats: `.apk` and `.aab`
- Supported targets: Android devices (ARM/x64 handled by Flutter tooling)
- Note: Play Store production release usually requires your own signing keystore setup

## macOS Installer

- Package formats: `.zip` (app bundle) and `.dmg`
- Build environment: `macos-latest` runner
- Note: package is not code-signed/notarized by default, Gatekeeper warning may appear

## iOS Package

- Package format: unsigned `.ipa` (`*-ios-unsigned.ipa`)
- Build mode: `flutter build ios --release --no-codesign`
- Note: unsigned IPA cannot be installed directly on standard iOS devices; signing and provisioning are still required

## GitHub Pages URL

After `deploy-flutter-web-to-pages` succeeds, the web app URL is:

`https://<your-github-username>.github.io/<repository-name>/`

For this repository, it will be:

`https://foxmaybeOI1761640545.github.io/FlutterDemo-1776537345-V1.0.1/`

## One-Time Repository Setting

In GitHub repository settings, ensure Pages is configured to use:

- Source: `GitHub Actions`
