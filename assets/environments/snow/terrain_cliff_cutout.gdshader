// Terrain3D generated autoshader, retained with a local replacement-surface cutout.
// Regenerate from Terrain3D when upgrading the addon; preserve the three cutout additions.
shader_type spatial;
uniform sampler2D snow_deformation : filter_linear, repeat_disable;
uniform sampler2D interactive_snow_depth : filter_linear, repeat_disable;
const float INTERACTIVE_SNOW_DEPTH_RANGE = 1.0;
uniform vec2 snow_tile_origins[12];
uniform int snow_tile_count = 0;
uniform float snow_clock = 0.0;
instance uniform bool fine_snow_mesh = false;
instance uniform vec4 snow_coarse_edges = vec4(1.0);
uniform vec2 fine_snow_origins[4];
uniform int fine_snow_tile_count = 0;

vec3 rounded_snow_profile(vec2 uv) {
 const vec2 TAP = vec2(0.84 / 2048.0, 0.84 / 1536.0);
 float southeast = textureLod(interactive_snow_depth, uv + TAP, 0.0).r;
 float southwest = textureLod(interactive_snow_depth, uv + vec2(-TAP.x, TAP.y), 0.0).r;
 float northeast = textureLod(interactive_snow_depth, uv + vec2(TAP.x, -TAP.y), 0.0).r;
 float northwest = textureLod(interactive_snow_depth, uv - TAP, 0.0).r;
 return vec3((southeast + southwest + northeast + northwest) * 0.25,
  (southwest + northwest - southeast - northeast) / 3.36,
  (northwest + northeast - southwest - southeast) / 3.36) * INTERACTIVE_SNOW_DEPTH_RANGE;
}

vec2 snow_contact_uv(vec2 point) {
 for (int slot = 0; slot < snow_tile_count; slot++) {
  vec2 local = (point - snow_tile_origins[slot]) / 16.0;
  if (all(greaterThanEqual(local, vec2(0.0))) && all(lessThan(local, vec2(1.0)))) {
   vec2 tile = vec2(float(slot % 4), float(slot / 4));
   return (tile + clamp(local, vec2(0.5 / 192.0), vec2(1.0 - 0.5 / 192.0))) / vec2(4.0, 3.0);
  }
 }
 return vec2(-1.0);
}

float snow_contact_height(vec2 contact) {
 return contact.g * (1.0 - contact.r) * 0.19 - contact.r * 0.27;
}

vec2 aged_snow_texel(ivec2 pixel) {
 vec4 value = texelFetch(snow_deformation, pixel, 0);
 if (value.r + value.g < 0.001) { return vec2(0.0); }
 vec2 time_bytes = round(value.ba * 255.0);
 float age = mod(snow_clock - dot(time_bytes, vec2(1.0, 256.0)) + 65536.0, 65536.0);
 return value.rg * (1.0 - smoothstep(26.0, 42.0, age));
}

vec2 read_snow_contact(vec2 atlas_uv) {
 vec2 texel = atlas_uv * vec2(textureSize(snow_deformation, 0)) - 0.5;
 ivec2 tile_start = ivec2(floor((texel + 0.5) / 192.0)) * 192;
 ivec2 tile_end = tile_start + 191;
 ivec2 lower = clamp(ivec2(floor(texel)), tile_start, tile_end);
 ivec2 upper = clamp(ivec2(floor(texel)) + 1, tile_start, tile_end);
 vec2 ratio = fract(texel);
 vec2 north = mix(aged_snow_texel(lower), aged_snow_texel(ivec2(upper.x, lower.y)), ratio.x);
 vec2 south = mix(aged_snow_texel(ivec2(lower.x, upper.y)), aged_snow_texel(upper), ratio.x);
 return mix(north, south, ratio.y);
}

vec2 snow_contact_at(vec2 point) {
 vec2 uv = snow_contact_uv(point);
 return uv.x >= 0.0 ? read_snow_contact(uv) : vec2(0.0);
}

// The terrain grid resolves broad settling. Fine walls and banks are shaded per pixel.
vec2 settled_snow_at(vec2 point, float spacing) {
 float reach = spacing * 0.55;
 bool overlaps_trace = false;
 for (int slot = 0; slot < snow_tile_count; slot++) {
  vec2 local = point - snow_tile_origins[slot];
  if (all(greaterThanEqual(local, vec2(-reach))) && all(lessThan(local, vec2(16.0 + reach)))) {
   overlaps_trace = true;
   break;
  }
 }
 if (!overlaps_trace) { return vec2(0.0); }
 vec2 contact = snow_contact_at(point) * 0.20;
 for (int i = 0; i < 8; i++) {
  float angle = (float(i) + 0.5) * 0.78539816;
  vec2 direction = vec2(cos(angle), sin(angle));
  contact += snow_contact_at(point + direction * reach) * 0.10;
 }
 return contact;
}
uniform sampler2D snow_exposed_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D polar_ice_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D polar_ice_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D polar_ice_rough : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 ridge_snow_bounds = vec4(210.0, 280.0, -366.0, 366.0);
uniform float ridge_snow_amount : hint_range(0.0, 1.0) = 0.65;
uniform vec4 ridge_snow_color : source_color = vec4(0.82, 0.88, 0.92, 1.0);
uniform vec4 cliff_replacement_bounds = vec4(258.0, 342.0, -364.0, 364.0);
// Powder surface across the authored exterior. Bounds: min/max X, min/max Z.
uniform bool entry_snow_enabled = true;
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
varying float v_ground_height;









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

float snow_surface_depth(vec2 point, float filter_spacing) {
 vec2 uv = (point + vec2(512.5, 768.5)) / vec2(2048.0, 1536.0);
 if (any(lessThanEqual(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) { return 0.0; }
 float depth = rounded_snow_profile(uv).x;
 float view_distance = distance(point, _camera_pos.xz);
 if (depth > 0.01 && view_distance < 34.0 && snow_tile_count > 0) {
  vec2 contact = filter_spacing < 0.5 ? snow_contact_at(point) : settled_snow_at(point, filter_spacing);
  float near_weight = 1.0 - smoothstep(21.0, 34.0, view_distance);
  float compression = contact.r * near_weight;
  float bank = contact.g * (1.0 - compression) * 0.10 * near_weight;
  depth = mix(depth, min(depth, 0.025), compression) + depth * bank;
 }
 return min(depth, INTERACTIVE_SNOW_DEPTH_RANGE);
}

float terrain_height_at_grid(vec2 grid) {
 ivec3 index = get_index_coord(grid, 1);
 return texelFetch(_height_maps, index, 0).r;
}

vec2 snow_surface_at_grid(vec2 grid, float filter_spacing) {
 float ground = terrain_height_at_grid(grid);
 return vec2(ground, ground + snow_surface_depth(grid * _vertex_spacing, filter_spacing));
}

void vertex() {
 vec3 fine_normal = vec3(0.0, 1.0, 0.0);
 
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
 if (!fine_snow_mesh) { v_vertex.xz -= shift * scale * vertex_lerp; }

 
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
 float coarse_filter = max(_vertex_spacing, 0.9);
 if (fine_snow_mesh && v_region.z >= 0 && !hole) {
  vec2 cell = floor(start_pos);
  vec2 ratio = fract(start_pos);
  float northwest = terrain_height_at_grid(cell);
  float northeast = terrain_height_at_grid(cell + vec2(1.0, 0.0));
  float southwest = terrain_height_at_grid(cell + vec2(0.0, 1.0));
  float southeast = terrain_height_at_grid(cell + vec2(1.0));
  float ground = mix(mix(northwest, northeast, ratio.x), mix(southwest, southeast, ratio.x), ratio.y);
  v_ground_height = ground;
  vec2 grade = vec2(mix(northeast - northwest, southeast - southwest, ratio.y),
   mix(southwest - northwest, southeast - northeast, ratio.x)) / _vertex_spacing;
  const float NORMAL_STEP = 0.17;
  vec2 point = v_vertex.xz;
  float depth = snow_surface_depth(point, 0.31);
  vec2 surface_grade = grade + vec2(
   snow_surface_depth(point + vec2(NORMAL_STEP, 0.0), 0.31) - depth,
   snow_surface_depth(point + vec2(0.0, NORMAL_STEP), 0.31) - depth
  ) / NORMAL_STEP;
  fine_normal = normalize(vec3(-surface_grade.x, 1.0, -surface_grade.y));
  v_vertex.y = ground + depth;
  // Match the coarse edge to keep the transition watertight at integer tile boundaries.
  vec4 faces = vec4(8.0) + vec4(VERTEX.x, -VERTEX.x, VERTEX.z, -VERTEX.z);
  faces += (vec4(1.0) - snow_coarse_edges) * 16.0;
  float edge = min(min(faces.x, faces.y), min(faces.z, faces.w));
  if (edge < 1.25) {
   vec2 a = snow_surface_at_grid(cell, coarse_filter);
   vec2 b = snow_surface_at_grid(cell + vec2(1.0, 0.0), coarse_filter);
   vec2 c = snow_surface_at_grid(cell + vec2(0.0, 1.0), coarse_filter);
   vec2 d = snow_surface_at_grid(cell + vec2(1.0), coarse_filter);
   vec2 coarse = mix(mix(a, b, ratio.x), mix(c, d, ratio.x), ratio.y);
   float join = 1.0 - smoothstep(0.0, 1.25, edge);
   // The blend uses coarse samples at the seam and dies off quickly inside the tile.
   v_vertex.y = mix(v_vertex.y, coarse.y, join);
   v_ground_height = mix(v_ground_height, coarse.x, join);
  }
 } else {
  float ground = mix(texelFetch(_height_maps, coord_a, 0).r, texelFetch(_height_maps, coord_b, 0).r, vertex_lerp);
  v_ground_height = ground;
  v_vertex.y = ground;
  if (v_region.z >= 0 && !hole) {
   v_vertex.y += snow_surface_depth(v_vertex.xz, coarse_filter);
  }
 }
 }

 
 VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;
 NORMAL = fine_snow_mesh ? normalize(mat3(VIEW_MATRIX) * fine_normal) : normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
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

// Generated by tools/authoring/smooth_polar_stream.py. xy=center, z=water height, w=half width.
vec3 polar_stream_sample(vec2 p) {
 vec4 points[17]=vec4[](vec4(-215.0000000,-170.0000000,5.8800495,3.7595692),vec4(-211.7817663,-161.8750000,4.4572429,4.2750902),vec4(-208.7965729,-153.7500000,3.0344362,4.4430201),vec4(-206.2419819,-145.6250000,1.6116296,4.2139682),vec4(-204.2500000,-137.5000000,1.1334667,3.8106995),vec4(-202.8669819,-129.3750000,0.7340242,3.5272094),vec4(-202.0465729,-121.2500000,0.3345816,3.4772154),vec4(-201.6567663,-113.1250000,-0.6596080,3.5141282),vec4(-201.5000000,-105.0000000,-1.7619335,3.3904308),vec4(-201.3432337,-96.8750000,-2.8642589,3.0103738),vec4(-200.9534271,-88.7500000,-3.8033816,2.5463986),vec4(-200.1330181,-80.6250000,-3.8448890,2.3110386),vec4(-198.7500000,-72.5000000,-3.8863964,2.4943257),vec4(-196.7580181,-64.3750000,-3.9371246,2.9977973),vec4(-194.2034271,-56.2500000,-4.0985024,3.5122032),vec4(-191.2182337,-48.1250000,-4.2598802,3.7713357),vec4(-188.0000000,-40.0000000,-4.4212579,3.7595692));
 vec3 result=vec3(10000.0,0.0,0.0);
 for(int i=0;i<16;i++) {
  vec4 a=points[i];vec4 b=points[i+1];
  float t=clamp(dot(p-a.xy,b.xy-a.xy)/dot(b.xy-a.xy,b.xy-a.xy),0.0,1.0);
  float d=length(p-mix(a.xy,b.xy,t));
  if(d<result.x)result=vec3(d,mix(a.z,b.z,t),mix(a.w,b.w,t));
 }
 return result;
}

void extra_polar_surfaces(vec3 p, out float bed, out float coast) {
 bed=0.0;coast=0.0;
 { vec2 q=(p.xz-vec2(105.0,95.0))/vec2(32.0,12.0);float a=atan(q.y,q.x);float r=length(q)*(1.0+.12*sin(a*3.0+0.0)+.07*sin(a*5.0));float area=1.0-smoothstep(1.1,1.5,r);bed=max(bed,area*(1.0-smoothstep(-2.81406993865967,-2.58406993865967,p.y)));coast=max(coast,area*smoothstep(-2.78406993865967,-2.60406993865967,p.y)*(1.0-smoothstep(-2.36406993865967,-1.66406993865967,p.y))); }
 { vec2 q=(p.xz-vec2(-215.0,90.0))/vec2(17.0,31.0);float a=atan(q.y,q.x);float r=length(q)*(1.0+.12*sin(a*3.0+1.0)+.07*sin(a*5.0));float area=1.0-smoothstep(1.1,1.5,r);bed=max(bed,area*(1.0-smoothstep(-2.1864174127578697,-1.95641741275787,p.y)));coast=max(coast,area*smoothstep(-2.15641741275787,-1.97641741275787,p.y)*(1.0-smoothstep(-1.73641741275787,-1.0364174127578698,p.y))); }
 vec3 stream=polar_stream_sample(p.xz);float nearest=stream.x;float level=stream.y;
 float area=1.0-smoothstep(6.0,12.0,nearest);
 bed=max(bed,area*(1.0-smoothstep(level-.05,level+.18,p.y)));
 // Broad feathered frost shoulder follows the stream, independently of its bed.
 float bank_variation=.45*sin(p.x*.17+p.z*.11)+.25*sin(p.z*.29-p.x*.09);
 float frost_area=1.0-smoothstep(stream.z+2.6,stream.z+12.6,nearest+bank_variation);
 float frost_height=1.0-smoothstep(level+.22,level+1.55+bank_variation*.18,p.y);
 coast=max(coast,frost_area*smoothstep(level-.08,level+.20,p.y)*frost_height);
}

void fragment() {
 if (!fine_snow_mesh && fine_snow_tile_count > 0) {
  for (int slot = 0; slot < fine_snow_tile_count; slot++) {
   vec2 local_snow = v_vertex.xz - fine_snow_origins[slot];
   if (all(greaterThanEqual(local_snow, vec2(0.0))) && all(lessThan(local_snow, vec2(16.0)))) { discard; }
  }
 }
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
 vec3 surface_normal = fine_snow_mesh ? normalize(mat3(INV_VIEW_MATRIX) * NORMAL) : w_normal;
 vec3 w_tangent = normalize(cross(surface_normal, vec3(0.0, 0.0, 1.0)));
 vec3 w_binormal = normalize(cross(surface_normal, w_tangent));
 NORMAL = mat3(VIEW_MATRIX) * surface_normal;
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

 // Apply Snow006 only along the compacted route; the surrounding ground uses Terrain3D's material.
 float packed_coverage = 0.0;
 float packed_ao = 1.0;
 if (entry_snow_enabled && v_vertex.z > 1.0 && v_vertex.z < 98.0 && v_vertex.x > -106.0 && v_vertex.x < -35.0) {
  vec2 p = v_vertex.xz;
  float route_t = clamp((p.y - 3.0) / 92.0, 0.0, 1.0);
  float route_x = mix(-38.8, -94.0, route_t) - sin(route_t * 6.2831853) * 7.5
   + sin(route_t * 12.566371) * 2.1;
  float edge = (texture(noise_texture, p * 0.42).r - 0.5) * 0.90;
  float route_distance = abs(p.x - route_x) * 0.72 + edge;
  float ends = smoothstep(1.0, 3.0, p.y) * (1.0 - smoothstep(94.0, 98.0, p.y));
  packed_coverage = (1.0 - smoothstep(0.66, 1.85, route_distance)) * ends * smoothstep(0.65, 0.9, w_normal.y);
  if (packed_coverage > 0.001) {
   vec3 path_color;
   vec3 path_normal;
   float path_roughness;
   sample_snow02(p, (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz, length(VERTEX), path_color, path_normal, path_roughness, packed_ao);
   ALBEDO = mix(ALBEDO, mix(path_color * 0.96, vec3(0.83, 0.86, 0.89), 0.12), packed_coverage);
   ROUGHNESS = mix(ROUGHNESS, clamp(path_roughness, 0.60, 0.83), packed_coverage);
   SPECULAR = mix(SPECULAR, 0.25, packed_coverage);
   NORMAL_MAP = normalize(mix(NORMAL_MAP * 2.0 - 1.0, path_normal, packed_coverage * 0.75)) * 0.5 + 0.5;
   NORMAL_MAP_DEPTH = mix(NORMAL_MAP_DEPTH, 1.0, packed_coverage);
  }
 }

 vec3 ground_position = vec3(v_vertex.x, v_ground_height, v_vertex.z);
 float extra_bed;float extra_coast;extra_polar_surfaces(ground_position,extra_bed,extra_coast);
 vec2 ice_p = (v_vertex.xz-vec2(-110.0,-105.0))/vec2(40.0,29.0);
 float ice_angle=atan(ice_p.y,ice_p.x);
 float ice_edge = length(ice_p)*(1.0+.13*sin(ice_angle*3.0+.7)+.10*sin(ice_angle*5.0-1.0)) + sin(v_vertex.x*0.19+sin(v_vertex.z*0.13))*0.045 + sin(v_vertex.z*0.31)*0.025;
 float ice_cover = (1.0-smoothstep(0.65,1.08,ice_edge))*smoothstep(0.7,0.96,w_normal.y)*smoothstep(-6.02,-5.70,v_ground_height);
 ice_cover=max(ice_cover,extra_coast);
 float frost_patch=.5+.5*sin(v_vertex.x*.19+sin(v_vertex.z*.13)*1.8)*sin(v_vertex.z*.23-v_vertex.x*.07);
 ice_cover*=.55+.45*smoothstep(.15,.8,frost_patch);
 vec2 ice_uv=v_vertex.xz/6.5 + vec2(sin(v_vertex.z*0.08),sin(v_vertex.x*0.07))*.22;
 vec3 frosted_ice=mix(vec3(.62,.73,.76),texture(polar_ice_color,ice_uv).rgb*vec3(.78,.88,.92),.45);
 ALBEDO=mix(ALBEDO,frosted_ice,ice_cover);
 ROUGHNESS=mix(ROUGHNESS,texture(polar_ice_rough,ice_uv).r*.45+.35,ice_cover);
 vec2 ice_xy=(texture(polar_ice_normal,ice_uv).rg*2.0-1.0)*.38;
 NORMAL_MAP=normalize(mix(NORMAL_MAP*2.0-1.0,vec3(ice_xy,sqrt(max(1.0-dot(ice_xy,ice_xy),0.001))),ice_cover))*0.5+0.5;
 float basin_bed=(1.0-smoothstep(.95,1.15,ice_edge))*(1.0-smoothstep(-6.1,-5.85,v_ground_height));
 basin_bed=max(basin_bed,extra_bed);
 ALBEDO=mix(ALBEDO,vec3(.30,.38,.40),basin_bed);
 ROUGHNESS=mix(ROUGHNESS,.95,basin_bed);
 NORMAL_MAP_DEPTH*=1.0-basin_bed;
 vec2 layer_uv = (v_vertex.xz + vec2(512.5, 768.5)) / vec2(2048.0, 1536.0);
 vec3 snow_profile = vec3(0.0);
 if (all(greaterThan(layer_uv, vec2(0.0))) && all(lessThan(layer_uv, vec2(1.0)))) {
  snow_profile = rounded_snow_profile(layer_uv);
 }
 float snow_depth = snow_profile.x;
 // World-space rock exposure keeps long dark patches without revealing Terrain3D control texels.
 vec2 snow_position = v_vertex.xz;
 float large_breakup = texture(noise_texture, snow_position * 0.065).r;
 float fine_breakup = texture(noise_texture, snow_position * 0.28 + large_breakup * 0.31).r;
 float exposure = (1.0 - w_normal.y) * 1.65 + large_breakup * 0.42 + fine_breakup * 0.13;
 float rock = smoothstep(0.39, 0.74, exposure) * (1.0 - smoothstep(0.04, 0.37, snow_depth));
 float surface_cover = float(entry_snow_enabled) * (1.0 - max(packed_coverage, max(ice_cover, basin_bed)));
 float winter_cover = smoothstep(0.025, 0.25, snow_depth) * surface_cover;
 if (winter_cover > 0.01 && !fine_snow_mesh) {
  vec3 rounded_normal = normalize(normalize(w_normal) + vec3(snow_profile.y, 0.0, snow_profile.z));
  NORMAL = normalize(mix(NORMAL, mat3(VIEW_MATRIX) * rounded_normal, winter_cover));
  TANGENT = normalize(cross(BINORMAL, NORMAL));
  BINORMAL = normalize(cross(NORMAL, TANGENT));
 }
 if (surface_cover > 0.01) {
  vec2 snow_uv = snow_position / entry_snow_tile_size;
  vec2 snow_at;
  mat2 snow_warp;
  snow02_coordinates(snow_uv, snow_at, snow_warp);
  vec2 snow_dx = snow_warp * dFdx(snow_uv);
  vec2 snow_dy = snow_warp * dFdy(snow_uv);
  vec4 scan = textureGrad(entry_snow_albedo, snow_at, snow_dx, snow_dy);
  vec4 detail = textureGrad(entry_snow_normal_rough, snow_at, snow_dx, snow_dy);
  vec3 snow_col = mix(scan.rgb * 1.07, vec3(0.83, 0.86, 0.89), 0.12 + winter_cover * 0.14);
  vec3 rock_col = texture(snow_exposed_rock, snow_position / 5.8).rgb;
  rock_col = mix(vec3(0.27, 0.31, 0.34), rock_col, 0.53);
  ALBEDO = mix(ALBEDO, mix(snow_col, rock_col, rock), surface_cover);
  ROUGHNESS = mix(ROUGHNESS, mix(clamp(detail.a, 0.68, 0.91), 0.86, rock), surface_cover);
  vec2 relief_xy = (detail.xy * 2.0 - 1.0) * mix(0.64, 0.37, winter_cover) * (1.0 - rock * 0.65);
  vec3 grain_normal = normalize(vec3(relief_xy, 1.0));
  NORMAL_MAP = normalize(mix(NORMAL_MAP * 2.0 - 1.0, grain_normal, surface_cover)) * 0.5 + 0.5;
  NORMAL_MAP_DEPTH = mix(NORMAL_MAP_DEPTH, 1.0, surface_cover);
  packed_ao = mix(packed_ao, mix(1.0, scan.a, 0.37), surface_cover);
 }
 if (length(VERTEX) < 34.0 && max(ice_cover, basin_bed) < 0.45 && packed_coverage < 0.85) {
  vec2 contact_uv = snow_contact_uv(v_vertex.xz);
  if (contact_uv.x >= 0.0) {
   vec2 contact = read_snow_contact(contact_uv);
   if (contact.r + contact.g > 0.001) {
    float amount = mix(0.42, 1.0, winter_cover) * (1.0 - packed_coverage) * (1.0 - smoothstep(24.0, 34.0, length(VERTEX)));
    ALBEDO *= 1.0 + amount * (contact.g * (1.0 - contact.r) * 0.13 - contact.r * 0.12);
    ROUGHNESS = mix(ROUGHNESS, 0.82, contact.r * amount);
    if (!fine_snow_mesh) {
     vec2 p = v_vertex.xz;
     const float SAMPLE_RADIUS = 0.15;
     float west = snow_contact_height(snow_contact_at(p - vec2(SAMPLE_RADIUS, 0.0)));
     float east = snow_contact_height(snow_contact_at(p + vec2(SAMPLE_RADIUS, 0.0)));
     float north = snow_contact_height(snow_contact_at(p - vec2(0.0, SAMPLE_RADIUS)));
     float south = snow_contact_height(snow_contact_at(p + vec2(0.0, SAMPLE_RADIUS)));
     vec2 imprint_slope = clamp(vec2(west - east, south - north) * 2.4, vec2(-0.48), vec2(0.48));
     vec3 imprint_normal = normalize(vec3(imprint_slope, 1.0));
     float blend = clamp(length(imprint_slope) * 1.8 + contact.r * 0.35, 0.0, 1.0) * amount;
     NORMAL_MAP = normalize(mix(NORMAL_MAP * 2.0 - 1.0, imprint_normal, blend)) * 0.5 + 0.5;
     NORMAL_MAP_DEPTH = mix(NORMAL_MAP_DEPTH, 1.0, blend);
    }
   }
  }
 }
 float ao = (1. - (mat.albedo_height.a * log(2.1 - mat.ao_strength))) * (1. - mat.normal_rough.y);
 AO = clamp(1. - ao * mat.ao_strength, mat.albedo_height.a, 1.0);
 AO_LIGHT_AFFECT = (1.0 - mat.albedo_height.a) * clamp(mat.normal_rough.y, 0., 1.);
 // Compacted snow has its own texture AO.
 AO = mix(AO, packed_ao, max(packed_coverage, surface_cover));
 AO_LIGHT_AFFECT *= 1.0 - max(packed_coverage, surface_cover);

}

