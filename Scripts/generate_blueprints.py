import json
import os

# Load FullQuran.json
with open('Siraat/Siraat/Resources/FullQuran.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

if isinstance(data, dict):
    surahs = data.get('surahs', [])
else:
    surahs = data

# Map Arabic letters to the symbols used in the original TajweedBlueprints.json
ARABIC_TO_SYMBOL = {
    "ب": "b", "س": "s", "م": "m", "ا": "A", "ل": "l", "ر": "r", "ح": "H", "ن": "n", "ي": "y",
    "ت": "t", "ث": "*", "ج": "j", "خ": "x", "د": "d", "ذ": "z", "ز": "z", "ش": "S", "ص": "s",
    "ض": "D", "ط": "T", "ظ": "Z", "ع": "E", "غ": "g", "ف": "f", "ق": "q", "ك": "k", "ه": "h",
    "و": "w", "ء": "a", "أ": "A", "إ": "A", "آ": "A", "ٱ": "A", "ى": "y"
}

# Tajweed constants from Siraat codebase
MADD_LETTERS = set(["ا", "و", "ي", "ى", "آ"])
MADD_SCALARS = set([0x0653, 0x0670])

def get_phonemes(text):
    phonemes = []
    # Segment into clusters similar to UthmaniCharacterMapper
    for char in text:
        # Check if it's an Arabic base letter
        base_letter = None
        for scalar in char.encode('utf-16-be'):
            # This is a bit complex in Python, let's simplify
            pass
        
        # Simplified: iterate over characters and find base letters
        if char in ARABIC_TO_SYMBOL:
            symbol = ARABIC_TO_SYMBOL[char]
            
            # Check for Madd marks in the cluster (this is simplified)
            has_madd_mark = any(ord(s) in MADD_SCALARS for s in char)
            is_madd = char in MADD_LETTERS or has_madd_mark
            
            phonemes.append({
                "symbol": symbol,
                "baseLetter": char,
                "isMaddVowel": is_madd,
                "expectedMaddCount": 2 if is_madd else 0,
                "expectedDurationSeconds": 0.9 if is_madd else 0.18
            })
    return phonemes

blueprints = []
for surah in surahs:
    if isinstance(surah, str): continue
    surah_num = surah.get('number')
    for ayah in surah.get('ayahs', []):
        verse_key = f"{surah_num}:{ayah.get('numberInSurah')}"
        blueprints.append({
            "verseKey": verse_key,
            "scriptUthmani": ayah.get('textUthmani'),
            "source": {
                "corpus": "Siraat Automated Generator",
                "attribution": "Derived from FullQuran.json and ArabicLetterInfo rules",
                "verified": False
            },
            "phonemes": get_phonemes(ayah.get('textUthmani', ''))
        })

output = {
    "schemaVersion": 1,
    "ayahs": blueprints
}

with open('Siraat/Siraat/Resources/TajweedBlueprints_Full.json', 'w', encoding='utf-8') as f:
    json.dump(output, f, ensure_ascii=False, indent=2)

print(f"Generated blueprints for {len(blueprints)} ayahs.")
