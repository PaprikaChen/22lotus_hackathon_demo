shader_type canvas_item;
// 画布物件的饱和度 / 亮度调节。只改颜色，不动 alpha，也不做任何位移，
// 所以可以安全挂在玩家 Sprite 上而不影响碰撞与对位。
//
// saturation: 1.0 = 原色，0.0 = 完全黑白。
// brightness: 1.0 = 原亮度，<1.0 变暗。

uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float brightness : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Rec. 709 亮度权重：比简单平均更贴近人眼对去色的预期。
	float luma = dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 rgb = mix(vec3(luma), tex.rgb, saturation) * brightness;
	COLOR = vec4(rgb, tex.a) * COLOR;
}
