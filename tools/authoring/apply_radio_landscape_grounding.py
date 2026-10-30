"""Apply only audited MultiMesh origins and matching authored collision poses."""
from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[2]
report=json.loads((ROOT/'tools/.local/radio_tower/forest_grounding.json').read_text())
paths={'Landscape':'scenes/levels/snow_exterior.tscn','CliffValley':'scenes/art/environment/cliff_valley.tscn','WestPassForest':'scenes/art/environment/west_pass_forest.tscn','SouthPassForest':'scenes/art/environment/south_pass_forest.tscn'}
byfile={};counts={}
for group in report:
 folder,name=group['path'].split('/',1)
 if folder not in paths:raise ValueError(group['path'])
 changes=group['changes']
 if name.startswith('Rock'):
  changes=[v for v in changes if abs(v['next_x']-v['x'])+abs(v['next_z']-v['z'])>.01]
  for v in changes:v['next']-=2.;v['delta']-=2.
 if changes:byfile.setdefault(paths[folder],[]).append((name,changes))
for relative,groups in byfile.items():
 p=ROOT/relative;s=p.read_text(encoding='utf-8'); collider_changes=[]
 for name,changes in groups:
  node=re.search(r'\[node name="'+re.escape(name)+r'"[^\n]*\][\s\S]*?(?=\n\[|\Z)',s)
  if not node:raise ValueError(name)
  rid=re.search(r'multimesh = SubResource\("([^"]+)"\)',node.group()).group(1)
  block=re.search(r'\[sub_resource type="MultiMesh" id="'+re.escape(rid)+r'"\][\s\S]*?(?=\n\[|\Z)',s)
  match=re.search(r'buffer = PackedFloat32Array\(([^)]*)\)',block.group())
  values=[v.strip() for v in match.group(1).split(',')]
  count=int(re.search(r'instance_count = (\d+)',block.group()).group(1));stride=len(values)//count
  assert stride*count==len(values) and stride>=12
  for v in changes:
   at=v['index']*stride
   values[at+3]=format(v['next_x'],'.8g');values[at+7]=format(v['next'],'.8g');values[at+11]=format(v['next_z'],'.8g')
   collider_changes.append(v)
  replacement=block.group()[:match.start(1)]+', '.join(values)+block.group()[match.end(1):]
  s=s[:block.start()]+replacement+s[block.end():]
  counts[name]=len(changes)
 def collider(m):
  b=m.group();t=re.search(r'transform = Transform3D\(([^)]*)\)',b)
  if not t:return b
  v=[x.strip() for x in t.group(1).split(',')];x,y,z=map(float,v[9:12])
  found=next((c for c in collider_changes if abs(c['x']-x)<.03 and abs(c['z']-z)<.03),None)
  if found:
   v[9]=format(found['next_x'],'.8g');v[10]=format(y+found['delta'],'.8g');v[11]=format(found['next_z'],'.8g')
   return b[:t.start(1)]+', '.join(v)+b[t.end(1):]
  return b
 s=re.sub(r'\[node [^\n]*type="CollisionShape3D"[^\n]*\][\s\S]*?(?=\n\[|\Z)',collider,s)
 p.write_text(s,encoding='utf-8')
print('UPDATED GROUNDED/CLEARED INSTANCES',sum(counts.values()),'GROUPS',len(counts))
(ROOT/'tools/.local/radio_tower/forest_grounding_applied.json').write_text(json.dumps(counts,indent=2))

