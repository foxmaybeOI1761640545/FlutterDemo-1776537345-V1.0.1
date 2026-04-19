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

## GitHub Pages URL

After `deploy-flutter-web-to-pages` succeeds, the web app URL is:

`https://<your-github-username>.github.io/<repository-name>/`

For this repository, it will be:

`https://foxmaybeOI1761640545.github.io/FlutterDemo-1776537345-V1.0.1/`

## One-Time Repository Setting

In GitHub repository settings, ensure Pages is configured to use:

- Source: `GitHub Actions`
