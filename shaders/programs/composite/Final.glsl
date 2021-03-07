/*
layout (r32ui) uniform uimage2D colorimg0;
const int  colortex0Format = R32UI;
const bool colortex0Clear = true;
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

layout (r32ui) uniform uimage2D colorimg1;
const int colortex1Format = R32UI;
const bool colortex1Clear = false;
const vec4 colortex1ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

layout (r32ui) uniform uimage2D colorimg2;
const int colortex2Format = R32UI;
const bool colortex2Clear = true;
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

layout (r32ui) uniform uimage2D colorimg3;
const int colortex3Format = R32UI;
const bool colortex3Clear = true;
const vec4 colortex3ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

layout (rgba8) uniform uimage2D colorimg4;
const int colortex4Format = RGBA8;
const bool colortex4Clear = true;
const vec4 colortex4ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
*/

uniform sampler2D colortex4;
uniform sampler2D colortex9;
uniform sampler2D colortex8;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform vec3 cameraPosition;
uniform vec2 viewSize;
uniform float far;
uniform uint ZERO;

vec2 texcoord = gl_FragCoord.xy / viewSize * MC_RENDER_QUALITY;

void main() {
    gl_FragColor = texture(colortex9, texcoord);
}
