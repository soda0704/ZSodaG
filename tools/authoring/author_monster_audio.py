"""Offline sound editing from existing project recordings; writes short mono PCM16 cues.

Dependencies: numpy, scipy, soundfile. No synthesis, decoding or DSP runs in the game.
"""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/.local/monster_sound/python'))
import numpy as np
from scipy import signal
import soundfile as sf

RATE = 32000
DEST = ROOT / 'assets/audio/gameplay/monsters'
DEST.mkdir(parents=True, exist_ok=True)
SOURCES = ROOT / 'assets/audio/gameplay'
report = {}

def read(name):
    data, rate = sf.read(SOURCES / (name + '.ogg'), always_2d=True)
    mono = data.mean(axis=1)
    return signal.resample_poly(mono, RATE, rate)

def fit(data, seconds, speed=1.0):
    if speed != 1:
        data = signal.resample(data, max(1, round(len(data)/speed)))
    count = round(seconds*RATE)
    return np.pad(data[:count], (0, max(0,count-len(data))))

def segment(data, seconds, fraction=0.0):
    """Trim leading/trailing silence before choosing a region of the source recording."""
    active = np.flatnonzero(abs(data) > max(abs(data).max()*.025, 1e-5))
    if not len(active): raise ValueError('Silent source')
    data = data[max(0,active[0]-round(.005*RATE)):active[-1]+1]
    count = round(seconds*RATE)
    start = round(max(0,len(data)-count)*fraction)
    return fit(data[start:], seconds)

def filter_audio(data, low=60, high=12000):
    return signal.sosfilt(signal.butter(2, [low,high], btype='bandpass', fs=RATE, output='sos'),data)

def save(name, data, peak=.55):
    data = np.asarray(data,dtype=np.float64)
    data -= data.mean()
    fade_in = min(round(.004*RATE),len(data)//4)
    fade_out = min(round(.025*RATE),len(data)//4)
    data[:fade_in] *= np.linspace(0,1,fade_in)**.7
    data[-fade_out:] *= np.linspace(1,0,fade_out)**1.5
    maximum = abs(data).max()
    if maximum < 1e-6: raise ValueError('Silent output: '+name)
    data *= peak/maximum
    sf.write(DEST/(name+'.wav'),data,RATE,subtype='PCM_16')
    report[name]={'seconds':round(len(data)/RATE,4),'peak_dbfs':round(float(20*np.log10(abs(data).max())),2),'rms_dbfs':round(float(20*np.log10(np.sqrt(np.mean(data*data)))),2)}

voices = {name:read(name) for name in ['tail','slasher','smily']}
floor,metal,snow,impact = [read(n) for n in ['floor_0','metal_0','snow_0','impact_concrete']]
breath = read('breath_short')
for creature,source,speed,length in [('head','smily',1.18,.52),('evolution','tail',.82,.9),('tail','tail',.96,.85),('slasher','slasher',1.0,.7),('smily','smily',1.03,.6)]:
    voice = voices[source]
    ambient_len = .85 if creature=='head' else 1.8 if creature in ['tail','evolution'] else 1.25
    for index,fraction in enumerate([.28,.72]):
        save(creature+'_ambient_'+str(index), filter_audio(fit(segment(voice,ambient_len*speed,fraction),ambient_len,speed),90,8500),.42)
    save(creature+'_alert',filter_audio(fit(segment(voice,length*speed,.12),length,speed),80,10500))
    search_len = .48 if creature=='head' else .7
    texture = fit(segment(voice,search_len*speed,.68),search_len,speed)
    save(creature+'_search',filter_audio(texture*.55+segment(breath,search_len,.35)*.3,90,4200),.35)
    duration = .24 if creature=='head' else .5 if creature=='evolution' else .35
    intake = segment(breath,duration,.05)
    snarl = fit(segment(voice,duration*speed,.42),duration,speed)
    ramp = np.linspace(.1,1,len(intake))**.6
    save(creature+'_windup',filter_audio((intake*.4+snarl*.8)*ramp,120,11000),.5)
    swing = segment(breath,.18 if creature=='head' else .26,.5)
    save(creature+'_miss',filter_audio(swing,400,12500),.4)
    hit = segment(impact,.13 if creature=='head' else .23,.0)
    save(creature+'_strike',filter_audio(hit,60,9500),.55)

for creature in ['head','evolution']:
    for surface,data in [('floor',floor),('metal',metal),('snow',snow)]:
        for index,speed in enumerate([.94,1.0,1.07]):
            duration = .045 if creature=='head' else .18
            trimmed = segment(data,.1 if creature=='head' else .24,0)
            body = fit(trimmed,duration,(2.2 if creature=='head' else .8)*speed)
            if creature=='evolution':
                thud = fit(segment(impact,.25,0),duration,.8*speed)
                body = body*.7 + filter_audio(thud,45,650)*.25
            body = filter_audio(body,450 if creature=='head' else 45,12500 if creature=='head' else 7500)
            body *= np.exp(-np.linspace(0,4 if creature=='head' else 2,len(body)))
            save(creature+'_'+surface+'_step_'+str(index),body,.42 if creature=='head' else .6)

(DEST/'authoring_report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('AUTHORED MONSTER AUDIO:',len(report),'short mono clips')
