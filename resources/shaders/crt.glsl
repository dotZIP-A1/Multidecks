extern number time;
extern vec2 resolution;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    vec2 uv = texture_coords;

    // 1. CRT Screen Curvature (Balatro's subtle lens warp)
    vec2 centered = uv - 0.5;
    float distortion = 0.08; // Increase for more curve
    uv = uv + centered * dot(centered, centered) * distortion;

    // Clamp coordinates so the texture doesn't wrap awkwardly at the warped edges
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return vec4(0.0, 0.0, 0.0, 1.0); // Black borders
    }

    // 2. Balatro-style Psychedelic Wave Distortion
    // This gently warps the texture lookup based on time
    vec2 waveUv = uv;
    waveUv.x += sin(uv.y * 10.0 + time * 2.0) * 0.003;
    waveUv.y += cos(uv.x * 10.0 + time * 1.5) * 0.003;

    // Fetch the texture using our waved coordinates
    vec4 texColor = Texel(texture, waveUv);

    // 3. Moving Scanlines
    float scanline = sin((uv.y * resolution.y * 1.2) - (time * 4.0)) * 0.03;
    texColor.rgb -= scanline;

    // 4. Vignette (Darkened edges)
    float vignette = 1.0 - dot(centered, centered) * 0.4;
    texColor.rgb *= vignette;

    return texColor * color;
}