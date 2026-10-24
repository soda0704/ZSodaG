"""Write the editable native loading scene and its supplied atom's texture track."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]


def main():
    lines = ['[gd_scene format=3]',
             '[ext_resource type="Script" path="res://scripts/ui/loading_screen.gd" id="logic"]',
             '[ext_resource type="Script" path="res://scripts/ui/loading_tip.gd" id="tip"]',
             '[ext_resource type="Theme" path="res://scenes/ui/northern_lab_hud_theme.tres" id="theme"]',
             '[ext_resource type="VideoStream" path="res://assets/ui/loading/vhs_01.ogv" id="video"]',
             '[ext_resource type="AudioStream" path="res://assets/audio/music/loading_northernlab.ogg" id="music"]',
             '[ext_resource type="Texture2D" path="res://assets/ui/loading/atom_atlas.png" id="atlas"]']
    tips = [
        ('Прислушивайся.', 'Бег и выстрелы привлекают внимание. Пригнувшись, можно остаться незамеченным чуть дольше.'),
        ('Свет не бесконечен.', 'Берегите заряд — неизвестно, сколько ещё находиться в темноте.'),
        ('Делитесь с напарником.', 'Удерживайте {offer_item}, чтобы протянуть предмет.'),
        ('Вдвоём легче.', 'Удерживайте {interact}, чтобы тащить предмет. С напарником его можно приподнять.'),
        ('Журнал экспедиции.', 'Задачи, найденные записи и ваши вещи — в журнале. Просмотреть — {journal}.'),
    ]
    for i, (title, body) in enumerate(tips):
        lines += [f'[sub_resource type="Resource" id="tip{i}"]', 'script = ExtResource("tip")',
                  'title = ' + json.dumps(title, ensure_ascii=False), 'body = ' + json.dumps(body, ensure_ascii=False)]
    for i in range(57):
        lines += [f'[sub_resource type="AtlasTexture" id="frame{i}"]', 'atlas = ExtResource("atlas")',
                  f'region = Rect2({i % 8 * 160}, {i // 8 * 160}, 160, 160)', 'filter_clip = true']
    lines += ['[sub_resource type="Animation" id="atom"]', 'resource_name = "atom"', 'length = 1.9', 'loop_mode = 1',
              'tracks/0/type = "value"', 'tracks/0/path = NodePath("Footer/Content/Status/Atom:texture")',
              'tracks/0/interp = 0', 'tracks/0/keys = {',
              '"times": PackedFloat32Array(' + ', '.join(f'{i / 30:.7f}' for i in range(57)) + '),',
              '"transitions": PackedFloat32Array(' + ', '.join('1' for _ in range(57)) + '),',
              '"update": 1,', '"values": [' + ', '.join(f'SubResource("frame{i}")' for i in range(57)) + ']}',
              '[sub_resource type="AnimationLibrary" id="library"]', '_data = {&"atom": SubResource("atom")}',
              '[sub_resource type="Gradient" id="gradient"]', 'offsets = PackedFloat32Array(0, 0.5, 1)',
              'colors = PackedColorArray(0.008, 0.01, 0.011, 0.04, 0.008, 0.01, 0.011, 0.38, 0.008, 0.01, 0.011, 0.98)',
              '[sub_resource type="GradientTexture2D" id="shade"]', 'gradient = SubResource("gradient")',
              'width = 8', 'height = 512', 'fill_from = Vector2(0, 0)', 'fill_to = Vector2(0, 1)',
              '[node name="LoadingScreen" type="Control"]', 'visible = false', 'layout_mode = 3', 'anchors_preset = 15',
              'anchor_right = 1.0', 'anchor_bottom = 1.0', 'grow_horizontal = 2', 'grow_vertical = 2',
              'mouse_filter = 0', 'process_mode = 3', 'theme = ExtResource("theme")', 'script = ExtResource("logic")',
              'videos = Array[VideoStream]([ExtResource("video")])',
              'tips = Array[ExtResource("tip")]([' + ', '.join(f'SubResource("tip{i}")' for i in range(5)) + '])']

    def node(name, kind, parent, props):
        lines.append(f'[node name="{name}" type="{kind}" parent="{parent}"]')
        lines.extend(props.splitlines())

    fullscreen = 'layout_mode = 1\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\ngrow_horizontal = 2\ngrow_vertical = 2\nmouse_filter = 2'
    node('Black', 'ColorRect', '.', fullscreen + '\ncolor = Color(0.008, 0.01, 0.011, 1)')
    node('VideoFrame', 'AspectRatioContainer', '.', fullscreen + '\nclip_contents = true\nratio = 1.7777778\nstretch_mode = 3')
    node('Video', 'VideoStreamPlayer', 'VideoFrame', 'layout_mode = 2\nmouse_filter = 2\nexpand = true\nloop = true\nvolume_db = -80.0')
    node('Shade', 'TextureRect', '.', fullscreen + '\ntexture = SubResource("shade")\nexpand_mode = 1')
    node('Footer', 'MarginContainer', '.', 'layout_mode = 0\nanchor_top = 1.0\nanchor_bottom = 1.0\noffset_top = -270.0\noffset_right = 1920.0\nmouse_filter = 2\ntheme_override_constants/margin_left = 56\ntheme_override_constants/margin_right = 56\ntheme_override_constants/margin_bottom = 36')
    node('Content', 'VBoxContainer', 'Footer', 'layout_mode = 2\nmouse_filter = 2\ntheme_override_constants/separation = 12')
    node('Status', 'HBoxContainer', 'Footer/Content', 'layout_mode = 2\nmouse_filter = 2\ntheme_override_constants/separation = 14')
    node('Atom', 'TextureRect', 'Footer/Content/Status', 'layout_mode = 2\ncustom_minimum_size = Vector2(62, 62)\nmouse_filter = 2\ntexture = SubResource("frame0")\nexpand_mode = 1\nstretch_mode = 5')
    node('TransitionLabel', 'Label', 'Footer/Content/Status', 'unique_name_in_owner = true\nlayout_mode = 2\nsize_flags_vertical = 4\ntheme_type_variation = &"HudHeading"\ntheme_override_font_sizes/font_size = 20\ntext = "ПОСАДКА У БАЗЫ…"')
    node('Rule', 'ColorRect', 'Footer/Content', 'layout_mode = 2\ncustom_minimum_size = Vector2(0, 1)\nmouse_filter = 2\ncolor = Color(0.886, 0.678, 0.302, 0.3)')
    node('TipTitle', 'Label', 'Footer/Content', 'unique_name_in_owner = true\nlayout_mode = 2\ntheme_override_font_sizes/font_size = 24\ntext = "Прислушивайся."')
    node('TipBody', 'Label', 'Footer/Content', 'unique_name_in_owner = true\nlayout_mode = 2\nsize_flags_vertical = 3\ncustom_minimum_size = Vector2(0, 60)\ntheme_override_font_sizes/font_size = 22\nautowrap_mode = 2\ntext = "Бег и выстрелы привлекают внимание."')
    node('NextHint', 'Label', 'Footer/Content', 'unique_name_in_owner = true\nlayout_mode = 2\ntheme_override_font_sizes/font_size = 18\ntheme_override_colors/font_color = Color(0.68, 0.7, 0.67, 1)\ntext = "01 / 05     [ Пробел ] — Следующая подсказка"')
    node('Music', 'AudioStreamPlayer', '.', 'stream = ExtResource("music")\nbus = &"Music"\nvolume_db = -80.0')
    node('AnimationPlayer', 'AnimationPlayer', '.', 'libraries = {&"": SubResource("library")}')
    (ROOT / 'scenes/ui/loading_screen.tscn').write_text('\n'.join(lines).replace('\n[', '\n\n[') + '\n', encoding='utf8')


if __name__ == '__main__':
    main()
