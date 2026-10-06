// Based on Pixelate into view (Custom Resolution), cak3_lover, CC0.
// https://godotshaders.com/shader/pixelate-into-view-custom-resolution/
shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 custom_resolution = vec2(160.0, 90.0);

float rand(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 96.233))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(UV * max(custom_resolution, vec2(1.0)));
	vec4 color = texture(TEXTURE, UV);
	// Explicit endpoints ensure complete coverage at 0 and no remnants at 1.
	float keep = progress <= 0.0 ? 1.0 : (progress >= 1.0 ? 0.0 : step(progress, rand(cell)));
	COLOR = vec4(color.rgb, color.a * keep);
}
