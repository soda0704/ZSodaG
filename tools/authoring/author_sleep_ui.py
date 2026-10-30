"""Write editable native Godot clips and vector power-switch frames."""
from pathlib import Path
import math
import re

ROOT = Path(__file__).resolve().parents[2]


def track(path, times, values):
    return (path, times, values)


def animation(name, duration, tracks):
    result = f'[sub_resource type="Animation" id="{name}"]\nresource_name = "{name}"\nlength = {duration}\n'
    for i, (path, times, values) in enumerate(tracks):
        scalar = not values[0].startswith(('Vector', 'Color'))
        if scalar:
            # Bake smoothstep keys: cubic interpolation overshoots held eye/align values.
            baked_times, baked_values = [], []
            for frame in range(round(duration * 60) + 1):
                t = min(frame / 60, duration)
                segment = next((j for j in range(len(times)-1) if t <= times[j+1]), len(times)-2)
                w = max(0, min(1, (t-times[segment])/(times[segment+1]-times[segment])))
                w = w*w*(3-2*w)
                baked_times.append(round(t, 6))
                baked_values.append(str(float(values[segment])*(1-w)+float(values[segment+1])*w))
            times, values = baked_times, baked_values
        result += (f'tracks/{i}/type = "value"\ntracks/{i}/path = NodePath("{path}")\n'
                   f'tracks/{i}/interp = {1 if scalar or values[0].startswith("Color") else 2}\ntracks/{i}/keys = {{"times": PackedFloat32Array({", ".join(map(str, times))}), '
                   f'"transitions": PackedFloat32Array({", ".join("1" for _ in times)}), "update": 0, "values": [{", ".join(values)}]}}\n')
    return result + '\n'


pose = '[gd_scene format=3]\n\n[ext_resource type="Script" path="res://scripts/characters/components/bunk_sleep_presentation.gd" id="script"]\n\n'
pose += animation('lie_down', 1.25, [
    track('.:progress', [0, 1.25], ['0.0', '1.0']),
    track('.:alignment', [0, .7, 1.25], ['0.0', '1.0', '1.0']),
    track('.:eye_openness', [0, .65, .88, 1.25], ['1.0', '1.0', '.72', '0.0']),
    track('CameraPose:position', [0, .48, .85, 1.25], ['Vector3(0,1.65,0)', 'Vector3(.42,.98,-.5)', 'Vector3(.12,.55,-.9)', 'Vector3(0,.30,-1.22)']),
    track('CameraPose:rotation', [0, .48, .85, 1.25], ['Vector3(0,0,0)', 'Vector3(.18,0,.025)', 'Vector3(.86,0,.015)', 'Vector3(1.5707963,0,0)']),
])
pose += animation('get_up', 1.4, [
    track('.:progress', [0, 1.4], ['0.0', '1.0']),
    track('.:alignment', [0, .25, 1.4], ['0.0', '0.0', '1.0']),
    track('.:eye_openness', [0, .18, .6, 1.4], ['0.0', '.18', '1.0', '1.0']),
    track('CameraPose:position', [0, .7, 1.4], ['Vector3(0,.30,-1.22)', 'Vector3(.2,1.1,-.45)', 'Vector3(0,1.65,0)']),
    track('CameraPose:rotation', [0, .7, 1.4], ['Vector3(1.5707963,0,0)', 'Vector3(.40,0,-.018)', 'Vector3(0,0,0)']),
])
pose += '''[sub_resource type="AnimationLibrary" id="clips"]
_data = {&"lie_down": SubResource("lie_down"), &"get_up": SubResource("get_up")}

[node name="BunkSleep" type="Node3D"]
script = ExtResource("script")

[node name="CameraPose" type="Node3D" parent="."]

[node name="AnimationPlayer" type="AnimationPlayer" parent="."]
process_priority = -50
libraries = {&"": SubResource("clips")}
'''
pose = re.sub(r'(?<![\w\d])(-?)\.(\d)', r'\g<1>0.\2', pose)
(ROOT / 'scenes/characters/bunk_sleep.tscn').write_text(pose, encoding='utf-8')

folder = ROOT / 'assets/ui/power_switch'
folder.mkdir(parents=True, exist_ok=True)
for i in range(21):
    # A 3D prism projected into a vector icon, pivoting about its back edge.
    angle = math.radians(48 - 96 * i / 20)
    depth = 57 * math.cos(angle)
    tip = (119 + depth * .43, 127 + math.sin(angle) * 60)
    a, b = (94, 127), (132, 127)
    c, d = (tip[0]+19, tip[1]), (tip[0]-19, tip[1])
    def points(seq): return ' '.join(f'{x:.2f},{y:.2f}' for x, y in seq)
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<g stroke="#efefe8" stroke-width="4" stroke-linecap="round" stroke-linejoin="round">
<path d="M57 28 187 28 187 224 57 224Z" fill="#111a20" fill-opacity=".65"/>
<path d="M57 28 49 36 49 230 179 230 187 224M49 230 57 224M49 36 57 36" fill="none" opacity=".65"/>
<g fill="none" stroke-width="2.5"><circle cx="69" cy="40" r="3"/><circle cx="175" cy="40" r="3"/><circle cx="69" cy="212" r="3"/><circle cx="175" cy="212" r="3"/></g>
<path d="M91 95 135 95 135 161 91 161Z" fill="#080f14"/>
<polygon points="{points([a,b,c,d])}" fill="#56656b"/>
<polygon points="{points([d,c,(c[0],c[1]+10),(d[0],d[1]+10)])}" fill="#d8ddd6"/>
<polygon points="{points([a,d,(d[0],d[1]+10),(a[0],a[1]+10)])}" fill="#293a43"/>
</g>
<g fill="none" stroke="#efefe8" stroke-width="3.3" stroke-linecap="round" stroke-linejoin="round">
<path d="M101 61c-10 0-10 17 0 17s10-17 0-17M117 78V61l13 17V61"/>
<path d="M91 179c-10 0-10 17 0 17s10-17 0-17M108 196v-17h10m-10 8h8M127 196v-17h10m-10 8h8"/>
</g></svg>'''
    (folder / f'switch_{i:02}.svg').write_text(svg, encoding='utf-8')

frames = '[gd_resource type="SpriteFrames" format=3]\n\n'
for i in range(21):
    frames += f'[ext_resource type="Texture2D" path="res://assets/ui/power_switch/switch_{i:02}.svg" id="f{i}"]\n'
frames += '\n[resource]\nanimations = [\n'
for name, indices in [('on', range(21)), ('off', reversed(range(21)))]:
    entries = ', '.join(f'{{"duration": 1.0, "texture": ExtResource("f{i}")}}' for i in indices)
    frames += f'{{"frames": [{entries}], "loop": false, "name": &"{name}", "speed": 36.0}},\n'
frames += ']\n'
(folder / 'switch_frames.tres').write_text(frames, encoding='utf-8')
notice = '''[gd_scene format=3]
[ext_resource type="Script" path="res://scripts/ui/power_switch_notice.gd" id="script"]
[ext_resource type="SpriteFrames" path="res://assets/ui/power_switch/switch_frames.tres" id="frames"]
[ext_resource type="Font" path="res://assets/fonts/hud/body.tres" id="font"]

'''
notice += animation('notice', 2.6, [track('Panel:modulate', [0, .16, 2.1, 2.6], ['Color(1,1,1,0)', 'Color(1,1,1,1)', 'Color(1,1,1,1)', 'Color(1,1,1,0)'])])
notice += '''[sub_resource type="AnimationLibrary" id="clips"]
_data = {&"notice": SubResource("notice")}

[sub_resource type="StyleBoxFlat" id="panel"]
bg_color = Color(.035,.05,.057,.72)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(.63,.72,.73,.26)
corner_radius_top_left = 5
corner_radius_top_right = 5
corner_radius_bottom_left = 5
corner_radius_bottom_right = 5

[node name="PowerSwitchNotice" type="Control"]
visible = false
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -352.0
offset_top = 42.0
offset_right = -32.0
offset_bottom = 140.0
grow_horizontal = 0
mouse_filter = 2
script = ExtResource("script")

[node name="Panel" type="Panel" parent="."]
layout_mode = 0
offset_right = 320.0
offset_bottom = 98.0
mouse_filter = 2
theme_override_styles/panel = SubResource("panel")

[node name="Icon" type="AnimatedSprite2D" parent="Panel"]
position = Vector2(47,49)
scale = Vector2(.34,.34)
sprite_frames = ExtResource("frames")
animation = &"on"

[node name="Title" type="Label" parent="Panel"]
offset_left = 88.0
offset_top = 34.0
offset_right = 309.0
offset_bottom = 66.0
mouse_filter = 2
theme_override_fonts/font = ExtResource("font")
theme_override_font_sizes/font_size = 21
theme_override_colors/font_color = Color(.94,.94,.91,1)
text = "Питание включено"

[node name="AnimationPlayer" type="AnimationPlayer" parent="."]
libraries = {&"": SubResource("clips")}
'''
notice = re.sub(r'(?<![\w\d])(-?)\.(\d)', r'\g<1>0.\2', notice)
(ROOT / 'scenes/ui/power_switch_notice.tscn').write_text(notice, encoding='utf-8')
print('Native sleep motion and vector switch frames authored.')
