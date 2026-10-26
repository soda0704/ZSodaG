"""Bake coherent material maps onto unchanged user geometry, using physical wear masks."""
import bpy,bmesh,numpy as np,math,json,hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parent
OUT=ROOT.parents[2]/'assets/models/doors/living_hermetic_door'
TEX=OUT/'textures/realistic_2k'; N=2048
INPUT=ROOT/'living_hermetic_door_prepared.blend'
bpy.ops.wm.open_mainfile(filepath=str(INPUT))
scene=bpy.context.scene
meshes=[o for o in scene.objects if o.type=='MESH']
original={o.name:([tuple(v.co) for v in o.data.vertices],[tuple(p.vertices) for p in o.data.polygons],list(o.matrix_world)) for o in meshes}
def active(o):
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
def read_image(path):
    im=bpy.data.images.load(str(path),check_existing=True)
    a=np.empty(im.size[0]*im.size[1]*4,np.float32);im.pixels.foreach_get(a)
    return a.reshape(im.size[1],im.size[0],4)[:,:,:3]
micro=read_image(TEX/'paint_microheight_source.png').mean(2)
frame_ref=np.flipud(read_image(TEX/'reference_frame_color.png'))
door_ref=np.flipud(read_image(TEX/'reference_doors_color.png'))
# Albedo reference crops contain material interiors, not the incompatible drawn outlines.
patches=[frame_ref[35:95,200:1000],door_ref[200:440,210:440],door_ref[957:1010,160:510],door_ref[601:621,120:520]]
patches=[p/np.maximum(p.mean((0,1)),.001) for p in patches]
groups={'frame':[o for o in meshes if not ('Leaf' in o.name or 'Lenses' in o.name)],'doors':[o for o in meshes if 'Leaf' in o.name]}
materials_before={o.name:[o.data.materials[p.material_index].name for p in o.data.polygons] for o in meshes}
for group,obs in groups.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0]
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.select_all(action='SELECT')
    bpy.ops.uv.average_islands_scale();bpy.ops.uv.pack_islands(rotate=True,margin=.003,shape_method='CONCAVE')
    bpy.ops.object.mode_set(mode='OBJECT')

def noise(p,scale):
    q=p*scale;cell=np.floor(q);f=q-cell;f=f*f*(3-2*f)
    result=np.zeros(len(p),np.float32)
    for x in [0,1]:
        for y in [0,1]:
            for z in [0,1]:
                c=cell+np.array([x,y,z]);h=np.sin(c@np.array([127.1,311.7,74.7]))*43758.5453;h=h-np.floor(h)
                result+=h*np.prod(np.where(np.array([x,y,z]),f,1-f),axis=1)
    return result
def sample(img,u,v):
    h,w=img.shape[:2];x=(np.mod(u,1)*(w-1)).astype(int);y=(np.mod(v,1)*(h-1)).astype(int)
    return img[y,x]
def segdist(p,a,b):
    v=b-a; t=np.clip((p-a)@v/max(float(v@v),1e-12),0,1)
    return np.linalg.norm(p-a-t[:,None]*v,axis=1)
rng=np.random.default_rng(3371)
scratches=[]
for i in range(62):
    a=np.array([rng.uniform(-1.5,1.5),rng.uniform(.08,2.95)])
    angle=rng.uniform(-.6,.6);length=rng.uniform(.022,.24)
    b=a+length*np.array([math.cos(angle),math.sin(angle)])
    scratches.append((a,b,rng.uniform(.0020,.0032)))

def evaluate(p,normal,category,convex,concave):
    coarse=noise(p,7); fine=noise(p,100);medium=noise(p,29)
    axis=int(np.argmax(np.abs(normal))); axes=[i for i in range(3) if i!=axis]
    u=p[:,axes[0]];v=p[:,axes[1]]
    grain=sample(micro,u*.9,v*.9)
    grain=np.clip((grain-.48)*3,-.7,.7)
    refs=sample(patches[min(category,3)],u*.65,v*.65)
    dist=np.full(len(p),100,np.float32)
    for a,b in convex:dist=np.minimum(dist,segdist(p,a,b))
    inset=np.full(len(p),100,np.float32)
    for a,b in concave:inset=np.minimum(inset,segdist(p,a,b))
    edge=np.exp(-dist/.004)
    chips=np.clip((edge*(.35+medium*1.3)+fine*.23-.62)*3.8,0,1)
    rub=np.exp(-dist/.011)*(.35+coarse*.65)
    grime=np.exp(-inset/.019)*(.25+fine*.75)
    abrasion=np.zeros(len(p),np.float32)
    if abs(normal[1])>.7:
        xz=p[:,[0,2]]
        for a,b,width in scratches:
            if a[0]>xz[:,0].max()+.26 or b[0]<xz[:,0].min()-.26 or a[1]>xz[:,1].max()+.26 or a[1]<xz[:,1].min()-.26:continue
            abrasion=np.maximum(abrasion,np.exp(-(segdist(xz,a,b)/width)**2))
    if category==2:chips*=.08;abrasion*=.3
    base=np.array([( .065,.077,.079),(.30,.315,.31),(.022,.027,.025),(.082,.151,.10),(.10,.112,.118)][category])
    rgb=base[None,:]*(.93+coarse[:,None]*.1+grain[:,None]*.06)
    rgb*=np.clip(refs,.45,1.7)*.55+.45
    rgb*=1-grime[:,None]*.48
    rubbed=base*1.14
    rgb=rgb*(1-rub[:,None]*.18)+rubbed*rub[:,None]*.18
    exposed=np.maximum(chips,abrasion*.65)
    metalcolor=np.array([.38,.39,.37])
    rgb=rgb*(1-exposed[:,None])+metalcolor*exposed[:,None]
    oxide=chips*np.clip((coarse-.57)*4,0,.65)
    rgb=rgb*(1-oxide[:,None])+np.array([.115,.06,.025])*oxide[:,None]
    rough=[.44,.38,.79,.46,.32][category]+(coarse-.5)*.19+grain*.09+grime*.13
    rough=rough*(1-exposed)+(.29+fine*.10)*exposed
    metallic=np.full(len(p),.02 if category<4 else .78)+exposed*.81
    metallic*=1-oxide*.8
    height=grain*(.00027 if category!=2 else .00014)-exposed*.00018+grime*.00006
    # AO represents shallow material cavities only; no lighting enters Base Color.
    ao=1-grime*.20-np.maximum(-grain,0)*.05
    return rgb,np.stack([ao,np.clip(rough,.12,.92),np.clip(metallic,0,1)],axis=1),height

def save(name,rgb,color=False):
    img=bpy.data.images.new(name,width=N,height=N,alpha=False)
    img.colorspace_settings.name='sRGB' if color else 'Non-Color'
    rgba=np.ones((N,N,4),np.float32);rgba[:,:,:3]=np.clip(rgb,0,1)
    img.pixels.foreach_set(rgba.ravel());img.filepath_raw=str(TEX/(name+'.png'));img.file_format='PNG';img.save();img.pack()
    return img
textures={};stats={}
for group,obs in groups.items():
    rgb=np.zeros((N,N,3),np.float32);orm=np.ones_like(rgb);height=np.zeros((N,N),np.float32);coverage=np.zeros((N,N),bool);density=np.zeros((N,N),np.float32)
    for o in obs:
        bm=bmesh.new();bm.from_mesh(o.data);bm.faces.ensure_lookup_table()
        edgegroups={}
        for f in bm.faces:
            conv=[];conc=[]
            for e in f.edges:
                if len(e.link_faces)==2 and e.calc_face_angle()<math.radians(24):continue
                a,b=[np.array(o.matrix_world@v.co) for v in e.verts]
                (conv if e.is_boundary or e.is_convex else conc).append((a,b))
            edgegroups[f.index]=(conv,conc)
        bm.free();o.data.calc_loop_triangles();uv=o.data.uv_layers.active.data
        for tri in o.data.loop_triangles:
            p=o.data.polygons[tri.polygon_index]
            coords=np.array([uv[i].uv for i in tri.loops])*N
            lo=np.maximum(np.floor(coords.min(0)).astype(int),0);hi=np.minimum(np.ceil(coords.max(0)).astype(int),N-1)
            if np.any(hi<lo):continue
            xx,yy=np.meshgrid(np.arange(lo[0],hi[0]+1),np.arange(lo[1],hi[1]+1));pts=np.stack([xx.ravel()+.5,yy.ravel()+.5],axis=1)
            a,b,c=coords;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
            if abs(den)<1e-8:continue
            w0=((b[1]-c[1])*(pts[:,0]-c[0])+(c[0]-b[0])*(pts[:,1]-c[1]))/den
            w1=((c[1]-a[1])*(pts[:,0]-c[0])+(a[0]-c[0])*(pts[:,1]-c[1]))/den
            w2=1-w0-w1;inside=(w0>=-1e-6)&(w1>=-1e-6)&(w2>=-1e-6)
            if not inside.any():continue
            world=np.array([o.matrix_world@o.data.vertices[i].co for i in tri.vertices])
            points=np.stack([w0[inside],w1[inside],w2[inside]],axis=1)@world
            mat=materials_before[o.name][p.index]
            category=0 if group=='frame' else {'M_Door_Leaf':1,'M_Door_Recess_Seal':2,'M_Living_Accent':3,'M_Door_Frame':0}[mat]
            if 'Fasteners' in o.name:category=4
            col,phys,h=evaluate(points,np.array(p.normal),category,*edgegroups[p.index])
            x=xx.ravel()[inside];y=yy.ravel()[inside]
            rgb[y,x]=col;orm[y,x]=phys;height[y,x]=h;coverage[y,x]=True
            area=np.linalg.norm(np.cross(world[1]-world[0],world[2]-world[0]))
            density[y,x]=math.sqrt(abs(den)/max(area,1e-12))
        print('RASTERIZED',group,o.name,flush=True)
    stats[group]={'uv_coverage':float(coverage.mean()),'median_pixels_per_meter':float(np.median(density[coverage]))}
    # Twelve-pixel nearest-neighbour dilation protects mipmaps and height derivatives.
    filled=coverage.copy()
    for step in range(12):
        old=filled.copy()
        for dy,dx in [(-1,0),(1,0),(0,-1),(0,1)]:
            src=np.roll(old,(dy,dx),(0,1));take=src&~filled
            for data in [rgb,orm,height,density]:data[take]=np.roll(data,(dy,dx),(0,1))[take]
            filled|=take
    gy,gx=np.gradient(height)
    normal=np.stack([-gx*density,-gy*density,np.ones((N,N))],axis=2)
    normal/=np.linalg.norm(normal,axis=2,keepdims=True);normal=normal*.5+.5
    textures[group]={'BaseColor':save(group+'_BaseColor',rgb,True),'ORM':save(group+'_ORM',orm),'Normal':save(group+'_Normal',normal)}
    save(group+'_Height',np.repeat(np.clip(.5+height*500,0,1)[:,:,None],3,2))
    print('BAKED',group,stats[group],flush=True)

def material(name,group):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name);m.use_nodes=True;nt=m.node_tree;nt.nodes.clear()
    bs=nt.nodes.new('ShaderNodeBsdfPrincipled');out=nt.nodes.new('ShaderNodeOutputMaterial');nt.links.new(bs.outputs[0],out.inputs[0]);out.location=(400,0)
    tex=nt.nodes.new('ShaderNodeTexImage');tex.image=textures[group]['BaseColor'];tex.location=(-650,250);nt.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    tex=nt.nodes.new('ShaderNodeTexImage');tex.image=textures[group]['ORM'];tex.location=(-650,-20)
    sp=nt.nodes.new('ShaderNodeSeparateColor');sp.location=(-350,-20);nt.links.new(tex.outputs['Color'],sp.inputs[0]);nt.links.new(sp.outputs['Green'],bs.inputs['Roughness']);nt.links.new(sp.outputs['Blue'],bs.inputs['Metallic'])
    gn=nt.nodes.new('ShaderNodeGroup');gn.node_tree=bpy.data.node_groups['glTF Material Output'];nt.links.new(sp.outputs['Red'],gn.inputs['Occlusion']);gn.location=(-80,-200)
    tex=nt.nodes.new('ShaderNodeTexImage');tex.image=textures[group]['Normal'];tex.location=(-650,-350)
    no=nt.nodes.new('ShaderNodeNormalMap');no.location=(-330,-300);nt.links.new(tex.outputs['Color'],no.inputs['Color']);nt.links.new(no.outputs['Normal'],bs.inputs['Normal'])
    return m
fm=material('M_Door_Frame','frame')
dm={name:material(name,'doors') for name in ['M_Door_Leaf','M_Door_Recess_Seal','M_Living_Accent']}
for o in groups['frame']:
    o.data.materials.clear();o.data.materials.append(fm)
    for p in o.data.polygons:p.material_index=0
for o in groups['doors']:
    before=materials_before[o.name];o.data.materials.clear()
    for m in dm.values():o.data.materials.append(m)
    for p in o.data.polygons:p.material_index={'M_Door_Recess_Seal':1,'M_Living_Accent':2}.get(before[p.index],0)
for o in meshes:
    assert original[o.name][0]==[tuple(v.co) for v in o.data.vertices]
    assert original[o.name][1]==[tuple(p.vertices) for p in o.data.polygons]
    assert original[o.name][2]==list(o.matrix_world)
stats['geometry_unchanged']=True;stats['texture_resolution']=2048
stats['source']='User BaseColor material-interior references plus imagegen microheight; unified geometry-based physical wear masks. Original mismatched normal/metallic/roughness/AO not used.'
(ROOT/'realistic_validation.json').write_text(json.dumps(stats,indent=2))
bpy.data.orphans_purge(do_recursive=True)
active(bpy.data.objects['LivingHermeticDoor'])
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'living_hermetic_door_realistic_2k.blend'))
for o in meshes:
    active(o);m=o.modifiers.new('Export tessellation','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=m.name)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=str(OUT/'living_hermetic_door.glb'),export_format='GLB',use_selection=True,export_animations=False,export_extras=True,export_cameras=False,export_lights=False,export_tangents=True)

scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True
scene.render.resolution_x=1400;scene.render.resolution_y=1400;scene.render.resolution_percentage=100
scene.world.color=(.15,.15,.15);scene.view_settings.view_transform='AgX'
def aim(o,target=(0,0,1.5)):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
for loc,power,size in [((-3,-2,4.5),1150,2.5),((4,-1,2.8),650,3),((0,3,4),1100,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;aim(o)
bpy.ops.object.camera_add(location=(3.2,-7,3.3));cam=bpy.context.object;cam.data.type='ORTHO';cam.data.ortho_scale=4.1;aim(cam);scene.camera=cam
scene.render.filepath=str(ROOT/'realistic_front.png');bpy.ops.render.render(write_still=True)
cam.location=(-2.8,7,3.2);aim(cam)
for o in scene.objects:
    if o.type=='LIGHT':o.location.y=-o.location.y;aim(o)
scene.render.filepath=str(ROOT/'realistic_back.png');bpy.ops.render.render(write_still=True)
for o in scene.objects:
    if o.type=='LIGHT':o.location.y=-o.location.y;aim(o)
cam.location=(-1.8,-4,2.6);cam.data.ortho_scale=1.22;aim(cam,(-.86,0,1.88))
scene.render.filepath=str(ROOT/'realistic_detail.png');bpy.ops.render.render(write_still=True)
print('REALISTIC_COMPLETE',stats)
