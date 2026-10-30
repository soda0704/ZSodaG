"""Prepare a cyclic faulty-lamp recording and native Animation from 03148.mp3.

Offline dependencies: numpy, scipy, soundfile. Original recording is untouched.
Usage: python tools/authoring/author_medical_fault_audio.py [source.mp3]
"""
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/.local/monster_sound/python'))
import numpy as np
from scipy import signal
import soundfile as sf

source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('E:/Downloads/03148.mp3')
data, rate = sf.read(source, always_2d=True)
data = data.mean(axis=1)
rate_out = 32000
data = signal.resample_poly(data, rate_out, rate)
data = signal.sosfilt(signal.butter(2, 40, fs=rate_out, btype='highpass', output='sos'), data)
# Tame isolated electrical cracks, retaining the quiet continuous electrical bed.
data = np.tanh(data / .07) * .07
overlap = round(.18 * rate_out)
weight = .5 - .5 * np.cos(np.linspace(0, np.pi, overlap))
loop = data[overlap:].copy()
loop[-overlap:] = data[-overlap:] * (1 - weight) + data[:overlap] * weight
# Place the playback boundary at a quiet near-zero crossing inside the cyclic edit.
window = rate_out // 100
quiet = np.convolve(loop * loop, np.ones(window)/window, mode='same')
score = np.abs(loop) + np.abs(loop - np.roll(loop, 1)) + np.sqrt(quiet)
boundary = int(np.argmin(score[window:-window])) + window
loop = np.roll(loop, -boundary)
loop *= min(.0794328 / np.sqrt(np.mean(loop * loop)), .6 / np.max(np.abs(loop)))
dest = ROOT / 'assets/audio/gameplay/medical_fault'
dest.mkdir(parents=True, exist_ok=True)
wav = dest / 'medical_fault_loop.wav'
sf.write(wav, loop, rate_out, subtype='PCM_16')
relative = wav.relative_to(ROOT).as_posix()
sample = f'res://.godot/imported/{wav.name}-{hashlib.md5(("res://"+relative).encode()).hexdigest()}.sample'
(dest / (wav.name + '.import')).write_text(f'''[remap]

importer="wav"
type="AudioStreamWAV"
path="{sample}"

[deps]

source_file="res://{relative}"
dest_files=["{sample}"]

[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=32000
edit/trim=false
edit/normalize=false
edit/loop_mode=2
edit/loop_begin=0
edit/loop_end=-1
compress/mode=0
''', encoding='utf-8')
# Offline crack envelope: cyclic padding prevents an artificial flash at the seam.
high = signal.sosfilt(signal.butter(2, 850, fs=rate_out, btype='highpass', output='sos'), loop)
hop = round(rate_out / 100)
energy = np.sqrt(np.array([np.mean(chunk * chunk) for chunk in np.array_split(high[:len(high)//hop*hop], len(high)//hop)]))
low, high_level = np.quantile(energy, [.5, .96])
activity = np.clip((energy - low) / max(high_level - low, 1e-6), 0, 1)
smooth = []
previous = 0.
for value in np.tile(activity, 3):
    coefficient = 1 - np.exp(-.01 / (.008 if value > previous else .055))
    previous += coefficient * (value - previous)
    smooth.append(previous)
smooth = np.array(smooth[-len(activity):])
intensity = .12 + .88 * (1 - smooth) ** 1.15
duration = len(loop) / rate_out
times = np.arange(len(intensity)) * hop / rate_out
# Keep key count bounded to one per rendered 60 Hz frame, interpolate natively.
keys = np.arange(0, duration, 1/60)
values = np.interp(keys, times, intensity)
keys = np.append(keys, duration)
values = np.append(values, values[0])
array = lambda a: ', '.join(f'{float(x):.6f}' for x in a)
(dest / 'medical_fault_flicker.tres').write_text('''[gd_resource type="Animation" format=3]

[resource]
resource_name = "fault"
length = %.9f
loop_mode = 1
tracks/0/type = "value"
tracks/0/imported = false
tracks/0/enabled = true
tracks/0/path = NodePath(".:intensity")
tracks/0/interp = 1
tracks/0/loop_wrap = true
tracks/0/keys = {
"times": PackedFloat32Array(%s),
"transitions": PackedFloat32Array(%s),
"update": 0,
"values": [%s]
}
''' % (duration, array(keys), array(np.ones(len(keys))), array(values)), encoding='utf-8')
report = {'source_name': source.name, 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
          'duration': duration, 'sample_rate': rate_out, 'crossfade_seconds': overlap/rate_out,
          'boundary_offset_seconds': boundary/rate_out,
          'rms': float(np.sqrt(np.mean(loop*loop))), 'peak': float(np.max(np.abs(loop))),
          'seam_delta': float(abs(loop[0]-loop[-1])), 'intensity_min': float(values.min()),
          'intensity_max': float(values.max()), 'animation_keys': len(keys)}
(dest / 'authoring_report.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
print(json.dumps(report, indent=2))
