uniform sampler2D colortex9;
uniform sampler2D colortex2;
uniform sampler2D colortex8;
uniform sampler2D colortex5;
uniform sampler2D depthtex0;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform vec3 cameraPosition;
uniform vec2 viewSize;
uniform bool accum;

vec2 texcoord = gl_FragCoord.xy / viewSize;

#include "../../includes/Debug.glsl"


// Atomic color read
#define screen_color_tex colortex4
uniform usampler2D screen_color_tex;

vec3 DecodeColor(uvec2 enc) {
    uvec3 col;
    col.r = enc.r & ((1<<16)-1);
    col.g = enc.r >> 16;
    col.b = enc.g;
    
    vec3 color = vec3(col);
    return color / 256.0;
}

vec3 ReadColor(ivec2 screenCoord) {
    uvec2 enc;
    enc.x = texelFetch(screen_color_tex, screenCoord * ivec2(2,1)              , 0).r;
    enc.y = texelFetch(screen_color_tex, screenCoord * ivec2(2,1) + ivec2(1, 0), 0).r;
    
    return DecodeColor(enc);
}
/**********************************************************************/


/* DRAWBUFFERS:9 */

void main() {
    // float depth0 = texture(depthtex0, texcoord).x;
    // if (depth0 >= 1.0) { gl_FragData[0] = texture(colortex9, texcoord); return; }
    
    ivec2 coord = ivec2(gl_FragCoord.xy);
    
    // if (all(equal(ivec2(gl_FragCoord.xy), ivec2(1, 0)))) coord = ivec2(0, 0);
    
    vec4 color = vec4(ReadColor(ivec2(gl_FragCoord.xy)), 1.0);
    
    if (accum) color += texelFetch(colortex9, coord, 0);
    
    gl_FragData[0] = color;
}
