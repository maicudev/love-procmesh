#pragma language glsl3
varying vec3 normal;
varying vec4 frag_position;
uniform mat4 m_view;

uniform vec4 baseColor;

struct DirectionalLight {
	vec3 direction;
	vec3 ambient;
	vec3 diffuse;
	vec3 specular;
};

const int MAX_DIRECTIONAL_LIGHTS = 4;
uniform DirectionalLight directional_lights[MAX_DIRECTIONAL_LIGHTS];
uniform int directional_lights_count;

vec3 calculate_directional_light(in DirectionalLight light, vec3 normal, vec3 viewDir) {
	vec3 light_direction = normalize(-(m_view * vec4(light.direction, 0.0)).xyz);
	float diff = max(dot(normal, light_direction), 0.0);

	vec3 reflect_direction = reflect(-light_direction, normal);
	float spec = diff > 0.0 ? pow(max(dot(viewDir, reflect_direction), 0.0), 48.0) : 0.0;

	return light.ambient + light.diffuse * diff + light.specular * spec;
} 

vec4 effect(vec4 color, Image t, vec2 texture_coords, vec2 screen_coords) {
	vec3 frag_p = frag_position.xyz / frag_position.w;
	vec3 surface_normal = normalize(normal);
	vec3 view_direction = normalize(-frag_p);

	vec3 result = vec3(0.0);
	for(int i = 0; i < directional_lights_count; i++) {
		result += calculate_directional_light(directional_lights[i], surface_normal, view_direction);
	}

	vec4 texcolor = Texel(t, texture_coords);
	if( texcolor.a <= 0.0 ) discard;
	vec4 albedo = texcolor * color * baseColor;
	return vec4(albedo.rgb * result, albedo.a);
}