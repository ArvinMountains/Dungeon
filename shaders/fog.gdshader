shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform float opacity: hint_range(0.0, 1.0) = 0.1;
uniform vec3 tint: source_color = vec3(0.51, 0.59, 0.50);

float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),f.x),f.y);}

void fragment(){
	vec2 p=UV*7.0+vec2(TIME*0.018,TIME*0.009);
	float n=noise(p)*0.65+noise(p*2.1)*0.35;
	float edge=smoothstep(0.0,0.18,UV.x)*smoothstep(0.0,0.18,1.0-UV.x)*smoothstep(0.0,0.18,UV.y)*smoothstep(0.0,0.18,1.0-UV.y);
	ALBEDO=tint;
	ALPHA=smoothstep(0.24,0.8,n)*opacity*edge;
}
