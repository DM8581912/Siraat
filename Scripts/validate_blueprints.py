import json

with open('Siraat/Siraat/Resources/TajweedBlueprints.json', 'r', encoding='utf-8') as f:
    original = json.load(f)

with open('Siraat/Siraat/Resources/TajweedBlueprints_Full.json', 'r', encoding='utf-8') as f:
    full = json.load(f)

print(f"Original ayahs: {len(original['ayahs'])}")
print(f"Full ayahs: {len(full['ayahs'])}")

# Check Al-Fatiha 1:1
orig_1_1 = original['ayahs'][0]
full_1_1 = next(a for a in full['ayahs'] if a['verseKey'] == '1:1')

print("\nComparing 1:1 phonemes:")
for i in range(min(len(orig_1_1['phonemes']), len(full_1_1['phonemes']))):
    op = orig_1_1['phonemes'][i]
    fp = full_1_1['phonemes'][i]
    status = "MATCH" if op['symbol'] == fp['symbol'] else "MISMATCH"
    print(f"{i}: {op['symbol']} vs {fp['symbol']} -> {status}")

