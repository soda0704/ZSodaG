shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float opacity = 0.6;
uniform mat4 base_inverse;
uniform vec3 clear_min[9];
uniform vec3 clear_max[9];
varying vec3 world_point;
varying float flake_seed;
void vertex() {
 world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 flake_seed=fract(float(INSTANCE_ID)*0.618033989);
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
 MODELVIEW_MATRIX=MODELVIEW_MATRIX*mat4(vec4(length(MODEL_MATRIX[0].xyz),0,0,0),vec4(0,length(MODEL_MATRIX[1].xyz),0,0),vec4(0,0,length(MODEL_MATRIX[2].xyz),0),vec4(0,0,0,1));
 float c=cos(INSTANCE_CUSTOM.x);float s=sin(INSTANCE_CUSTOM.x);
 VERTEX.xy=mat2(vec2(c,s),vec2(-s,c))*VERTEX.xy;
}
void fragment() {
 vec3 p=(base_inverse*vec4(world_point,1)).xyz;
 bool inside=p.y< -8.0;
 for(int i=0;i<9;i++) { inside=inside||(all(greaterThan(p,clear_min[i]))&&all(lessThan(p,clear_max[i]))); }
 vec2 q=(UV-0.5)*2.0;
 float angle=atan(q.y,q.x)+flake_seed*6.283185;
 // Soft irregular clusters, rather than identical stretched discs or stars.
 float edge=0.73+0.10*sin(angle*5.0+flake_seed*17.0)+0.06*sin(angle*9.0);
 float shape=1.0-smoothstep(edge-0.25,edge,length(q));
 float texture_detail=0.82+0.18*sin(q.x*19.0+flake_seed*31.0)*sin(q.y*23.0);
 float proximity=smoothstep(0.25,0.7,length(VERTEX));
 ALBEDO=vec3(.86,.92,.96);
 ALPHA=inside?0.0:shape*texture_detail*opacity*proximity;
}
