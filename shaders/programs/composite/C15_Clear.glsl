uniform sampler2D depthtex0;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform vec3 cameraPosition;
uniform vec2 viewSize;
uniform float far;
uniform bool accum;

vec2 texcoord = gl_FragCoord.xy / viewSize;

#include "../../includes/debug.glsl"

/* DRAWBUFFERS:8 */

void main() {
    ivec2 coord = ivec2(gl_FragCoord.xy);
    
    float depth = texelFetch(depthtex0, coord, 0).x;
    
    gl_FragData[0] = vec4(depth, 0.0, 0.0, 0.0);
}
