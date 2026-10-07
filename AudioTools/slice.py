"""Offline clipping of the user-supplied reading; no speech synthesis or playback."""
import array
import hashlib
import json
import math
from pathlib import Path
import struct
import wave

root = Path(__file__).resolve().parents[1]
source = root / "Assets/nato-source.wav"
data = source.read_bytes()
position = 12
chunks = {}
while position + 8 <= len(data):
    tag, size = struct.unpack_from("<4sI", data, position)
    chunks[tag] = data[position + 8:position + 8 + size]
    position += 8 + size + (size % 2)
fmt, channels, rate, _, _, bits = struct.unpack_from("<HHIIHH", chunks[b"fmt "])
assert channels == 1 and rate == 24000 and bits == 16
samples = array.array("h", chunks[b"data"])
names = "Alfa Bravo Charlie Delta Echo Foxtrot Golf Hotel India Juliett Kilo Lima Mike November Oscar Papa Quebec Romeo Sierra Tango Uniform Victor Whiskey Xray Yankee Zulu".split()
names += ["digit" + str(n) for n in range(10)]
runs = json.loads((root / "AudioTools/detected-segments.json").read_text())
runs = [pair for pair in runs if pair[1] - pair[0] > .15][:len(names)]
assert len(runs) == len(names)
target = root / "Assets/Voices"
target.mkdir(exist_ok=True)
records = []
for name, (start, end) in zip(names, runs):
    start, end = max(0, start - .02), end + .02
    # Alfa has a detached, low-frequency bump after a long silent tail.
    # Its last voiced syllable has already decayed by source time 1.18 s.
    if name == "Alfa":
        end = min(end, 1.18)
    clip = samples[round(start * rate):round(end * rate)]
    # Equal peak level; preserve original voice, timing and pronunciation.
    gain = min(2.5, 20000 / max(abs(n) for n in clip))
    clip = array.array("h", (round(n * gain) for n in clip))
    # A conservative -52 dBFS, 5 ms RMS boundary retains quiet final consonants
    # (notably digit5); never remove silence inside a spoken word.
    window = round(rate * .005)
    threshold = 32768 * 10 ** (-52 / 20)
    active = [i for i in range(0, len(clip), window)
              if math.sqrt(sum(n*n for n in clip[i:i+window]) / len(clip[i:i+window])) >= threshold]
    assert active, name
    margin = round(rate * .008)
    first, last = max(0, active[0] - margin), min(len(clip), active[-1] + window + margin)
    clip = clip[first:last]
    start, end = start + first / rate, start + last / rate
    # Fade only the outermost 2 ms to avoid discontinuities.
    for i in range(48):
        clip[i] = round(clip[i] * i / 48)
        clip[-1-i] = round(clip[-1-i] * i / 48)
    path = target / (name.lower() + ".wav")
    with wave.open(str(path), "wb") as stream:
        stream.setparams((1, 2, rate, 0, "NONE", "not compressed"))
        stream.writeframes(clip.tobytes())
    records.append({"callsign": name, "file": path.name, "source_start": round(start, 3), "source_end": round(end, 3), "duration": len(clip)/rate, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
manifest = {"status": "bundled_from_user_upload", "source": "https://commons.wikimedia.org/wiki/File:NATO_Phonetic_Alphabet_reading.ogg", "author": "valeatory", "license": "CC BY-SA 3.0", "changes": "24kHz mono PCM conversion; alphabet and trailing 0–9 clipping; peak gain; -52 dBFS 5ms RMS boundary detection with 8ms margins; Alfa source end capped at 1.18s to exclude a detached low-frequency tail; 2ms edge fades. Runtime applies 12ms linear crossfades only between adjacent voice clips. No synthesis or time stretching.", "verification": "26 alphabet segments and 10 following digit segments; user explicitly confirmed digit order 0,1,2...9 on 2026-10-07. Offline decoding and waveform checks; no physical listening test by agent.", "files": records}
(root / "HookReview/voice-catalog.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n")
print(f"Created {len(records)} voice clips, {min(x['duration'] for x in records):.2f}–{max(x['duration'] for x in records):.2f} seconds; no playback.")
