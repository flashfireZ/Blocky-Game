shader_type canvas_item;

uniform vec4 fill_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform vec4 border_color : source_color = vec4(0.1, 0.3, 0.5, 1.0);
uniform float corner_radius : hint_range(0.0, 0.5) = 0.08;
uniform float border_width : hint_range(0.0, 0.15) = 0.04;
uniform float border_darkness : hint_range(0.0, 1.0) = 0.4;

void fragment() {
    vec2 uv = UV;

    // Coins arrondis
    vec2 q = abs(uv - 0.5) - (0.5 - corner_radius);
    float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
    float alpha = 1.0 - smoothstep(corner_radius - 0.015, corner_radius + 0.015, dist);

    // Bordure
    float inner = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float is_border = 1.0 - smoothstep(border_width - 0.005, border_width + 0.005, inner);

    vec3 col = mix(fill_color.rgb, border_color.rgb, is_border);

    COLOR = vec4(col, fill_color.a * alpha);
}