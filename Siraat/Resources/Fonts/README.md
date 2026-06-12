# Qur'an (Uthmani) font

Verse text in the reader uses `Font.quran(...)` (see `App/DesignSystem.swift`), which looks
up the PostScript name in `SiraatFont.uthmaniPostScriptName`. Until a font file is bundled,
SwiftUI's `.custom(...)` silently falls back to the system font — the app still runs, the
Arabic just renders in the default face.

This is the ONLY optional manual asset — the privacy manifest and translation editions are
already wired into the Xcode project (`project.pbxproj`). Building from iPad? See the repo's
`BUILD_ON_IPHONE.md`.

## To enable the real Uthmani face

1. Add a licensed Uthmani font file to this folder. Recommended, redistribution-friendly
   (SIL Open Font License — safe to ship):
   - **Amiri Quran** — https://github.com/alif-type/amiri  (`AmiriQuran-Regular.ttf`)
   - **Scheherazade New** — https://software.sil.org/scheherazade/
   KFGQPC Uthmanic Script HAFS is the most authentic but check its license before shipping.

2. Add the file to the app target so it lands in the bundle. `SiraatFont.registerBundledFonts()`
   (called at launch in `SiraatApp.init`) registers every bundled `.otf`/`.ttf` with the
   process — no Info.plist `UIAppFonts` entry needed.
   - **On a Mac:** Xcode → file inspector → Target Membership → check "Siraat".
   - **On iPad (no Mac):** add the file to `project.pbxproj` exactly like the translation
     files are wired. For `AmiriQuran-Regular.ttf` you'd add, mirroring the existing entries:
     a `PBXFileReference` (`lastKnownFileType = file`, `path = "Siraat/Resources/Fonts/AmiriQuran-Regular.ttf"`),
     a `PBXBuildFile` pointing at it, that build-file UUID inside the app **Resources** phase
     (`RB0000000000000000000001`), and the file ref in the `Siraat` group. Use the next free
     `FR…`/`BF…` UUIDs (the translation files used `…0047`–`…004A` / `…0041`–`…0044`).

3. Set `SiraatFont.uthmaniPostScriptName` (in `App/DesignSystem.swift`) to the font's
   **PostScript name** — NOT always the filename. For Amiri Quran it is `AmiriQuran-Regular`.
   (On a Mac, macOS Font Book shows it; otherwise use the name the foundry documents.)

4. Verify on device: verse text should switch to the Uthmani face; diacritics render cleanly.
