shader_type canvas_item;

// ─── Couleur principale ───────────────────────────────────────────────────────
uniform vec4 base_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);

// ─── Épaisseur des 4 faces latérales (en UV, 0.0 à 0.5) ──────────────────────
uniform float face_top_h    : hint_range(0.04, 0.30) = 0.13;
uniform float face_bottom_h : hint_range(0.04, 0.30) = 0.13;
uniform float face_left_w   : hint_range(0.04, 0.30) = 0.13;
uniform float face_right_w  : hint_range(0.04, 0.30) = 0.13;

// ─── Multiplicateurs de luminosité de chaque face ────────────────────────────
uniform float bright_top    : hint_range(1.0, 2.5) = 1.85;
uniform float bright_left   : hint_range(1.0, 2.0) = 1.30;
uniform float bright_center : hint_range(0.8, 1.5) = 1.05;
uniform float dark_right    : hint_range(0.1, 1.0) = 0.55;
uniform float dark_bottom   : hint_range(0.1, 1.0) = 0.35;

// ─── Reflet brillant sur la face top ─────────────────────────────────────────
uniform float gloss_strength : hint_range(0.0, 1.0) = 0.40;
uniform float gloss_width    : hint_range(0.1, 1.0) = 0.55;

// ─── Netteté des bordures entre faces ────────────────────────────────────────
uniform float edge_sharpness : hint_range(10.0, 200.0) = 80.0;

// ─── Coins arrondis ───────────────────────────────────────────────────────────
uniform float corner_radius  : hint_range(0.0, 0.15) = 0.06;
uniform float corner_ao      : hint_range(0.0, 1.0)  = 0.55;

// ═══════════════════════════════════════════════════════════════════════════════

float sharp_mask(float value, float threshold) {
    return clamp((value - threshold) * edge_sharpness + 0.5, 0.0, 1.0);
}

vec3 saturate_color(vec3 c, float amount) {
    float lum = dot(c, vec3(0.299, 0.587, 0.114));
    return clamp(mix(vec3(lum), c, 1.0 + amount), 0.0, 1.0);
}

void fragment() {
    vec2 uv = UV;
    vec3 base = base_color.rgb;

    // ── 1. MASQUES DES 4 FACES ────────────────────────────────────────────────
    float m_top    = 1.0 - sharp_mask(uv.y,       face_top_h);
    float m_bottom = 1.0 - sharp_mask(1.0 - uv.y, face_bottom_h);
    float m_left   = 1.0 - sharp_mask(uv.x,       face_left_w);
    float m_right  = 1.0 - sharp_mask(1.0 - uv.x, face_right_w);

    float m_center = sharp_mask(uv.y,       face_top_h)
                   * sharp_mask(1.0 - uv.y, face_bottom_h)
                   * sharp_mask(uv.x,       face_left_w)
                   * sharp_mask(1.0 - uv.x, face_right_w);

    // Les coins appartiennent aux faces haut/bas (priorité)
    float m_left_clean  = m_left  * (1.0 - m_top) * (1.0 - m_bottom);
    float m_right_clean = m_right * (1.0 - m_top) * (1.0 - m_bottom);

    // ── 2. COULEUR DE CHAQUE FACE ─────────────────────────────────────────────

    // Centre : base saturée
    vec3 col_center = saturate_color(base * bright_center, 0.15);

    // Top : très claire + reflet glossy
    vec3 col_top = clamp(base * bright_top + vec3(0.12), 0.0, 1.0);
    float gloss_x = smoothstep(gloss_width, 0.0, uv.x);
    col_top += gloss_x * gloss_strength * m_top;

    // Gauche : éclairée
    vec3 col_left = base * bright_left;

    // Droite : sombre, teinte froide
    vec3 col_right = base * dark_right;
    col_right = mix(col_right, col_right * vec3(0.85, 0.9, 1.1), 0.4);

    // Bas : très sombre
    vec3 col_bottom = base * dark_bottom;
    col_bottom = mix(col_bottom, col_bottom * vec3(0.8, 0.85, 1.0), 0.3);

    // ── 3. COMPOSITION ────────────────────────────────────────────────────────
    vec3 col = col_center;
    col = mix(col, col_top,    m_top);
    col = mix(col, col_bottom, m_bottom);
    col = mix(col, col_left,   m_left_clean);
    col = mix(col, col_right,  m_right_clean);

    // ── 4. AMBIENT OCCLUSION COINS ────────────────────────────────────────────
    float d_corner = min(
        min(length(uv - vec2(0.0, 0.0)), length(uv - vec2(1.0, 0.0))),
        min(length(uv - vec2(0.0, 1.0)), length(uv - vec2(1.0, 1.0)))
    );
    float ao = smoothstep(0.0, corner_radius * 1.5, d_corner);
    col *= mix(1.0 - corner_ao, 1.0, ao);

    // ── 5. COINS ARRONDIS (alpha) ─────────────────────────────────────────────
    vec2 q = abs(uv - 0.5) - (0.5 - corner_radius);
    float dist_rounded = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
    float alpha = 1.0 - smoothstep(-0.01, 0.01, dist_rounded - corner_radius);

    col = clamp(col, 0.0, 1.0);
    COLOR = vec4(col, base_color.a * alpha * COLOR.a);
}
