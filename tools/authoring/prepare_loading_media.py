"""Prepare supplied loading artwork offline. Requires rlottie-python, Pillow, numpy, imageio-ffmpeg.

Sources remain untouched. Native Godot nodes play the results; no runtime Lottie dependency.
"""
from pathlib import Path
import copy
import json
import subprocess
import wave
import numpy as np
import imageio_ffmpeg
from PIL import Image
from rlottie_python import LottieAnimation

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/ui/loading'
SOURCE = Path('E:/Downloads/Всякая хуйня для игры')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    original = Path('E:/Downloads/Atom Loader.json')
    data = json.loads(original.read_text(encoding='utf8'))
    (OUT / 'atom_source.json').write_text(json.dumps(data, ensure_ascii=False), encoding='utf8')
    adapted = copy.deepcopy(data)

    def colors(value):
        if isinstance(value, dict):
            # Preserve source masks, paths and timing. Only visible black fills
            # become warm white so the supplied balls read on a dark screen.
            if value.get('ty') in ('fl', 'st'):
                color = value.get('c', {}).get('k')
                if isinstance(color, list) and len(color) == 4 and color[:3] == [0, 0, 0]:
                    value['c']['k'] = [0.937, 0.937, 0.91, color[3]]
            for child in value.values():
                colors(child)
        elif isinstance(value, list):
            for child in value:
                colors(child)

    colors(adapted)
    animation = LottieAnimation.from_data(json.dumps(adapted))
    atlas = Image.new('RGBA', (1280, 1280))
    for i in range(57):
        frame = animation.render_pillow_frame(i * 2, width=160, height=160)
        atlas.paste(frame, ((i % 8) * 160, (i // 8) * 160))
    atlas.save(OUT / 'atom_atlas.png', optimize=True)
    # End/start overlap: output begins at source second 1 and ends at the
    # same moment after a 1-second dissolve. This avoids a hard VHS cut.
    video_filter = ('[0:v]trim=duration=15,setpts=PTS-STARTPTS,fps=30,settb=1/30,split[a][b];'
                    '[a][b]xfade=transition=fade:duration=1:offset=14,'
                    'trim=start=1:end=15,setpts=PTS-STARTPTS,format=yuv420p[v]')
    subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'warning', '-y',
                    '-i', str(SOURCE / '1024_prob4-vhs.mp4'), '-filter_complex', video_filter,
                    '-map', '[v]', '-an', '-r', '30', '-c:v', 'libtheora', '-q:v', '7',
                    str(OUT / 'vhs_01.ogv')], check=True)
    # A restrained early passage, before the denser second half. Overlap its
    # ends, keeping the audible loop periodic rather than fading to silence.
    music = ROOT / 'assets/audio/music/loading_northernlab.ogg'
    with wave.open(str(SOURCE / 'Звуки/NorthernLab.wav'), 'rb') as source_audio:
        rate = source_audio.getframerate()
        channels = source_audio.getnchannels()
        assert source_audio.getsampwidth() == 2
        samples = np.frombuffer(source_audio.readframes(source_audio.getnframes()), dtype='<i2')
        samples = samples.reshape(-1, channels).astype(np.float32) / 32768.0
    passage = samples[28 * rate:76 * rate]
    overlap = 3 * rate
    t = np.arange(overlap, dtype=np.float32)[:, None] / overlap
    seam = passage[-overlap:] * (1 - t) + passage[:overlap] * t
    loop = np.concatenate([passage[overlap:-overlap], seam]).astype('<f4')
    subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'warning', '-y',
                    '-f', 'f32le', '-ar', str(rate), '-ac', str(channels), '-i', '-',
                    '-vn', '-c:a', 'libvorbis', '-q:a', '5', str(music)], input=loop.tobytes(), check=True)
    print('Prepared 57 atom frames, silent 14s video loop, 45s music loop (source 00:28–01:16).')


if __name__ == '__main__':
    main()
