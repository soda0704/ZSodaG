"""Bake editor-authored floor geometry into paper survey SVGs and native Resources.
Run extract_journal_plans.gd first. Requires shapely only at authoring time.
"""
import json
import re
from xml.etree import ElementTree as ET
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from pathlib import Path
from shapely.geometry import Polygon, LineString
from shapely.ops import unary_union
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/ui/journal/maps"
TITLES = ["Главный этаж", "Контроль и связь", "Жизнеобеспечение", "Испытательный сектор", "Биосдерживание", "Экспедиционный сектор", "Нижняя выработка"]
LABELS = ["00", "−01", "−02", "−03", "−04", "−05", "ШАХТА"]
def outline_text(svg):
    # Godot's SVG importer does not typeset <text>; preserve printing as glyph paths.
    font=TTFont(ROOT/"assets/fonts/journal/body.ttf")
    glyphs=font.getGlyphSet(); cmap=font.getBestCmap(); units=font["head"].unitsPerEm
    def convert(match):
        el=ET.fromstring(match.group(0)); size=float(el.get("font-size","16")); scale=size/units
        spacing=float(el.get("letter-spacing","0"))/scale
        advance=sum(font["hmtx"][cmap[ord(ch)]][0]+spacing for ch in el.text)
        x=float(el.get("x","0")); y=float(el.get("y","0"))
        if el.get("text-anchor")=="end":x-=advance*scale
        paths=[]; at=0
        for ch in el.text:
            name=cmap.get(ord(ch),"space"); pen=SVGPathPen(glyphs);glyphs[name].draw(pen)
            paths.append(f'<path transform="translate({at},0)" d="{pen.getCommands()}"/>')
            at+=font["hmtx"][name][0]+spacing
        return f'<g fill="{el.get("fill","#4f594c")}" transform="translate({x},{y}) scale({scale}, {-scale})">'+"".join(paths)+"</g>"
    return re.sub(r'<text[^>]*>[^<]*</text>',convert,svg)
def path_of(g,project):
    if g.is_empty: return ""
    if hasattr(g,"geoms"): return " ".join(path_of(p,project) for p in g.geoms)
    if g.geom_type=="Polygon":
        rings=[g.exterior,*g.interiors]
        return " ".join("M"+" L".join("%.2f %.2f"%project(x,y) for x,y in ring.coords)+" Z" for ring in rings)
    return "M"+" L".join("%.2f %.2f"%project(x,y) for x,y in g.coords)
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    plans=json.loads((ROOT/"tools/.local/journal_plans.json").read_text())
    resources=[]
    for i,data in enumerate(plans):
        cave=i==6
        if cave:
            line=LineString(data["route"]).simplify(.5)
            floor=line.buffer(3.5).simplify(.4)
            walls=floor.boundary
        else:
            polygons=[Polygon(t) for t in data["floors"] if Polygon(t).area>.05]
            floor=unary_union(polygons+[Polygon([(-3,-3),(3,-3),(3,3),(-3,3)])]).buffer(.025).simplify(.025)
            walls=unary_union([LineString(t) for t in data["lines"] if LineString(t).length>.05]).simplify(.04)
        x0,z0,x1,z1=floor.bounds
        # Equal world-unit scale on both axes, with generous printed margins.
        w,h=x1-x0+6,z1-z0+6
        w=max(w,h*720/670);h=w*670/720
        cx,cz=(x0+x1)/2,(z0+z1)/2
        x0,z0=cx-w/2,cz-h/2
        def project(x,z):return (40+(x-x0)/w*720,65+(z-z0)/h*670)
        svg=['<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" width="800" height="850" viewBox="0 0 800 850">',
        '<defs><pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse"><path d="M40 0 H0 V40" fill="none" stroke="#6f796b" stroke-opacity=".13" stroke-width=".7"/></pattern><linearGradient id="paper" x2="1" y2="1"><stop stop-color="#e1d7b9"/><stop offset=".48" stop-color="#f0e7cf"/><stop offset="1" stop-color="#cec3a1"/></linearGradient></defs>',
        '<path d="M7 13 L782 5 L794 831 L19 845 Z" fill="#463c2d" opacity=".16"/><path d="M3 6 L775 0 L788 820 L10 835 Z" fill="url(#paper)" stroke="#8e8061" stroke-width="1.5"/><path d="M30 45 H758 V754 H30 Z" fill="url(#grid)"/>',
        '<path d="M265 9 L269 825 M533 7 L537 824 M8 420 L781 414" stroke="#918366" stroke-width="2" opacity=".2"/><path d="M268 9 L272 825 M536 7 L540 824 M8 423 L781 417" stroke="#fff8e4" stroke-width="2" opacity=".45"/>',
        '<path d="M30 60 V35 H80 M720 35 H760 V60 M30 735 V760 H80 M720 760 H760 V735" fill="none" stroke="#7e7056" stroke-width="1"/>',
        '<path d="'+path_of(floor,project)+'" fill="#b4b39c" fill-opacity=".42" stroke="#575c50" stroke-width="2.1" fill-rule="evenodd" stroke-linejoin="round"/>',
        '<path d="'+path_of(walls,project)+'" fill="none" stroke="#38483f" stroke-opacity=".8" stroke-width="1.1" stroke-linecap="round"/>']
        if cave: svg.append('<path d="'+path_of(line,project)+'" fill="none" stroke="#84634c" stroke-opacity=".65" stroke-width="1.3" stroke-dasharray="6 5"/>')
        else:
            ex,ez=project(0,0)
            svg.append(f'<rect x="{ex-8}" y="{ez-8}" width="16" height="16" fill="#eee6ce" stroke="#8d4e3a" stroke-width="2"/><path d="M{ex-3} {ez+4} L{ex} {ez-3} L{ex+3} {ez+4}" fill="none" stroke="#8d4e3a" stroke-width="1.6"/>')
        svg.append('<path d="M714 116 V73 L706 91 M714 73 L722 91" stroke="#4f594c" fill="none" stroke-width="2"/><text x="708" y="65" font-family="serif" font-size="17" fill="#4f594c">N</text>')
        length=100 if cave else 10
        px=length/w*720
        svg.append(f'<path d="M48 788 v-5 h{px:.2f} v5 M48 786 h{px:.2f}" stroke="#4f594c" fill="none" stroke-width="2"/><text x="48" y="811" font-family="serif" font-size="16" fill="#4f594c">0 — {length} m</text><text x="745" y="802" text-anchor="end" font-family="serif" font-size="14" letter-spacing="3" fill="#7a6b52">NL / {i:02d}</text></svg>')
        (OUT/f"floor_{i}.svg").write_text(outline_text("".join(svg)),encoding="utf-8")
        resource=f'''[gd_resource type="Resource" script_class="JournalMapFloor" load_steps=3 format=3]
[ext_resource type="Script" path="res://scripts/ui/journal_map_floor.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/ui/journal/maps/floor_{i}.svg" id="2"]
[resource]
script = ExtResource("1")
title = "{TITLES[i]}"
level_label = "{LABELS[i]}"
elevation = {data["elevation"]}
scene_root = NodePath("{data["root"]}")
plan = ExtResource("2")
world_rect = Rect2({x0}, {z0}, {w}, {h})
'''
        (OUT/f"floor_{i}.tres").write_text(resource,encoding="utf-8")
        resources.append(f'[ext_resource type="Resource" path="res://assets/ui/journal/maps/floor_{i}.tres" id="f{i}"]')
    atlas='[gd_resource type="Resource" script_class="JournalAtlas" format=3]\n[ext_resource type="Script" path="res://scripts/ui/journal_atlas.gd" id="atlas"]\n[ext_resource type="Script" path="res://scripts/ui/journal_map_floor.gd" id="floor"]\n'+"\n".join(resources)+'\n[resource]\nscript = ExtResource("atlas")\nfloors = Array[ExtResource("floor")](['+", ".join(f'ExtResource("f{i}")' for i in range(7))+'])\n'
    (OUT/"atlas.tres").write_text(atlas,encoding="utf-8")
    print("Authored seven survey sheets and atlas resources")
if __name__ == "__main__":main()
