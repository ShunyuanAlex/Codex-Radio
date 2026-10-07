"""Render the two simulator-derived cue packs; no synthesized tones or speech.

Raw recordings, pinned source URLs and licenses live in Assets/SoundSources.
Edits made 2026-10-07: excerpts, envelopes, level matching and rhythmic assembly.
Run with Python 3 on macOS; afconvert performs the source PCM conversion.
"""
from pathlib import Path
import array
import hashlib
import json
import math
import subprocess
import tempfile
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 24000
ORDER = ["reading", "testing", "unknown", "compacting", "complete", "waiting", "cancelled", "blocked"]
SIGNATURES = ["短按键", "单声短铃", "双按键回执", "高低收束音", "完整双钟声", "间隔双提醒", "断开提示", "连续三连告警"]


def load(pack, name):
    source = ROOT / "Assets/SoundSources" / pack / name
    with tempfile.TemporaryDirectory() as temp:
        dest = Path(temp) / "decoded.wav"
        subprocess.run(["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16@24000", "-c", "1", str(source), str(dest)], check=True)
        with wave.open(str(dest)) as wav:
            return [x / 32768 for x in array.array("h", wav.readframes(wav.getnframes()))]


def excerpt(samples, start=0, duration=3, fade_in=.004, fade_out=.018):
    out = samples[round(start * RATE):round((start + duration) * RATE)]
    assert out
    for i in range(min(round(fade_in * RATE), len(out) // 2)):
        out[i] *= i / max(1, round(fade_in * RATE) - 1)
    for i in range(min(round(fade_out * RATE), len(out) // 2)):
        out[-1-i] *= i / max(1, round(fade_out * RATE) - 1)
    return out


def join(*parts):
    out = []
    for part in parts:
        out.extend([0.] * round(part * RATE) if isinstance(part, float) else part)
    return out


def level(samples, db):
    # Match active audio rather than making the quiet gaps increase the gain.
    active = [x for x in samples if abs(x) > .003]
    rms = math.sqrt(sum(x*x for x in active) / len(active))
    gain = min(10 ** (db / 20) / rms, .65 / max(map(abs, samples)))
    return [x * gain for x in samples]


def transpose(samples, ratio):
    """Resample a recorded chime for the two-note compaction motif (no new oscillator)."""
    length = int(len(samples) / ratio)
    result = []
    for i in range(length):
        position = i * ratio
        a = min(len(samples) - 1, int(position))
        b = min(len(samples) - 1, a + 1)
        result.append(samples[a] + (samples[b] - samples[a]) * (position - a))
    return result


def save(dest, samples):
    dest.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(dest), "wb") as wav:
        wav.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        wav.writeframes(array.array("h", [round(x * 32767) for x in samples]).tobytes())


def build(pack):
    def cut(name, start=0, duration=3, **kwargs):
        return excerpt(load(pack, name), start, duration, **kwargs)
    if pack == "airbus":
        click = cut("click.wav", fade_in=.001, fade_out=.003)
        processing = cut("FL2070/320cabinalert.wav", 0, .25, fade_out=.07)
        compact = join(cut("cabinalert.wav", 0, .19, fade_out=.04), .055, cut("cabinalert.wav", .82, .29, fade_out=.09))
        complete = cut("cabinalert.wav", fade_out=.025)
        attention = cut("stall.wav", .03, .16, fade_in=.015, fade_out=.05)
        stop = cut("FL2070/320apoff.wav", 0, .28, fade_out=.015)
        warning = cut("FL2070/320apoff.wav", 0, 1.10)
    else:
        click = cut("click7.wav", fade_in=.001, fade_out=.006)
        processing = cut("cabinalert.wav", 0, .20, fade_out=.06)
        compact = join(transpose(cut("cabinalert.wav", 0, .21, fade_out=.05), 1.25), .055, transpose(cut("cabinalert.wav", 0, .26, fade_out=.08), .9))
        bell = cut("cabinalert.wav", fade_out=.02)
        complete = join(bell, .09, bell)
        attention = cut("caution-sound.wav", 0, .25)
        stop = cut("autopilot-disengage.wav", .12, .62, fade_out=.25)
        alarm = cut("config-warning.wav", .12, .26, fade_out=.025)
        warning = join(alarm, .07, alarm, .07, alarm)
    receipt = join(click, .085, click)
    cues = dict(zip(ORDER, [click, processing, receipt, compact, complete, join(attention, .38, attention), stop, warning]))
    # The runtime additionally matches each cue to the actual joined callsign's
    # active RMS. This baseline makes standalone cue previews comparable to speech.
    targets = dict.fromkeys(ORDER, -15)
    entries = []
    sampler = []
    for status, signature in zip(ORDER, SIGNATURES):
        samples = level(cues[status], targets[status])
        dest = ROOT / "Assets/SoundPacks" / pack / (status + ".wav")
        save(dest, samples)
        entries.append(dict(pack=pack, status=status, signature=signature, duration=round(len(samples)/RATE, 5), peak=round(max(map(abs, samples)), 5), active_rms_target_db=targets[status], sha256=hashlib.sha256(dest.read_bytes()).hexdigest()))
        sampler = join(sampler, samples, .8)
    save(ROOT / "build/sound-preview-0.8.1" / (pack + "-sampler.wav"), sampler)
    return entries


if __name__ == "__main__":
    result = build("airbus") + build("boeing")
    (ROOT / "Assets/SoundPacks/catalog.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
