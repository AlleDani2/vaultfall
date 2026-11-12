shader_type canvas_item;
// Banda di luce che attraversa un'icona/tessera (ShineSweep). Compatibile con GL Compatibility.
// La banda è a GRADINI (pixel nitidi, niente sfumatura): un nucleo chiaro e un bordo più tenue; agisce solo dove
// la texture è opaca (l'icona non «sbava» fuori dalla sua sagoma).
uniform float progress : hint_range(-0.5, 1.5) = -1.0;
uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float band_width = 0.16;
uniform float strength = 0.75;
uniform float cells = 24.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 q = floor(UV * cells) / cells;                 // quantizza: bordi della banda a pixel
	float d = (q.x + q.y * 0.55) / 1.55 - progress;
	float core = step(abs(d), band_width * 0.5);
	float edge = step(abs(d), band_width) - core;
	float k = (core * 1.0 + edge * 0.45) * strength;
	COLOR = vec4(mix(c.rgb, shine_color.rgb, k), c.a);
}
