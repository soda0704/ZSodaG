"""Offline authoring of the native lower shaft scene; never used at runtime.

The sculpted surface sleeve stays short. This structural continuation closes
the sightlines beyond its bottom without putting a lid in the cabin's path.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "scenes/art/elevator/shaft_depth_enclosure.tscn"
blocks = []


def box(name, low, high):
    blocks.append((name, tuple((a + b) / 2 for a, b in zip(low, high)),
                   tuple(b - a for a, b in zip(low, high))))


def vector(values):
    return "Vector3(" + ", ".join(f"{value:.5f}" for value in values) + ")"


# Close the step between the rough sleeve and the narrower lower lining.
# Overlapping vertical walls alone still permit steep sightlines through that step.
box("TransitionNorth", (-7.5, -9.95, -7.5), (7.5, -9.8, -3.55))
box("TransitionSouth", (-7.5, -9.95, 3.55), (7.5, -9.8, 7.5))
box("TransitionEast", (3.55, -9.95, -3.55), (7.5, -9.8, 3.55))
box("TransitionWest", (-7.5, -9.95, -3.55), (-3.22, -9.8, 3.55))
box("NorthBedrock", (-3.85, -94, -3.85), (3.85, -9.8, -3.55))
box("SouthBedrock", (-3.85, -94, 3.55), (3.85, -9.8, 3.85))
box("EastBedrock", (3.55, -94, -3.85), (3.85, -9.8, 3.85))
box("WestNorthBedrock", (-3.32, -94, -3.85), (-3.22, -9.8, -2.68))
box("WestSouthBedrock", (-3.32, -94, 2.68), (-3.22, -9.8, 3.85))
top = -9.8
for floor in range(1, 6):
    y = -18.0 * floor
    # Existing landing door panels overlap this aperture on all four edges.
    box(f"WestBand{floor}", (-3.32, y + 4.1, -2.68), (-3.22, top, 2.68))
    # Seal the shaft-to-landing underside. It ends behind the moving cabin.
    box(f"LandingUnderside{floor}", (-6.5, y - 0.2, -2.8), (-3.05, y, 2.8))
    top = y
box("WestBottomBand", (-3.32, -94, -2.68), (-3.22, top, 2.68))
box("ShaftSump", (-3.85, -94, -3.85), (3.85, -93.6, 3.85))

parts = ['''[gd_scene format=3]

[ext_resource type="Texture2D" path="res://assets/environments/cave/pbr/rock_06_diff_2k.jpg" id="albedo"]
[ext_resource type="Texture2D" path="res://assets/environments/cave/pbr/rock_06_nor_gl_2k.jpg" id="normal"]
[ext_resource type="Texture2D" path="res://assets/environments/cave/pbr/rock_06_rough_2k.jpg" id="roughness"]

[sub_resource type="StandardMaterial3D" id="Bedrock"]
albedo_color = Color(0.65, 0.68, 0.70, 1)
albedo_texture = ExtResource("albedo")
roughness_texture = ExtResource("roughness")
normal_enabled = true
normal_scale = 0.65
normal_texture = ExtResource("normal")
uv1_scale = Vector3(0.45, 0.45, 0.45)
uv1_triplanar = true
uv1_world_triplanar = true
''']
for name, center, size in blocks:
    parts.append(f'''
[sub_resource type="BoxMesh" id="Mesh_{name}"]
material = SubResource("Bedrock")
size = {vector(size)}

[sub_resource type="BoxShape3D" id="Shape_{name}"]
size = {vector(size)}
''')
parts.append('''
[node name="ShaftDepthEnclosure" type="StaticBody3D"]
editor_description = "Opaque continuation below the short surface rock sleeve. Native editable walls, landing apertures and a sump below the lowest cabin stop; no surface roof or runtime generation."
collision_layer = 1
collision_mask = 0
metadata/footstep_surface = "concrete"
''')
for name, center, size in blocks:
    parts.append(f'''
[node name="{name}" type="MeshInstance3D" parent="."]
position = {vector(center)}
mesh = SubResource("Mesh_{name}")

[node name="{name}Collision" type="CollisionShape3D" parent="."]
position = {vector(center)}
shape = SubResource("Shape_{name}")
''')
OUT.write_text("".join(parts), encoding="utf-8")
print(f"Authored {OUT}: {len(blocks)} native wall/floor blocks")
