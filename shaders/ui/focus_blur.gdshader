shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float blur_radius : hint_range(0.0, 12.0) = 0.0;

void fragment() {
	vec2 pixel = 1.0 / vec2(textureSize(screen_texture, 0));
	vec2 offset = pixel * blur_radius;
	vec4 color = texture(screen_texture, SCREEN_UV) * 0.20;
	color += texture(screen_texture, SCREEN_UV + vec2(offset.x, 0.0)) * 0.12;
	color += texture(screen_texture, SCREEN_UV - vec2(offset.x, 0.0)) * 0.12;
	color += texture(screen_texture, SCREEN_UV + vec2(0.0, offset.y)) * 0.12;
	color += texture(screen_texture, SCREEN_UV - vec2(0.0, offset.y)) * 0.12;
	color += texture(screen_texture, SCREEN_UV + offset) * 0.08;
	color += texture(screen_texture, SCREEN_UV - offset) * 0.08;
	color += texture(screen_texture, SCREEN_UV + vec2(offset.x, -offset.y)) * 0.08;
	color += texture(screen_texture, SCREEN_UV + vec2(-offset.x, offset.y)) * 0.08;
	COLOR = color;
}
