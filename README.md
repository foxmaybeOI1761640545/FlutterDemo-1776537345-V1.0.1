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
- `.github/workflows/build-release.yml`: GitHub Actions build and package flow

## CI Build/Package

- Push `main`: run tests, build web, upload artifact.
- Push tag like `v1.0.0`: also publish release asset `flutter-web-build.tar.gz`.
