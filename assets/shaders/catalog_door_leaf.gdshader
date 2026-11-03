shader_type spatial;
render_mode cull_disabled;
uniform mat4 door_world_to_local;
uniform vec2 aperture = vec2(2.3,2.7);
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float metallic = 1.0;
uniform float roughness = 1.0;
uniform float normal_scale = 1.0;
uniform bool normal_enabled = true;
uniform bool ao_enabled = true;
uniform float ao_light_affect = 0.0;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
varying vec3 door_point;
void vertex() {
 door_point = (door_world_to_local * MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
 UV = UV * uv_scale.xy + uv_offset.xy;
}
void fragment() {
 // The moving leaf is visible only inside its fixed doorway pocket.
 // Discard also affects shadow/depth passes; no transparent overlay or second mesh.
 if(abs(door_point.x) > aperture.x * 0.5 + 0.012 || door_point.y < -0.012 || door_point.y > aperture.y + 0.012) discard;
 ALBEDO = texture(albedo_texture,UV).rgb * albedo.rgb;
 vec3 orm = texture(orm_texture,UV).rgb;
 METALLIC = orm.b * metallic;
 ROUGHNESS = orm.g * roughness;
 if(ao_enabled) { AO=orm.r; AO_LIGHT_AFFECT=ao_light_affect; }
 if(normal_enabled) { NORMAL_MAP=texture(normal_texture,UV).rgb; NORMAL_MAP_DEPTH=normal_scale; }
}
