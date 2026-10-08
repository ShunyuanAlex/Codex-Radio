"""Build the shared weekly-quota warning from the pinned FlightGear recording."""
from pathlib import Path
import array
import hashlib
import json
import subprocess
import tempfile
import wave

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Assets/SoundSources/boeing/GPWS/pull-up.wav'
EXPECTED = 'b9f2b4fdf64e0b5d210311d185de83ed974101df8358f59f0eef9a8b7e116fc4'
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == EXPECTED
with tempfile.TemporaryDirectory() as temp:
    decoded = Path(temp) / 'pull-up.wav'
    subprocess.run(['/usr/bin/afconvert', '-f', 'WAVE', '-d', 'LEI16@24000', '-c', '1', str(SOURCE), str(decoded)], check=True)
    with wave.open(str(decoded)) as wav:
        samples = array.array('h', wav.readframes(wav.getnframes()))
# Preserve the spoken phrase; only soften the 4 ms endpoints. Two full phrases,
# separated by 80 ms, play as one track. Runtime matches the callsign RMS level.
for i in range(96):
    samples[i] = round(samples[i] * i / 95)
    samples[-i-1] = round(samples[-i-1] * i / 95)
output = samples + array.array('h', [0] * 1920) + samples
path = ROOT / 'Assets/Alerts/pull-up.wav'
path.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(path), 'wb') as wav:
    wav.setparams((1, 2, 24000, 0, 'NONE', 'not compressed'))
    wav.writeframes(output.tobytes())
manifest = {
    'source': '777-VMD/Sounds/GPWS/pull-up.wav',
    'url': 'https://raw.githubusercontent.com/franck-vmd/Boeing-777-Flightgear/42b53cbd1abff5a2cbc868c6576c79c343405b3d/777-VMD/Sounds/GPWS/pull-up.wav',
    'source_sha256': EXPECTED,
    'license': 'GPL-2.0; see Assets/SoundSources/boeing/LICENSE and AUTHORS',
    'output': 'Assets/Alerts/pull-up.wav',
    'output_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
    'phrase_repetitions': 2, 'gap_seconds': 0.08,
    'seconds': len(output) / 24000,
    'processing': '24 kHz mono PCM, 4 ms endpoint fades, two full phrases; runtime RMS matched to alfa.wav',
}
(path.parent / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest, indent=2))

# Exhaustion has a separate nonverbal continuous warning, not another Pull up.
source_alarm = ROOT / 'Assets/SoundSources/boeing/config-warning.wav'
with tempfile.TemporaryDirectory() as temp:
    decoded = Path(temp) / 'alarm.wav'
    subprocess.run(['/usr/bin/afconvert', '-f', 'WAVE', '-d', 'LEI16@24000', '-c', '1', str(source_alarm), str(decoded)], check=True)
    with wave.open(str(decoded)) as wav:
        alarm = array.array('h', wav.readframes(wav.getnframes()))
for i in range(240):
    alarm[i] = round(alarm[i] * i / 239)
    alarm[-i-1] = round(alarm[-i-1] * i / 239)
alarm_path = path.parent / 'quota-exhausted.wav'
with wave.open(str(alarm_path), 'wb') as wav:
    wav.setparams((1, 2, 24000, 0, 'NONE', 'not compressed'))
    wav.writeframes(alarm.tobytes())
manifest['exhaustion_alarm'] = {
    'source': 'Assets/SoundSources/boeing/config-warning.wav',
    'source_sha256': hashlib.sha256(source_alarm.read_bytes()).hexdigest(),
    'source_manifest': 'Assets/SoundSources/manifest.json',
    'output': 'Assets/Alerts/quota-exhausted.wav',
    'output_sha256': hashlib.sha256(alarm_path.read_bytes()).hexdigest(),
    'seconds': len(alarm)/24000,
    'processing': '24 kHz mono PCM, 10 ms endpoint fades, one complete alarm; runtime RMS matched to alfa.wav',
}
(path.parent / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
