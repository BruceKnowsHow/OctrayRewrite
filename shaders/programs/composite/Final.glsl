/*
layout (r32ui) uniform uimage2D colorimg0;
const int  colortex0Format = R32UI;
const bool colortex0Clear = false;
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

layout (r32ui) uniform uimage2D colorimg1;
const int colortex1Format = R32UI;
const bool colortex1Clear = true;
const vec4 colortex1ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

layout (r32ui) uniform uimage2D colorimg2;
const int colortex2Format = R32UI;
const bool colortex2Clear = true;
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int colortex5Format = RGBA8;
const bool colortex5Clear = true;
const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
*/

uniform sampler2D colortex9;
uniform sampler2D colortex8;
uniform sampler2D colortex5;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform vec3 cameraPosition;
uniform vec2 viewSize;
uniform float far;
uniform uint ZERO;

vec2 texcoord = gl_FragCoord.xy / viewSize * MC_RENDER_QUALITY;

#include "../../includes/debug.glsl"

void main() {
    gl_FragColor = 4.0*texture(colortex9, texcoord) / (texture(colortex9, texcoord) + 1);
    
    #ifdef DEBUG
        gl_FragColor = texture(colortex5, texcoord);
    #endif
}
