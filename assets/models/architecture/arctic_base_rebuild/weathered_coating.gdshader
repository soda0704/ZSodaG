shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D coating_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D coating_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D coating_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
vec2 hash2(vec2 p) {
 return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453);
}
void fragment(){
 // Triangular blending offsets ALL PBR channels together. The sampling
 // gradients exclude cell hashing, preventing mip seams at cell boundaries.
 vec2 grid=mat2(vec2(1.0,0.0),vec2(-0.57735027,1.15470054))*(UV*.65);
 vec2 cell=floor(grid), f=fract(grid);
 vec2 a=cell,b=cell+vec2(1,0),c=cell+vec2(0,1);
 vec3 w=vec3(1.0-f.x-f.y,f.x,f.y);
 if(f.x+f.y>1.0){a=cell+vec2(1,1);w=vec3(f.x+f.y-1.0,1.0-f.y,1.0-f.x);}
 w=w*w*(3.0-2.0*w);w/=dot(w,vec3(1.0));
 vec2 dx=dFdx(UV),dy=dFdy(UV);
 vec3 color=vec3(0),normal=vec3(0);float rough=0.0;
 for(int i=0;i<3;i++){
  vec2 id=i==0?a:(i==1?b:c);vec2 h=hash2(id);
  float scale=mix(.82,1.18,h.x);vec2 at=UV*scale+h*39.7;
  color+=textureGrad(coating_color,at,dx*scale,dy*scale).rgb*w[i];
  normal+=(textureGrad(coating_normal,at,dx*scale,dy*scale).xyz*2.0-1.0)*w[i];
  rough+=textureGrad(coating_roughness,at,dx*scale,dy*scale).r*w[i];
 }
 // The scanned coating provides colour only. Lighting supplies all shading;
 // no position-based darkening or baked vertex wear is multiplied into it.
 ALBEDO=color;
 NORMAL_MAP=normalize(normal)*.5+.5;NORMAL_MAP_DEPTH=.35;
 ROUGHNESS=clamp(.60+.34*rough,.60,.94);METALLIC=.02;
}
