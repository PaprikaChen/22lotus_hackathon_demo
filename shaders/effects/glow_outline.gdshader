shader_type canvas_item;
// 轮廓外发光：沿本体 alpha 边缘向外扩一圈光，本体自身保持原样。
//
// 做法是在 UV 周围按三层同心环各取 12 个采样点，取 alpha 的最大值当作
// 「向外膨胀后的剪影」，再减掉本体 alpha —— 剩下的就是本体之外的那一圈。
// 越外层的环权重越低，所以光是往外衰减的，不是一圈硬边。
//
// 前提：贴图四周有透明余量（本项目的可交互物件是满画布贴图，余量很足）。
// 光画不到贴图矩形之外，所以紧贴边缘裁切的图会被切掉一半光。

uniform vec4 glow_color : source_color = vec4(1.0, 0.93, 0.72, 1.0);
// 0 = 完全不发光。解谜时由 SequencePuzzleItem 脉动这个值。
uniform float glow_strength : hint_range(0.0, 4.0) = 0.0;
// 发光扩散半径，单位是**贴图像素**（世界像素 = 这个值 × 精灵 scale）。
uniform float glow_radius : hint_range(0.0, 64.0) = 14.0;

const int RINGS = 3;
const int SAMPLES = 12;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float spread = 0.0;
	for (int ring = 1; ring <= RINGS; ring++) {
		float t = float(ring) / float(RINGS);
		float radius = glow_radius * t;
		// 外圈更暗：权重随半径线性衰减。
		float weight = 1.0 - (t - 1.0 / float(RINGS)) * 0.9;
		for (int i = 0; i < SAMPLES; i++) {
			float angle = TAU * float(i) / float(SAMPLES);
			vec2 offset = vec2(cos(angle), sin(angle)) * radius * TEXTURE_PIXEL_SIZE;
			spread = max(spread, texture(TEXTURE, UV + offset).a * weight);
		}
	}
	// 只保留本体之外的部分，本体内部交给贴图自己。
	float halo = clamp(spread - tex.a, 0.0, 1.0) * clamp(glow_strength, 0.0, 4.0);
	halo = clamp(halo, 0.0, 1.0) * glow_color.a;

	vec4 base = tex * COLOR;
	// 标准 over 合成：本体盖在光上。halo = 0 时逐像素等同原图——**不能**用
	// mix(glow, base, base.a)，那样半透明的抗锯齿边会被染上光色，看起来像描边。
	float glow_a = halo * COLOR.a * (1.0 - base.a);
	float out_a = base.a + glow_a;
	vec3 rgb = base.a > 0.0 || glow_a > 0.0
		? (base.rgb * base.a + glow_color.rgb * glow_a) / max(out_a, 0.0001)
		: base.rgb;
	COLOR = vec4(rgb, out_a);
}
