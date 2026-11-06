shader_type spatial;
render_mode cull_disabled;
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


varying vec2 world_xz;
void vertex(){world_xz=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;}
void fragment(){
 vec3 color;vec3 normal;float roughness;float snow_ao;
 sample_snow02(world_xz,(INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz,length(VERTEX),color,normal,roughness,snow_ao);
 ALBEDO=color;NORMAL_MAP=normal*0.5+0.5;NORMAL_MAP_DEPTH=1.0;
 ROUGHNESS=roughness;SPECULAR=0.22;AO=snow_ao;
}
