shader_type spatial;
uniform sampler2D snow_color : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D snow_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D ice_color : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D ice_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D ice_roughness : repeat_enable, filter_linear_mipmap_anisotropic;
uniform bool rock_mode=false;
varying vec3 world_position;
varying vec3 world_normal;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;world_normal=MODEL_NORMAL_MATRIX*NORMAL;}
void fragment(){
 vec3 n=normalize(world_normal);
 vec3 weights=pow(abs(n),vec3(4.0));weights/=max(dot(weights,vec3(1.0)),.001);
 vec2 uv=world_position.xz/2.4;
 vec2 a=vec2(.37,.23),b=vec2(-.19,.41),c=vec2(-.31,.29),d=vec2(.43,.17);
 float pa=dot(uv,a)+.8,pb=dot(uv,b)+2.3,pc=dot(uv,c)+1.7,pd=dot(uv,d)+4.1;
 vec2 at=uv+.65*vec2(sin(pa)+.5*sin(pb),sin(pc)+.5*sin(pd));
 vec3 powder=texture(snow_color,at).rgb;
 vec4 packed=texture(snow_normal,at);
 vec3 p=world_position/.9;
 vec3 ice=texture(ice_color,p.zy).rgb*weights.x+texture(ice_color,p.xz).rgb*weights.y+texture(ice_color,p.xy).rgb*weights.z;
 float rough=texture(ice_roughness,p.zy).r*weights.x+texture(ice_roughness,p.xz).r*weights.y+texture(ice_roughness,p.xy).r*weights.z;
 float value=dot(ice,vec3(.2126,.7152,.0722));
 // Internal cracks modulate pale glacial ice, rather than becoming black painted veins.
 vec3 blue=mix(vec3(.38,.50,.53),vec3(.65,.74,.76),sqrt(clamp(value,0.0,1.0)))*.92;
 if(rock_mode){blue=ice*vec3(.72,.76,.78);}
 float coat=clamp(COLOR.r*smoothstep(.25,.82,n.y),0.0,1.0);
 ALBEDO=mix(blue,powder,coat);
 ROUGHNESS=mix(clamp(rough*.72+.08,rock_mode ? .65 : .12,.85),packed.a,coat);
 SPECULAR=mix(.34,.22,coat);
 // Triplanar detail on steep fractures; no stretched horizontal UVs.
 vec3 tx=texture(ice_normal,p.zy).rgb*2.0-1.0;
 vec3 ty=texture(ice_normal,p.xz).rgb*2.0-1.0;
 vec3 tz=texture(ice_normal,p.xy).rgb*2.0-1.0;
 vec3 fracture=normalize(vec3(tx.z*sign(n.x),tx.y,tx.x)*weights.x+vec3(ty.x,ty.z*sign(n.y),-ty.y)*weights.y+vec3(tz.x,tz.y,tz.z*sign(n.z))*weights.z);
 vec3 ice_n=normalize(mix(n,fracture,.28));
 vec3 snow_n=normalize(n+vec3(packed.r*2.0-1.0,0,-(packed.g*2.0-1.0))*.5);
 NORMAL=normalize((VIEW_MATRIX*vec4(normalize(mix(ice_n,snow_n,coat)),0.0)).xyz);
}
