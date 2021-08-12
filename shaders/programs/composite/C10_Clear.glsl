uniform sampler2D depthtex0;
uniform sampler2D colortex6;
uniform sampler2D colortex11;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform vec3 cameraPosition;
uniform vec2 viewSize;
uniform float frameTimeCounter;
uniform float far;
uniform bool accum;

vec2 texcoord = gl_FragCoord.xy / viewSize;

#include "../../includes/debug.glsl"

uniform sampler2D noisetex;
uniform vec3 sunDirection;

#define sky_tex colortex15
uniform usampler2D sky_tex;
#include "../../includes/Sky.glsl"

vec3 GetWorldSpacePosition(vec2 coord, float depth) {
    vec4 pos = vec4(vec3(coord, depth) * 2.0 - 1.0, 1.0);
    pos = gbufferProjectionInverse * pos;
    pos /= pos.w;
    pos.xyz = mat3(gbufferModelViewInverse) * pos.xyz;
    
    return pos.xyz;
}

/* RENDERTARGETS:11 */

void main() {
    ivec2 coord = ivec2(gl_FragCoord.xy);
    
    float depth = texelFetch(depthtex0, coord, 0).x;
    
    vec3 worldPos = GetWorldSpacePosition(texcoord, depth);
    
    vec3 worldDir = normalize(worldPos);
    vec3 absorb = vec3(1.0);
    
    vec3 skyColor = ComputeTotalSky(vec3(0.0), worldDir, absorb, true) * SKY_PRIMARY_BRIGHTNESS + GetFogColor(worldDir);
    
    if (depth >= 1.0) {
        gl_FragData[0] = vec4(skyColor, 0.0);
        gl_FragData[1] = vec4(0.0);
        exit();
        return;
    }
    
    vec4 gbufferEncode = texelFetch(colortex6, ivec2(gl_FragCoord.xy), 0);
    vec3 albedo = unpackUnorm4x8(floatBitsToUint(gbufferEncode.r)).rgb * 256.0 / 255.0;
    albedo = pow(albedo, vec3(2.2));
    
    gl_FragData[0].rgb = texelFetch(colortex11, coord, 0).rgb * albedo;
    
    if ((int(gbufferEncode.a) & 64) > 0 && int(gbufferEncode.a) != 250) {
        gl_FragData[0].rgb += albedo;
    }
    
    
    float fog_amount = clamp(length(worldPos) / max(16.0 * 16.0, far), 0.0, 1.0);
    
    if (is_nether)
        gl_FragData[0].rgb = mix(gl_FragData[0].rgb, GetFogColor(worldDir), fog_amount);
    else
        gl_FragData[0].rgb += GetFogColor(worldDir) * fog_amount;
    
    
    exit();
}
