# Qur'an (Uthmani) font

Verse text in the reader uses `Font.quran(...)` (see `App/DesignSystem.swift`), which looks
up the PostScript name in `SiraatFont.uthmaniPostScriptName`. Until a font file is bundled,
SwiftUI's `.custom(...)` silently falls back to the system font — the app still runs, the
Arabic just renders in the default face.

## To enable the real Uthmani face

1. Add a licensed Uthmani font file to this folder. Recommended, redistribution-friendly
   (SIL Open Font License — safe to ship):
   - **Amiri Quran** — https://github.com/alif-type/amiri  (`AmiriQuran-Regular.ttf`)
   - **Scheherazade New** — https://software.sil.org/scheherazade/
   KFGQPC Uthmanic Script HAFS is the most authentic but check its license before shipping.

2. Add the file to the **Siraat app target** (Xcode → file inspector → Target Membership),
   so it lands in the app bundle. `SiraatFont.registerBundledFonts()` (called at launch in
   `SiraatApp.init`) registers every bundled `.otf`/`.ttf` with the process — no Info.plist
   `UIAppFonts` entry required.

3. Set `SiraatFont.uthmaniPostScriptName` to the font's **PostScript name** (open the file in
   macOS Font Book → it's shown there; it is NOT always the filename). For Amiri Quran it is
   `AmiriQuran-Regular`.

4. Verify on device: verse text should switch to the Uthmani face; diacritics render cleanly.
