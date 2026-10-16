shader_type spatial;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap, repeat_enable;
uniform sampler2D floor_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float texture_scale : hint_range(0.1, 2.0) = 0.45;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.65;
uniform vec3 tint : source_color = vec3(0.75, 0.78, 0.80);
varying vec3 world_position;
varying vec3 world_normal;
varying float snow_mask;
void vertex() {
 world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
 snow_mask=COLOR.r;
}
vec3 projected(sampler2D map, vec3 p, vec3 w) {
 return texture(map,p.yz).rgb*w.x+texture(map,p.xz).rgb*w.y+texture(map,p.xy).rgb*w.z;
}
void fragment() {
 vec3 n=normalize(world_normal);
 vec3 w=pow(abs(n),vec3(5.0)); w/=max(dot(w,vec3(1.0)),0.001);
 vec3 p=world_position*texture_scale;
 vec3 color=projected(rock_albedo,p,w)*tint;
 float floor_mix=smoothstep(0.65,0.94,n.y)*0.70;
 color=mix(color,projected(floor_albedo,world_position*0.60,w)*0.85,floor_mix);
 float snow=snow_mask*smoothstep(0.25,0.8,n.y);
 ALBEDO=mix(color,vec3(0.77,0.80,0.83),snow);
 ROUGHNESS=mix(clamp(projected(rock_roughness,p,w).r,0.65,1.0),0.98,snow);
 vec3 nx=texture(rock_normal,p.yz).xyz*2.0-1.0;
 vec3 ny=texture(rock_normal,p.xz).xyz*2.0-1.0;
 vec3 nz=texture(rock_normal,p.xy).xyz*2.0-1.0;
 vec3 bump=vec3(nx.z*sign(n.x),nx.x,nx.y)*w.x
           +vec3(ny.x,ny.z*sign(n.y),ny.y)*w.y
           +vec3(nz.x,nz.y,nz.z*sign(n.z))*w.z;
 NORMAL=normalize(mat3(VIEW_MATRIX)*normalize(mix(n,bump,normal_strength*(1.0-snow))));
}
