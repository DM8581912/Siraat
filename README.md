# Siraat

Siraat is a SwiftUI iOS application that brings together:

- real-time Arabic khutba transcription and translation,
- Quran recitation correction with word-level feedback,
- a Quran reader with translations, bookmarks, and verse audio playback.
- location-based prayer times, qibla direction, opt-in prayer reminders,
  Quran search, bookmark filtering, and explicit light/dark/system appearance
  control.

The repository contains a hand-authored Xcode project because this workspace is
Linux-based and does not include Xcode tooling. Open `Siraat.xcodeproj` on macOS
with Xcode 16 or newer to build and run the app.

## Configuration

1. Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig`.
2. Fill in provider keys only if you replace the mock translation provider with
   a network-backed service.
3. Do not commit real API keys. The project reads secrets through build settings
   and can be extended to persist runtime tokens in Keychain.

## Verification

This Codespaces environment does not include `swift` or `xcodebuild`, so local
compilation is not possible here. Verify on macOS with:

```sh
xcodebuild -project Siraat.xcodeproj -scheme Siraat -destination 'platform=iOS Simulator,name=iPhone 16' test
```
