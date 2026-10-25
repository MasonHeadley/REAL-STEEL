shader_type canvas_item;
// The start menu's camcorder look, drawn over the whole screen: a soft, washed-out picture
// with tape wobble, colour fringes, grain, scan lines and dark corners. `glitch` adds a burst
// of static and tearing at a cut; `wide` bends the picture like an action camera's lens.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float glitch = 0.0;
uniform float wide = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	uv = 0.5 + c * (1.0 + wide * r2) / (1.0 + wide * 0.3);
	// Each line of the picture sits a hair to one side of where it should; at a cut, whole
	// bands tear sideways.
	float tick = floor(TIME * 24.0);
	uv.x += (hash(vec2(floor(uv.y * 240.0), tick)) - 0.5) * 0.0016;
	uv.x += glitch * glitch * (hash(vec2(floor(uv.y * 28.0), tick)) - 0.5) * 0.12;
	// A band of bad tracking that crawls up the picture.
	float band = smoothstep(0.03, 0.0, abs(fract(uv.y + TIME * 0.06) - 0.5));
	uv.x += band * 0.006 * sin(TIME * 40.0 + uv.y * 300.0);

	float fringe = 0.0016 + glitch * 0.012 + band * 0.004;
	vec3 col = vec3(texture(screen, uv + vec2(fringe, 0.0)).r, texture(screen, uv).g, texture(screen, uv - vec2(fringe, 0.0)).b);
	col = mix(col, textureLod(screen, uv, 2.0).rgb, 0.35);

	// Cheap tape: less colour, more contrast, a yellow-green cast and milky shadows.
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(grey), col, 0.6);
	col = (col - 0.5) * 1.15 + 0.47;
	col = col * vec3(1.03, 1.0, 0.88) + vec3(0.02, 0.025, 0.03);

	col += (hash(uv * vec2(1600.0, 900.0) + tick) - 0.5) * 0.1;
	col *= 0.92 + 0.08 * sin(uv.y * 900.0);
	col *= 1.0 - r2 * 1.1;
	float snow = hash(uv * 700.0 + TIME * 90.0);
	col = mix(col, vec3(snow), max(glitch * glitch * 0.75 * step(0.45, hash(vec2(floor(uv.y * 36.0), tick))), band * 0.12));
	COLOR = vec4(col, 1.0);
}
