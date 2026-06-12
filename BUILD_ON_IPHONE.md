# Building Siraat from your phone / iPad

You don't have a Mac, so here's the on-device path. The realistic tool for building a real
iOS app on Apple hardware without a Mac is **Swift Playgrounds** (free, App Store). It runs
on **iPad** and **iPhone**; opening and building this full Xcode project + uploading to the
App Store is smoothest on **iPad** (iPhone Swift Playgrounds is more limited). If you only
have an iPhone, the iPad flow below still applies if you can borrow/buy an iPad; otherwise a
cloud-Mac service (e.g. Xcode Cloud, Codemagic, MacinCloud) is the alternative.

## Good news: nothing to wire up by hand
The two things I previously said needed a Mac are now **already added to the Xcode project**:
- `PrivacyInfo.xcprivacy` (App Store privacy manifest)
- The three offline translation editions (`Translation-ur/id/tr.json`)

They're in the app target's resources in `project.pbxproj`, so when you open the project they
just build. No "target membership" step.

## Steps on iPad
1. **Get the code onto the device.** Install the **Working Copy** app (git client) or GitHub's
   app, and clone `github.com/DM8581912/Siraat` (branch `feature/production-grade-ui-trust`).
2. **Open in Swift Playgrounds.** Swift Playgrounds → open `Siraat.xcodeproj`. Let it resolve.
3. **Set signing.** Tap the app settings → set your Apple ID team so it can sign to your device.
4. **Run** on your iPad/iPhone to test, or **Upload to App Store Connect** from Swift
   Playgrounds when ready (you'll need an Apple Developer account, $99/yr).

## The one optional asset: the Uthmani Qur'an font
The app runs fine without it (verse text falls back to the system Arabic font). To enable the
nicer Uthmani face, see `Siraat/Resources/Fonts/README.md` — on iPad you drop the font file
into that folder in Working Copy, then add one line to `project.pbxproj` (the README shows the
exact snippet to paste, mirroring how the translation files are wired). It registers itself at
launch; no Info.plist editing.

## After building — verify these on-device
The big batch of changes can only be confirmed on a real device:
- Dynamic Type at the largest sizes (Arabic scales now), VoiceOver reads Arabic.
- Switch translation to **Urdu / Indonesian / Turkish** with airplane mode on → it shows the
  real translation offline with the correct credit (no English-under-wrong-name).
- Prayer reminders fire at the correct computed times across several days.
- Recitation screen shows no red "wrong" verdicts and the "follow-along, not a tajweed ruling" note.
