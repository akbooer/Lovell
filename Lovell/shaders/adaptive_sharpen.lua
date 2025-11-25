
--[[

// #version 120 (LÖVE2D defaults to a compatible version)

// Uniforms provided by LÖVE2D automatically:
// sampler2D Texel (the image texture being drawn)
// vec2 TexelSize (size of a single pixel in texture coordinates)

extern float sharpness; // A custom uniform to control the strength (0.0 to 1.0)

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    // Determine the distance of one pixel in texture coordinates
    vec2 px = TexelSize;

    // Sample the center pixel and its immediate neighbors (4-tap cross pattern)
    vec3 c = Texel(texture_coords).rgb;
    vec3 c2 = Texel(texture_coords + vec2(0, -px.y)).rgb; // Up
    vec3 c4 = Texel(texture_coords + vec2(-px.x, 0)).rgb; // Left
    vec3 c6 = Texel(texture_coords + vec2(px.x, 0)).rgb;  // Right
    vec3 c8 = Texel(texture_coords + vec2(0, px.y)).rgb;  // Down

    // Calculate local contrast (min and max RGB values in the neighborhood)
    vec3 minRGB = min(c, min(c2, min(c4, min(c6, c8))));
    vec3 maxRGB = max(c, max(c2, max(c4, max(c6, c8))));

    // Calculate the amplitude/sharpening factor based on local contrast
    // Smallest distance to the signal limit [0 to 1]
    minRGB = min(minRGB, 1.0 - maxRGB);
    // Inverse of maxRGB provides a weight: low contrast gets high weight
    vec3 ampRGB = minRGB / maxRGB; 

    // Apply a sqrt curve to soften the response and blend
    vec3 weight = sqrt(ampRGB) * sharpness * 0.05; // 0.05 is a base scale factor

    // Apply the sharpening (unsharp mask principle)
    // The center pixel is enhanced based on the difference from neighbors, weighted locally.
    vec3 sharpened_color = c + (c - (c2 + c4 + c6 + c8) / 4.0) * weight;

    // Clamp the output color to ensure it stays within valid [0, 1] range
    return vec4(clamp(sharpened_color, 0.0, 1.0), 1.0);
}
--]]
