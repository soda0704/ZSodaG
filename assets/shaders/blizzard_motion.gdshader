shader_type particles;
// Per-particle drift plus a coherent wind field; CUSTOM carries actual velocity.
uniform vec3 wind_direction = vec3(1.0, -0.2, 0.4);
uniform vec3 emission_extents = vec3(9.0, 4.0, 9.0);
uniform float gust = 0.0;
uniform float ground_height = -1000.0;
uniform vec3 wake_center = vec3(0.0, -1000.0, 0.0);

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
 if (CUSTOM.w < 0.23 && abs(TRANSFORM[3].y-ground_height)<9.0) {
  TRANSFORM[3].y=mix(ground_height+0.12,ground_height+0.85,sample_point.y);
 }
 VELOCITY=normalize(wind_direction)*mix(12.0,21.0,CUSTOM.w);
 CUSTOM.xyz=VELOCITY;
}
void process() {
 float phase=CUSTOM.w*61.7;
 vec3 p=TRANSFORM[3].xyz;
 vec3 crosswind=vec3(sin(phase+TIME*2.1+p.z*0.37),sin(phase*1.7+TIME*2.8+p.x*0.4),cos(phase+TIME*1.8+p.x*0.31));
 vec3 personal=vec3(sin(phase*3.1),sin(phase*2.3)*0.6,cos(phase*4.7));
 vec3 forward=normalize(wind_direction);
 vec3 sideways=normalize(cross(forward,vec3(0.0,1.0,0.0)));
 float turn=sin(TIME*0.58+p.x*0.09+p.z*0.07);
 vec3 flow=normalize(forward+sideways*turn*mix(0.22,0.64,gust));
 vec3 target=flow*mix(9.0,24.0,gust)*mix(0.65,1.25,CUSTOM.w)+personal*6.0+crosswind*5.0;
 vec3 wake=p-wake_center;
 float wake_strength=1.0-smoothstep(1.0,6.0,length(wake));
 target+=vec3(-wake.z,0.15,wake.x)*wake_strength*2.8*sin(TIME*2.0+phase*0.12);
 if (CUSTOM.w < 0.23 && abs(p.y-ground_height)<3.0) {
  target.y=clamp((ground_height+0.5-p.y)*5.0+crosswind.y,-4.0,4.0);
 }
 VELOCITY=mix(VELOCITY,target,1.0-exp(-DELTA*4.0));
 CUSTOM.xyz=VELOCITY;
}
