shader_type canvas_item;
// Dissolvenza a blocchi (morte del mostro): ogni «cella» sparisce a un istante casuale, con un bordo incandescente.
// Pixel quadrati: la griglia è quantizzata, nessuna sfocatura.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float cells = 32.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 g = floor(UV * cells);
	float n = hash(g) * 0.75 + (1.0 - UV.y) * 0.25;     // dall'alto verso il basso, con disordine
	float a = amount * 1.15;
	if (n < a - 0.09) {
		COLOR = vec4(0.0);
	} else if (n < a) {
		COLOR = vec4(edge_color.rgb, c.a);
	} else {
		COLOR = c;
	}
}
