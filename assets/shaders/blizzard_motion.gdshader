shader_type particles;
// Per-particle drift plus a coherent wind field; CUSTOM carries actual velocity.
uniform vec3 wind_direction = vec3(1.0, -0.2, 0.4);
uniform vec3 emission_extents = vec3(9.0, 4.0, 9.0);
float random_value(float n) { return fract(sin(n)*43758.5453); }
void start() {
 float seed=float(NUMBER)+float(RANDOM_SEED%10000u);
 vec3 sample_point=vec3(random_value(seed*12.7+1.0),random_value(seed*31.1+2.0),random_value(seed*74.7+3.0));
 TRANSFORM=mat4(1.0);
 TRANSFORM[3].xyz=(sample_point*2.0-1.0)*emission_extents;
 TRANSFORM=EMISSION_TRANSFORM*TRANSFORM;
 float size=mix(0.5,2.2,random_value(seed*17.3+4.0));
 TRANSFORM[0].xyz*=size;TRANSFORM[1].xyz*=size;TRANSFORM[2].xyz*=size;
 CUSTOM.w=random_value(seed*43.7+5.0);
 VELOCITY=normalize(wind_direction)*mix(12.0,21.0,CUSTOM.w);
 CUSTOM.xyz=VELOCITY;
}
void process() {
 float phase=CUSTOM.w*61.7;
 vec3 p=TRANSFORM[3].xyz;
 vec3 crosswind=vec3(sin(phase+TIME*2.1+p.z*0.37),sin(phase*1.7+TIME*2.8+p.x*0.4),cos(phase+TIME*1.8+p.x*0.31));
 vec3 personal=vec3(sin(phase*3.1),sin(phase*2.3)*0.6,cos(phase*4.7));
 vec3 target=normalize(wind_direction)*mix(12.0,21.0,CUSTOM.w)+personal*5.0+crosswind*7.0;
 VELOCITY=mix(VELOCITY,target,1.0-exp(-DELTA*4.0));
 CUSTOM.xyz=VELOCITY;
}
