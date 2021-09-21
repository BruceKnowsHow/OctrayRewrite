#include "../glsl_version.glsl"
#include "worldID.glsl"
#define final
#define fsh

void main() {
    gl_Position = ftransform();
}