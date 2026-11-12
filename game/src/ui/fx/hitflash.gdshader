shader_type canvas_item;
// Lampo bianco di colpo: mescola il colore verso il bianco SOLO dove la texture è opaca (la sagoma non cambia).
// Solo colore: nessuna geometria toccata (regola D-6).
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(c.rgb, flash_color.rgb, flash), c.a);
}
