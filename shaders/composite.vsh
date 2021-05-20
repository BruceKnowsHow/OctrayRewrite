#include "../glsl_version.glsl"
#include "worldID.glsl"

void main() {
    gl_Position = ftransform();
    gl_Position.x = gl_Position.x * 100.0 - 99.0;
    gl_Position.y = gl_Position.y * 2.5 - 0.5;
}
