"""Offline original sound design for furniture/concrete; no runtime synthesis."""
from pathlib import Path
import numpy as np
from scipy.io import wavfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/"assets/audio/gameplay/heavy_props"
OUT.mkdir(parents=True,exist_ok=True)
SR=32000
rng=np.random.default_rng(80423)
def colored(n,lo,hi):
 freq=np.fft.rfftfreq(n,1/SR)
 spectrum=np.fft.rfft(rng.normal(size=n))
 weight=(1-np.exp(-(freq/max(lo,1))**4))*np.exp(-(freq/hi)**4)
 signal=np.fft.irfft(spectrum*weight,n)
 return signal/max(float(np.std(signal)),1e-8)
def write(name,a):
 a=a-np.mean(a)
 a=a*(.72/max(float(np.max(np.abs(a))),1e-8))
 wavfile.write(OUT/(name+".wav"),SR,(a*32767).astype(np.int16))
for material,low,high in [("bench",110,2700),("sofa",70,1000),("concrete",85,5400)]:
 n=SR*4;t=np.arange(n)/SR
 # Periodic random spectra and integer-cycle modulation make a continuous loop.
 base=colored(n,low,high)
 grit=colored(n,600,high)*(.35+.65*np.maximum(0,np.sin(2*np.pi*13*t/4))**8)
 modulation=.7+.13*np.sin(2*np.pi*3*t/4)+.1*np.sin(2*np.pi*7*t/4+.8)
 rub=base*modulation*.65+grit*.22
 if material=="bench":
  rub+=.12*np.sin(2*np.pi*164*t+1.1*np.sin(2*np.pi*t/4))*(.5+.5*np.sin(2*np.pi*2*t/4))
 write(material+"_drag",rub)
 for cue,duration in [("lift",.34),("place",.68)]:
  n=int(SR*duration);t=np.arange(n)/SR
  attack=1-np.exp(-t/(.006 if cue=="lift" else .002))
  envelope=attack*np.exp(-t/(.085 if cue=="lift" else .14))
  noise=colored(n,low,high)*envelope
  modes=np.zeros(n)
  for frequency,amplitude in [(92,.7),(173,.35),(367,.16)]:
   modes+=amplitude*np.sin(2*np.pi*frequency*t)*attack*np.exp(-t/(.08 if material=="sofa" else .18))
  a=noise*.52+modes*(.2 if cue=="lift" else .6)
  if material=="concrete" and cue=="place":
   a+=colored(n,900,6500)*np.exp(-t/.22)*attack*.22
  fade=min(640,n//5);a[-fade:]*=np.linspace(1,0,fade)
  a[0]=0;a[-1]=0
  write(material+"_"+cue,a)
for config in OUT.glob("*_drag.wav.import"):
 text=config.read_text(encoding="utf8").replace("edit/loop_mode=0","edit/loop_mode=2")
 config.write_text(text,encoding="utf8")
print("HEAVY AUDIO READY")
