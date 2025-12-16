shader_type spatial;

uniform vec4 grid_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);  // Cyan
uniform vec4 background_color : source_color = vec4(0.05, 0.05, 0.1, 1.0);  // Dark blue
uniform float grid_size : hint_range(0.1, 10.0) = 1.0;  // Size of each grid square
uniform float line_width : hint_range(0.01, 0.5) = 0.05;  // Thickness of lines
uniform float major_grid_every : hint_range(0.0, 20.0) = 5.0;  // Thicker line every N squares
uniform float major_line_width : hint_range(0.01, 1.0) = 0.1;

void fragment() {
    // Get world position (UV * object scale)
    vec2 pos = UV * 100.0;  // Adjust 100.0 to match your track scale

    // Calculate grid
    vec2 grid = abs(fract(pos / grid_size - 0.5) - 0.5) / fwidth(pos / grid_size);
    float line = min(grid.x, grid.y);

    // Major grid lines
    vec2 major_grid = abs(fract(pos / (grid_size * major_grid_every) - 0.5) - 0.5) / fwidth(pos / (grid_size * major_grid_every));
    float major_line = min(major_grid.x, major_grid.y);

    // Combine lines
    float grid_mask = 1.0 - min(line / line_width, 1.0);
    float major_mask = 1.0 - min(major_line / major_line_width, 1.0);

    // Mix colors
    vec3 color = background_color.rgb;
    color = mix(color, grid_color.rgb, grid_mask * 0.3);  // Regular grid
    color = mix(color, grid_color.rgb, major_mask * 0.6);  // Major grid brighter

    ALBEDO = color;
    ROUGHNESS = 0.8;
    METALLIC = 0.0;
}