import bpy
from pathlib import Path
from mathutils import Vector
root=Path('D:/Github/ZSodaG')
scene=bpy.data.scenes.get('NorthernLab_Polar_Location')
assert scene
bpy.context.window.scene=scene
mat=bpy.data.materials.new('PolarLocation_Ice003_Snow006_Preview');mat.use_nodes=True
ns=mat.node_tree.nodes;links=mat.node_tree.links;bs=ns.get('Principled BSDF')
geo=ns.new('ShaderNodeNewGeometry')
def texture(path,scale,linear=False):
    uv=ns.new('ShaderNodeVectorMath');uv.operation='SCALE';uv.inputs[3].default_value=scale;links.new(geo.outputs['Position'],uv.inputs[0])
    tex=ns.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(root/path),check_existing=True);tex.projection='BOX';tex.projection_blend=.2;links.new(uv.outputs['Vector'],tex.inputs['Vector'])
    if linear:tex.image.colorspace_settings.name='Non-Color'
    return tex
ice=texture('assets/environments/snow/ice003/ice003_color.jpg',1/.9)
snow=texture('assets/environments/snow/snow006/color.jpg',1/2.4)
gray=ns.new('ShaderNodeRGBToBW');links.new(ice.outputs['Color'],gray.inputs[0])
ramp=ns.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].color=(.35,.46,.49,1);ramp.color_ramp.elements[1].color=(.60,.68,.70,1);links.new(gray.outputs[0],ramp.inputs[0])
attr=ns.new('ShaderNodeAttribute');attr.attribute_name='SnowCover'
mix=ns.new('ShaderNodeMixRGB');links.new(attr.outputs['Fac'],mix.inputs[0]);links.new(ramp.outputs['Color'],mix.inputs[1]);links.new(snow.outputs['Color'],mix.inputs[2]);links.new(mix.outputs[0],bs.inputs['Base Color'])
ice_n=texture('assets/environments/snow/ice003/ice003_normalgl.jpg',1/.9,True)
nmap=ns.new('ShaderNodeNormalMap');nmap.inputs['Strength'].default_value=.28;links.new(ice_n.outputs['Color'],nmap.inputs['Color']);links.new(nmap.outputs[0],bs.inputs['Normal'])
bs.inputs['Roughness'].default_value=.48
for ob in scene.objects:
    if ob.type=='MESH':ob.data.materials.clear();ob.data.materials.append(mat)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            sp=area.spaces.active;sp.region_3d.view_location=Vector((-110,105,-4));sp.region_3d.view_distance=55;sp.region_3d.view_rotation=Vector((20,-35,-25)).to_track_quat('-Z','Y');sp.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(root/'blender/polar_location/polar_location.blend'))
print('PASS materials installed in whole-location Blender scene; Godot remains visual authority')
