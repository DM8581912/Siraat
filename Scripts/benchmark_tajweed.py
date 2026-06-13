import json

def simulate_evaluation():
    with open('Siraat/Siraat/Resources/TajweedBlueprints_Full.json', 'r', encoding='utf-8') as f:
        blueprints = json.load(f)
    
    # Test with Al-Fatiha 1:1
    ayah_1_1 = next(a for a in blueprints['ayahs'] if a['verseKey'] == '1:1')
    print(f"Benchmarking Ayah {ayah_1_1['verseKey']}: {ayah_1_1['scriptUthmani']}")
    
    # Simulate a perfect recitation
    perfect_aligned = []
    for p in ayah_1_1['phonemes']:
        perfect_aligned.append({
            "symbol": p['symbol'],
            "duration": p['expectedDurationSeconds'],
            "confidence": 0.95
        })
    
    # Simulate a recitation with a short Madd
    short_madd_aligned = []
    for p in ayah_1_1['phonemes']:
        duration = p['expectedDurationSeconds']
        if p['isMaddVowel']:
            duration = 0.2 # Too short
        short_madd_aligned.append({
            "symbol": p['symbol'],
            "duration": duration,
            "confidence": 0.95
        })
        
    print("\nPerfect Recitation: All Green Expected")
    # In a real scenario, we'd call the Swift evaluator. 
    # Here we just verify the logic we've built into the blueprints.
    
    print("\nShort Madd Recitation: Yellow Expected on Madd letters")
    for i, p in enumerate(ayah_1_1['phonemes']):
        if p['isMaddVowel']:
            obs = short_madd_aligned[i]
            if obs['duration'] < p['expectedDurationSeconds'] * 0.5:
                print(f"Flagged: {p['baseLetter']} is too short ({obs['duration']}s vs {p['expectedDurationSeconds']}s)")

simulate_evaluation()
