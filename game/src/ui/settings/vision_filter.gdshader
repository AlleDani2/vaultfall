shader_type canvas_item;
// Filtro di visione (1.0, accessibilità): ricolora l'immagine finale. SOLO colore (D-6): nessun PNG viene toccato.
//   mode: 0 spento, 1 protanopia, 2 deuteranopia, 3 tritanopia (correzione «daltonizzante»: l'errore di colore che la
//   visione ridotta non distingue viene spostato sui canali che si vedono, così rosso/verde o blu/giallo restano distinguibili)
//   contrast, saturation: alto contrasto (1,0 = invariato)
// Gli stessi calcoli sono in Accessibility.daltonize() (GDScript) per il test e per l'anteprima.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int mode = 0;
uniform float contrast = 1.0;
uniform float saturation = 1.0;

vec3 simulate(vec3 c, int m) {
	mat3 sim;
	if (m == 1) {
		sim = mat3(vec3(0.152286, 0.114503, -0.003882), vec3(1.052583, 0.786281, -0.048116), vec3(-0.204868, 0.099216, 1.051998));
	} else if (m == 2) {
		sim = mat3(vec3(0.367322, 0.280085, -0.011820), vec3(0.860646, 0.672501, 0.042940), vec3(-0.227968, 0.047413, 0.968881));
	} else {
		sim = mat3(vec3(1.255528, -0.078411, 0.004733), vec3(-0.076749, 0.930809, 0.691367), vec3(-0.178779, 0.147602, 0.303900));
	}
	return sim * c;
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	if (mode > 0) {
		vec3 err = c - simulate(c, mode);
		if (mode == 3) {
			c = clamp(c + vec3(-err.b, err.b, 0.0), 0.0, 1.0);      // blu/giallo perso: lo si sposta su rosso/verde
		} else {
			c = clamp(c + vec3(0.0, 0.7 * err.r + err.g, 0.7 * err.r + err.b), 0.0, 1.0);
		}
	}
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(lum), c, saturation);
	c = clamp((c - 0.5) * contrast + 0.5, 0.0, 1.0);
	COLOR = vec4(c, 1.0);
}
