// Terrain3D generated autoshader, retained with a local replacement-surface cutout.
// Regenerate from Terrain3D when upgrading the addon; preserve the three cutout additions.
shader_type spatial;
uniform vec4 ridge_snow_bounds = vec4(210.0, 280.0, -366.0, 366.0);
uniform float ridge_snow_amount : hint_range(0.0, 1.0) = 0.65;
uniform vec4 ridge_snow_color : source_color = vec4(0.82, 0.88, 0.92, 1.0);
uniform vec4 cliff_replacement_bounds = vec4(258.0, 342.0, -364.0, 364.0);
// Powder surface across the authored exterior. Bounds: min/max X, min/max Z.
uniform bool entry_snow_enabled = true;
uniform vec4 entry_snow_bounds = vec4(-520.0, 1544.0, -776.0, 776.0);
uniform float entry_snow_edge : hint_range(1.0, 12.0) = 6.0;
// Keep this Snow 02 sampler identical in terrain_cliff_cutout and polar_backdrop.
// Snow006 supplied by the user. Color + AO and OpenGL Normal + Roughness packed together.
uniform sampler2D entry_snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D entry_snow_normal_rough : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float entry_snow_tile_size : hint_range(1.0,4.0) = 2.4;
uniform sampler2D entry_snow_height : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float entry_snow_relief_metres : hint_range(0.0,0.06) = 0.03;
uniform float entry_snow_normal_strength : hint_range(0.0,1.0) = 1.0;
uniform bool entry_snow_variation = true;
uniform float entry_snow_patch_density : hint_range(0.4,2.0) = 1.0;
uniform float entry_snow_dark_lift : hint_range(0.0,0.3) = 0.0;
uniform float entry_snow_groove_softening : hint_range(0.0,0.25) = 0.0;
// Continuous, non-periodic coordinate deformation: no cells and no normal cross-fades.
void snow02_coordinates(vec2 uv,out vec2 at,out mat2 jacobian) {
 vec2 p=uv*entry_snow_patch_density;
 vec2 a=vec2(0.37,0.23),b=vec2(-0.19,0.41);
 vec2 c=vec2(-0.31,0.29),d=vec2(0.43,0.17);
 float pa=dot(p,a)+0.8,pb=dot(p,b)+2.3,pc=dot(p,c)+1.7,pd=dot(p,d)+4.1;
 vec2 warp=0.65*vec2(sin(pa)+0.5*sin(pb),sin(pc)+0.5*sin(pd));
 vec2 gx=0.65*entry_snow_patch_density*(cos(pa)*a+0.5*cos(pb)*b);
 vec2 gy=0.65*entry_snow_patch_density*(cos(pc)*c+0.5*cos(pd)*d);
 jacobian=mat2(vec2(1.0+gx.x,gy.x),vec2(gx.y,1.0+gy.y));
 at=uv+warp;
}

// Bounded 24-step parallax occlusion, close-up only. Height never moves collision/vertices.
vec2 snow02_parallax(vec2 at,mat2 jacobian,vec2 dx,vec2 dy,vec3 view_world,float view_distance) {
 float relief=entry_snow_relief_metres*(1.0-smoothstep(6.0,16.0,view_distance));
 if(relief<0.00001)return at;
 vec2 ray=jacobian*(view_world.xz/max(abs(view_world.y),0.25))*(relief/entry_snow_tile_size);
 vec2 current=at+ray*0.5;
 vec2 step_uv=ray/24.0;
 float layer=0.0;
 float depth=1.0-textureGrad(entry_snow_height,current,dx,dy).r;
 vec2 previous=current;float before=depth;
 for(int step=0;step<24;step++) {
  if(layer>=depth)break;
  previous=current;before=depth-layer;
  current-=step_uv;layer+=1.0/24.0;
  depth=1.0-textureGrad(entry_snow_height,current,dx,dy).r;
 }
 float after=layer-depth;
 float fraction=clamp(before/max(before+after,0.00001),0.0,1.0);
 return mix(previous,current,fraction);
}

void sample_snow02(vec2 world_xz,vec3 view_world,float view_distance,out vec3 color,out vec3 tangent_normal,out float roughness,out float snow_ao) {
 vec2 uv=world_xz/entry_snow_tile_size;
 vec2 dx=dFdx(uv),dy=dFdy(uv);
 vec3 normal;
 if(entry_snow_variation) {
  vec2 at;mat2 jacobian;
  snow02_coordinates(uv,at,jacobian);
  at=snow02_parallax(at,jacobian,jacobian*dx,jacobian*dy,view_world,view_distance);
  vec4 surface=textureGrad(entry_snow_albedo,at,jacobian*dx,jacobian*dy);
  color=surface.rgb;snow_ao=surface.a;
  vec4 packed=textureGrad(entry_snow_normal_rough,at,jacobian*dx,jacobian*dy);
  normal=packed.rgb*2.0-1.0;
  vec2 gradient=transpose(jacobian)*vec2(normal.x,-normal.y);
  normal.xy=vec2(gradient.x,-gradient.y);
  roughness=packed.a;
 } else {
  uv=snow02_parallax(uv,mat2(1.0),dx,dy,view_world,view_distance);
  vec4 surface=textureGrad(entry_snow_albedo,uv,dx,dy);
  color=surface.rgb;snow_ao=surface.a;
  vec4 packed=textureGrad(entry_snow_normal_rough,uv,dx,dy);
  normal=packed.rgb*2.0-1.0;roughness=packed.a;
 }
 // Lift only dark pigment; keep the light snow unchanged. Soften steep groove shading slightly.
 float dark=1.0-smoothstep(0.2,0.65,dot(color,vec3(0.2126,0.7152,0.0722)));
 color=mix(color,max(color,vec3(0.65)),dark*entry_snow_dark_lift);
 normal.xy*=1.0-entry_snow_groove_softening;
 tangent_normal=normalize(mix(vec3(0,0,1),normalize(normal),entry_snow_normal_strength));
 roughness=clamp(roughness,0.04,1.0);
}


bool inside_cliff_replacement(vec2 p) {
 return p.x > cliff_replacement_bounds.x && p.x < cliff_replacement_bounds.y
     && p.y > cliff_replacement_bounds.z && p.y < cliff_replacement_bounds.w;
}
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx,skip_vertex_transform;








































uniform vec3 _camera_pos = vec3(0.f);
uniform float _mesh_size = 48.f;
uniform uint _background_mode = 1u; 
uniform uint _mouse_layer = 0x80000000u; 
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0; 
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625; 
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform vec2 _region_locations[1024];
uniform float _texture_normal_depth_array[32];
uniform float _texture_ao_strength_array[32];
uniform float _texture_roughness_mod_array[32];
uniform float _texture_uv_scale_array[32];
uniform vec2 _texture_detile_array[32];
uniform vec4 _texture_color_array[32];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;

uniform highp sampler2DArray _color_maps : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform highp sampler2DArray _texture_array_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform highp sampler2DArray _texture_array_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;




uniform float auto_slope : hint_range(0, 10) = 1.0;
uniform float auto_height_reduction : hint_range(0, 1) = 0.1;
uniform int auto_base_texture : hint_range(0, 31) = 0;
uniform int auto_overlay_texture : hint_range(0, 31) = 1;

uniform float blend_sharpness : hint_range(0, 1) = 0.5;
uniform bool flat_terrain_normals = false;
uniform bool enable_projection = true;
uniform float projection_threshold : hint_range(0.0, 0.99, 0.01) = 0.8;

uniform float mipmap_bias : hint_range(0.5, 1.5, 0.01) = 1.0;
uniform float depth_blur : hint_range(0.0, 35.0, 0.1) = 0.0;
uniform float bias_distance : hint_range(0.0, 16384.0, 0.1) = 512.0;

uniform bool enable_macro_variation = true;
uniform vec3 macro_variation1 : source_color = vec3(1.);
uniform vec3 macro_variation2 : source_color = vec3(1.);
uniform float macro_variation_slope : hint_range(0., 1.) = 0.333;


uniform highp sampler2D noise_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float noise1_scale : hint_range(0.001, 1.) = 0.04; 
uniform float noise1_angle : hint_range(0, 6.283) = 0.;
uniform vec2 noise1_offset = vec2(0.5);
uniform float noise2_scale : hint_range(0.001, 1.) = 0.076; 



struct material {
 vec4 albedo_height;
 vec4 normal_rough;
 float normal_map_depth;
 float ao_strength;
 float total_weight;
 float snow_weight;
};

varying float v_vertex_xz_dist;
varying vec3 v_vertex;









ivec3 get_index_coord(const vec2 uv, const int search) {
 vec2 r_uv = round(uv);
 vec2 o_uv = mod(r_uv,_region_size);
 ivec2 pos;
 int bounds, layer_index = -1;
 for (int i = -1; i < clamp(search,  0 ,  2 ); i++) {
 if ((layer_index == -1 && _background_mode == 0u ) || i < 0) {
 r_uv -= i == -1 ? vec2(0.0) : vec2(float(o_uv.x <= o_uv.y), float(o_uv.y <= o_uv.x));
 pos = ivec2(floor((r_uv) * _region_texel_size)) + (_region_map_size / 2);
 bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
 layer_index = (_region_map[ pos.y * _region_map_size + pos.x ] * bounds - 1);
 }
 }
 return ivec3(ivec2(mod(r_uv,_region_size)), layer_index);
}




vec3 get_index_uv(const vec2 uv2) {
 ivec2 pos = ivec2(floor(uv2)) + (_region_map_size / 2);
 int bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
 int layer_index = _region_map[ pos.y * _region_map_size + pos.x ] * bounds - 1;
 return vec3(uv2 - _region_locations[layer_index], float(layer_index));
}

void vertex() {
 
 v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

 
 v_vertex_xz_dist = length(v_vertex.xz - _camera_pos.xz);

 
 float scale = MODEL_MATRIX[0][0];
 float vertex_lerp = smoothstep(0.55, 0.95, (v_vertex_xz_dist / scale - _mesh_size - 4.0) / (_mesh_size - 2.0));
 vec2 v_fract = fract(VERTEX.xz * 0.5) * 2.0;
 
 vec2 shift = (scale < _vertex_spacing + 1e-6) ? 
 
 mix(v_fract, vec2(v_fract.x, -v_fract.y),
 round(fract(round(mod(v_vertex.z * _vertex_density, 4.0)) *
 round(mod(v_vertex.x * _vertex_density, 4.0)) * 0.25))
 ) :
 
 v_fract * round((fract(v_vertex.xz * 0.25 / scale) - 0.5) * 4.0);
 vec2 start_pos = v_vertex.xz * _vertex_density;
 vec2 end_pos = (v_vertex.xz - shift * scale) * _vertex_density;
 v_vertex.xz -= shift * scale * vertex_lerp;

 
 UV = v_vertex.xz * _vertex_density;

 
 UV2 = fma(UV, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));

 
 ivec3 v_region = get_index_coord(start_pos,  1 );
 uint control = floatBitsToUint(texelFetch(_control_maps, v_region, 0)).r;
 bool hole = bool(control >>2u & 0x1u);
 // Keep finite vertices around this cutout: NaN holes tear coarse LOD triangles.
 // Collision holes remain in the control map; the rendered edge is clipped below.
 if (inside_cliff_replacement(start_pos * _vertex_spacing)) { hole = false; }

 
 if ( !(CAMERA_VISIBLE_LAYERS == _mouse_layer) && 
 (hole || (_background_mode == 0u && v_region.z == -1))) {
 v_vertex.x = 0. / 0.;
 } else { 
 
 ivec3 coord_a = get_index_coord(start_pos,  1 );
 ivec3 coord_b = get_index_coord(end_pos,  1 );
 float h = mix(texelFetch(_height_maps, coord_a, 0).r,texelFetch(_height_maps, coord_b, 0).r,vertex_lerp);
 v_vertex.y = h;
 }

 
 VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;
 NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
 BINORMAL = normalize((MODELVIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
 TANGENT = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
}





float random(in vec2 xy) {
 return fract(sin(dot(xy, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 rotate_vec2(const vec2 v, const vec2 cs) {
 return vec2(fma(cs.x, v.x, cs.y * v.y), fma(cs.x, v.y, -cs.y * v.x));
}


void accumulate_material(const vec3 base_ddx, const vec3 base_ddy, const float weight, const ivec3 index,
 const uint control, const vec2 texture_weight, const ivec2 texture_id, const vec3 i_normal,
 const float h, inout material mat) {

 
 vec2 i_pos = fma(_region_locations[index.z], vec2(_region_size), vec2(index.xy)) * _vertex_spacing;

 
 vec2 i_uv = v_vertex.xz;
 vec4 i_dd = vec4(base_ddx.xz, base_ddy.xz);
 mat2 p_align = mat2(1.);
 if (i_normal.y <= projection_threshold && enable_projection) {
 
 p_align = mat2(vec2(i_normal.z, -i_normal.x), vec2(i_normal.x, i_normal.z));
 
 vec2 xz = round(normalize(-i_normal.xz) * 1.3065629648763765); 
 xz *= abs(xz.x) + abs(xz.y) > 1.5 ? 0.7071067811865475 : 1.0; 
 xz = vec2(-xz.y, xz.x);
 i_pos = floor(vec2(dot(i_pos, xz), -h));
 i_uv = vec2(dot(v_vertex.xz, xz), -v_vertex.y);
 i_dd.xy = vec2(dot(base_ddx.xz, xz), -base_ddx.y);
 i_dd.zw = vec2(dot(base_ddy.xz, xz), -base_ddy.y);
 }

 
 float control_scale =  (0.9 - float(((control >>7u & 0x7u) + 3u) % 8u + 1u) * 0.1) ;
 i_dd *= control_scale;
 i_uv *= control_scale;
 i_pos *= control_scale;

 
 float c_angle =  float(control >>10u & 0xFu) *  -0.392699081698724  ;
 vec2 c_cs_angle = vec2(cos(c_angle), sin(c_angle));
 i_uv = rotate_vec2(i_uv, c_cs_angle);
 i_pos = rotate_vec2(i_pos, c_cs_angle);

 
 float world_normal = 1.;
 vec3 T = normalize(base_ddx), B = -normalize(base_ddy);
 
 
 
 float blend =  float(control >> 14u & 0xFFu) *  0.003921568627450  ; 
 float sharpness = fma(56., blend_sharpness, 8.);


 
 if (blend < 1.0 
 ) {
 int id = texture_id[0];
 float id_w = texture_weight[0];
 float id_scale = _texture_uv_scale_array[id];
 vec4 id_dd = i_dd * id_scale;

 
 vec2 uv_center = floor(fma(i_pos, vec2(id_scale), vec2(0.5)));
 vec2 id_detile = fma(random(uv_center), 2.0, -1.0) * _texture_detile_array[id] * TAU;
 vec2 id_cs_angle = vec2(cos(id_detile.x), sin(id_detile.x));
 
 vec2 id_uv = rotate_vec2(fma(i_uv, vec2(id_scale), -uv_center), id_cs_angle) + uv_center + id_detile.y - 0.5;
 
 
 id_cs_angle = vec2(
 fma(id_cs_angle.x, c_cs_angle.x, -id_cs_angle.y * c_cs_angle.y),
 fma(id_cs_angle.y, c_cs_angle.x, id_cs_angle.x * c_cs_angle.y));
 
 id_dd.xy = rotate_vec2(id_dd.xy, id_cs_angle);
 id_dd.zw = rotate_vec2(id_dd.zw, id_cs_angle);

 vec4 alb = textureGrad(_texture_array_albedo, vec3(id_uv, float(id)), id_dd.xy, id_dd.zw);
 vec4 nrm = textureGrad(_texture_array_normal, vec3(id_uv, float(id)), id_dd.xy, id_dd.zw);

 alb.rgb *= _texture_color_array[id].rgb;
 nrm.a = clamp(nrm.a + _texture_roughness_mod_array[id], 0., 1.);
 
 nrm.xyz = fma(nrm.xzy, vec3(2.0), vec3(-1.0));
 nrm.xz = rotate_vec2(nrm.xz, id_cs_angle) * p_align;

 world_normal =  fma(T, vec3(nrm.x), fma(B, vec3(nrm.z), i_normal * vec3(nrm.y))) .y;

 float id_weight = exp2(sharpness * log2(weight + id_w + alb.a)) * weight;
 mat.albedo_height = fma(alb, vec4(id_weight), mat.albedo_height);
 mat.normal_rough = fma(nrm, vec4(id_weight), mat.normal_rough);
 mat.normal_map_depth = fma(_texture_normal_depth_array[id], id_weight, mat.normal_map_depth);
 mat.ao_strength = fma(_texture_ao_strength_array[id], id_weight, mat.ao_strength);
 mat.total_weight += id_weight;
 mat.snow_weight += id == 0 ? id_weight : 0.0;
 }

 
 if (blend > 0.0 && texture_id[1] != texture_id[0]
 ) {
 int id = texture_id[1];
 float id_w = texture_weight[1];
 float id_scale = _texture_uv_scale_array[id];
 vec4 id_dd = i_dd * id_scale;

 
 vec2 uv_center = floor(fma(i_pos, vec2(id_scale), vec2(0.5)));
 vec2 id_detile = _texture_detile_array[id] * fma(random(uv_center), 2.0, -1.0) * TAU;
 vec2 id_cs_angle = vec2(cos(id_detile.x), sin(id_detile.x));
 
 vec2 id_uv = rotate_vec2(fma(i_uv, vec2(id_scale), -uv_center), id_cs_angle) + uv_center + id_detile.y - 0.5;
 
 
 id_cs_angle = vec2(
 fma(id_cs_angle.x, c_cs_angle.x, -id_cs_angle.y * c_cs_angle.y),
 fma(id_cs_angle.y, c_cs_angle.x, id_cs_angle.x * c_cs_angle.y));
 
 id_dd.xy = rotate_vec2(id_dd.xy, id_cs_angle);
 id_dd.zw = rotate_vec2(id_dd.zw, id_cs_angle);

 vec4 alb = textureGrad(_texture_array_albedo, vec3(id_uv, float(id)), id_dd.xy, id_dd.zw);
 vec4 nrm = textureGrad(_texture_array_normal, vec3(id_uv, float(id)), id_dd.xy, id_dd.zw);
 alb.rgb *= _texture_color_array[id].rgb;
 nrm.a = clamp(nrm.a + _texture_roughness_mod_array[id], 0., 1.);
 
 nrm.xyz = fma(nrm.xzy, vec3(2.0), vec3(-1.0));
 nrm.xz = rotate_vec2(nrm.xz, id_cs_angle) * p_align;

 float id_weight = exp2(sharpness * log2(weight + id_w + alb.a * clamp(world_normal, 0., 1.))) * weight;
 mat.albedo_height = fma(alb, vec4(id_weight), mat.albedo_height);
 mat.normal_rough = fma(nrm, vec4(id_weight), mat.normal_rough);
 mat.normal_map_depth = fma(_texture_normal_depth_array[id], id_weight, mat.normal_map_depth);
 mat.ao_strength = fma(_texture_ao_strength_array[id], id_weight, mat.ao_strength);
 mat.total_weight += id_weight;
 mat.snow_weight += id == 0 ? id_weight : 0.0;
 }
}

void fragment() {
 // Exact edge at every LOD, slightly inside the authored mesh for seam overlap.
 if (CAMERA_VISIBLE_LAYERS != _mouse_layer && inside_cliff_replacement(v_vertex.xz)) { discard; }
 
 vec2 uv = UV;
 vec2 uv2 = UV2;
 
 
 vec3 region_uv = get_index_uv(uv2);
 const vec3 offsets = vec3(0, 1, 2);
 vec2 index_id = floor(uv);
 vec2 weight = fract(uv);
 vec2 invert = 1.0 - weight;
 vec4 weights = vec4(
 invert.x * weight.y, 
 weight.x * weight.y, 
 weight.x * invert.y, 
 invert.x * invert.y 
 );

 ivec3 index[4];
 
 index[0] = get_index_coord(index_id + offsets.xy,  2 );
 index[1] = get_index_coord(index_id + offsets.yy,  2 );
 index[2] = get_index_coord(index_id + offsets.yx,  2 );
 index[3] = get_index_coord(index_id + offsets.xx,  2 );
 
 vec3 base_ddx = dFdxCoarse(v_vertex);
 vec3 base_ddy = dFdyCoarse(v_vertex);
 
 
 float region_mip = log2(max(length(base_ddx.xz), length(base_ddy.xz)) * _vertex_density);
 bool bilerp = region_mip < 0.0 && region_uv.z > -1.;

 
 vec3 index_normal[4];
 float h[4];
 
 float u = 0.0;
 float v = 0.0;
 
 
 h[3] = texelFetch(_height_maps, index[3], 0).r; 
 h[2] = texelFetch(_height_maps, index[2], 0).r; 
 h[0] = texelFetch(_height_maps, index[0], 0).r; 
 index_normal[3] = normalize(vec3(h[3] - h[2] + u, _vertex_spacing, h[3] - h[0] + v));

 
 vec3 w_normal = index_normal[3];

 
 float bias = mix(mipmap_bias,
 depth_blur + 1.,
 smoothstep(0.0, 1.0, (v_vertex_xz_dist - bias_distance) *  0.0009765625 ));
 base_ddx *= bias;
 base_ddy *= bias;

 
 vec4 color_map = region_uv.z > -1.0 ? textureLod(_color_maps, region_uv, region_mip) :  vec4(1.0, 1.0, 1.0, 0.5) ;

 
 if (bilerp) {
 
 vec4 col_map[4];
 col_map[3] = index[3].z > -1 ? texelFetch(_color_maps, index[3], 0) :  vec4(1.0, 1.0, 1.0, 0.5) ;
 
 col_map[0] = index[0].z > -1 ? texelFetch(_color_maps, index[0], 0) :  vec4(1.0, 1.0, 1.0, 0.5) ;
 col_map[1] = index[1].z > -1 ? texelFetch(_color_maps, index[1], 0) :  vec4(1.0, 1.0, 1.0, 0.5) ;
 col_map[2] = index[2].z > -1 ? texelFetch(_color_maps, index[2], 0) :  vec4(1.0, 1.0, 1.0, 0.5) ;

 color_map =
 col_map[0] * weights[0] +
 col_map[1] * weights[1] +
 col_map[2] * weights[2] +
 col_map[3] * weights[3] ;
 



 
 
 h[1] = texelFetch(_height_maps, index[1], 0).r; 
 float h_4 = texelFetch(_height_maps, get_index_coord(index_id + offsets.yz,  2 ), 0).r; 
 float h_5 = texelFetch(_height_maps, get_index_coord(index_id + offsets.zy,  2 ), 0).r; 
 float h_6 = texelFetch(_height_maps, get_index_coord(index_id + offsets.zx,  2 ), 0).r; 
 float h_7 = texelFetch(_height_maps, get_index_coord(index_id + offsets.xz,  2 ), 0).r; 

 
 index_normal[0] = normalize(vec3(h[0] - h[1] + u, _vertex_spacing, h[0] - h_7 + v));
 index_normal[1] = normalize(vec3(h[1] - h_5 + u, _vertex_spacing, h[1] - h_4 + v));
 index_normal[2] = normalize(vec3(h[2] - h_6 + u, _vertex_spacing, h[2] - h[1] + v));

 
 w_normal =
 index_normal[0] * weights[0] +
 index_normal[1] * weights[1] +
 index_normal[2] * weights[2] +
 index_normal[3] * weights[3] ;
 }

 
 if (flat_terrain_normals) {
 NORMAL = normalize(cross(dFdyCoarse(VERTEX),dFdxCoarse(VERTEX)));
 TANGENT = normalize(cross(NORMAL, VIEW_MATRIX[2].xyz));
 BINORMAL = normalize(cross(NORMAL, TANGENT));
 } else {
 vec3 w_tangent = normalize(cross(w_normal, vec3(0.0, 0.0, 1.0)));
 vec3 w_binormal = normalize(cross(w_normal, w_tangent));
 NORMAL = mat3(VIEW_MATRIX) * w_normal;
 TANGENT = mat3(VIEW_MATRIX) * w_tangent;
 BINORMAL = mat3(VIEW_MATRIX) * w_binormal;
 }

 
 
 uvec4 control = uvec4(floatBitsToUint(texelFetch(_control_maps, index[3], 0).r));
 if (bilerp) {
 control = uvec4(
 floatBitsToUint(texelFetch(_control_maps, index[0], 0).r),
 floatBitsToUint(texelFetch(_control_maps, index[1], 0).r),
 floatBitsToUint(texelFetch(_control_maps, index[2], 0).r),
 control[3]);
 }

 {
 
 float auto_blend = clamp(fma(auto_slope * 2.0, (w_normal.y - 1.0), 1.0)
 - auto_height_reduction * 0.01 * v_vertex.y, 0.0, 1.0);
 
 uvec4 is_auto = (control & uvec4(0x1u)) | uvec4(uint(region_uv.z < 0.0));
 uint u_auto = 
 ((uint(auto_base_texture) & 0x1Fu) << 27u) |
 ((uint(auto_overlay_texture) & 0x1Fu) << 22u) |
 ((uint(fma(auto_blend, 255.0 , 0.5)) & 0xFFu) << 14u);
 control = control * (1u - is_auto) + u_auto * is_auto;
 }


 
 
 
 ivec4 t_id[2] = {ivec4(control >> uvec4(27u) & uvec4(0x1Fu)),
 ivec4(control >> uvec4(22u) & uvec4(0x1Fu))};
 ivec2 texture_ids[4] = ivec2[4](
 ivec2(t_id[0].x, t_id[1].x),
 ivec2(t_id[0].y, t_id[1].y),
 ivec2(t_id[0].z, t_id[1].z),
 ivec2(t_id[0].w, t_id[1].w));

 
 vec4 weights_id_1 = vec4(control >> uvec4(14u) & uvec4(0xFFu)) *  0.003921568627450 ;
 vec4 weights_id_0 = 1.0 - weights_id_1;
 vec2 t_weights[4] = vec2[4](
 vec2(weights_id_0[0], weights_id_1[0]),
 vec2(weights_id_0[1], weights_id_1[1]),
 vec2(weights_id_0[2], weights_id_1[2]),
 vec2(weights_id_0[3], weights_id_1[3]));
 
 
 if (bilerp) {
 t_weights = {vec2(0), vec2(0), vec2(0), vec2(0)};
 weights_id_0 *= weights;
 weights_id_1 *= weights;
 for (int i = 0; i < 4; i++) {
 vec2 w_0 = vec2(weights_id_0[i]);
 vec2 w_1 = vec2(weights_id_1[i]);
 ivec2 id_0 = texture_ids[i].xx;
 ivec2 id_1 = texture_ids[i].yy;
 t_weights[0] += fma(w_0, vec2(equal(texture_ids[0], id_0)), w_1 * vec2(equal(texture_ids[0], id_1)));
 t_weights[1] += fma(w_0, vec2(equal(texture_ids[1], id_0)), w_1 * vec2(equal(texture_ids[1], id_1)));
 t_weights[2] += fma(w_0, vec2(equal(texture_ids[2], id_0)), w_1 * vec2(equal(texture_ids[2], id_1)));
 t_weights[3] += fma(w_0, vec2(equal(texture_ids[3], id_0)), w_1 * vec2(equal(texture_ids[3], id_1)));
 }
 }
 

 
 material mat = material(vec4(0.0), vec4(0.0), 0., 0., 0., 0.);

 
 accumulate_material(base_ddx, base_ddy, weights[3], index[3], control[3], t_weights[3],
 texture_ids[3], index_normal[3], h[3], mat);

 
 if (bilerp) {
 accumulate_material(base_ddx, base_ddy, weights[2], index[2], control[2], t_weights[2],
 texture_ids[2], index_normal[2], h[2], mat);
 accumulate_material(base_ddx, base_ddy, weights[1], index[1], control[1], t_weights[1],
 texture_ids[1], index_normal[1], h[1], mat);
 accumulate_material(base_ddx, base_ddy, weights[0], index[0], control[0], t_weights[0],
 texture_ids[0], index_normal[0], h[0], mat);
 }

 
 float weight_inv = 1.0 / mat.total_weight;
 mat.albedo_height *= weight_inv;
 mat.normal_rough *= weight_inv;
 mat.normal_map_depth *= weight_inv;
 mat.ao_strength *= weight_inv;

 
 vec3 macrov = vec3(1.);
 if (enable_macro_variation) {
 float noise1 = texture(noise_texture, rotate_vec2(fma(uv, vec2(noise1_scale * .1), noise1_offset) , vec2(cos(noise1_angle), sin(noise1_angle)))).r;
 float noise2 = texture(noise_texture, uv * noise2_scale * .1).r;
 macrov = mix(macro_variation1, vec3(1.), noise1);
 macrov *= mix(macro_variation2, vec3(1.), noise2);
 macrov = mix(vec3(1.0), macrov, clamp(w_normal.y + macro_variation_slope, 0., 1.));
 }
 
 
 float roughness = clamp(fma(color_map.a - 0.5, 2.0, mat.normal_rough.a), 0., 1.);
 
 
 ALBEDO = mat.albedo_height.rgb * color_map.rgb * macrov;
 // Local snow dusting on the uphill join; editable bounds, no terrain displacement.
 float ridge_mask = smoothstep(ridge_snow_bounds.x, ridge_snow_bounds.x + 18.0, v_vertex.x)
  * (1.0-smoothstep(ridge_snow_bounds.y-12.0,ridge_snow_bounds.y,v_vertex.x))
  * smoothstep(ridge_snow_bounds.z,ridge_snow_bounds.z+40.0,v_vertex.z)
  * (1.0-smoothstep(ridge_snow_bounds.w-40.0,ridge_snow_bounds.w,v_vertex.z));
 float ridge_patch = texture(noise_texture,v_vertex.xz*0.037).r;
 float ridge_cover = ridge_mask * ridge_snow_amount
  * (0.2+0.8*smoothstep(0.08,0.62,w_normal.y+(ridge_patch-0.5)*0.28));
 ALBEDO = mix(ALBEDO,ridge_snow_color.rgb*(0.94+ridge_patch*0.06),ridge_cover);
 ROUGHNESS = roughness;
 SPECULAR = 1. - mat.normal_rough.a;
 
 NORMAL_MAP = fma(normalize(mat.normal_rough.xzy), vec3(0.5), vec3(0.5));
 NORMAL_MAP_DEPTH = mat.normal_map_depth * (1.0-ridge_cover*0.45);

 // Replace only snow inside the sample area. The height/control maps, rock
 // layers, terrain holes, collision and material outside these bounds are intact.
 float powder_coverage = 0.0;
 float powder_ao = 1.0;
 if (entry_snow_enabled) {
  vec2 p = v_vertex.xz;
  vec2 edge_in = smoothstep(entry_snow_bounds.xz, entry_snow_bounds.xz + vec2(entry_snow_edge), p);
  vec2 edge_out = vec2(1.0) - smoothstep(entry_snow_bounds.yw - vec2(entry_snow_edge), entry_snow_bounds.yw, p);
  // Legacy painted rock IDs belong to the old mountainous terrain. On the new
  // plain use the actual slope, avoiding texel-shaped rock patches on flat snow.
  float coverage = edge_in.x * edge_in.y * edge_out.x * edge_out.y
   * smoothstep(0.65, 0.9, w_normal.y);
  powder_coverage = coverage;
  if (coverage > 0.001) {
   vec3 snow_color;
   vec3 detail_normal;
   float snow_roughness;
   sample_snow02(p,(INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz,length(VERTEX),snow_color,detail_normal,snow_roughness,powder_ao);
   ALBEDO = mix(ALBEDO, snow_color, coverage);
   ROUGHNESS = mix(ROUGHNESS, snow_roughness, coverage);
   SPECULAR = mix(SPECULAR, 0.22, coverage);
   NORMAL_MAP = normalize(mix(NORMAL_MAP * 2.0 - 1.0, detail_normal, coverage)) * 0.5 + 0.5;
   NORMAL_MAP_DEPTH = mix(NORMAL_MAP_DEPTH, 1.0, coverage);
  }
 }

 
 float ao = (1. - (mat.albedo_height.a * log(2.1 - mat.ao_strength))) * (1. - mat.normal_rough.y);
 AO = clamp(1. - ao * mat.ao_strength, mat.albedo_height.a, 1.0);
 AO_LIGHT_AFFECT = (1.0 - mat.albedo_height.a) * clamp(mat.normal_rough.y, 0., 1.);
 // Painted rock AO is not part of the new powder surface either.
 AO = mix(AO, powder_ao, powder_coverage);
 AO_LIGHT_AFFECT *= 1.0 - powder_coverage;

}

