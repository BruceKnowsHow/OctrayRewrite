uniform sampler2D depthtex0;
uniform sampler2D colortex6;
uniform sampler2D colortex11;
uniform sampler2D colortex13;
uniform sampler2D colortex8;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferModelView;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec2 viewSize;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform float far;
uniform bool accum;

vec2 texcoord = gl_FragCoord.xy / viewSize;

#include "../../includes/debug.glsl"
#include "../../includes/Random.glsl"

#define ACCUM_GAMMA 2.4

vec3 Reproject(vec3 screenPos) {
    vec4 pos  = gbufferProjectionInverse * vec4(screenPos * 2.0 - 1.0, 1.0);
         pos /= pos.w;
         pos  = gbufferModelViewInverse * pos;
    
    pos.xyz += cameraPosition - previousCameraPosition;
    
    pos  = gbufferPreviousProjection * gbufferPreviousModelView * pos;
    pos /= pos.w;
    
    return pos.xyz * 0.5 + 0.5;
}

float Luminance(vec3 x) {
    return dot(x, vec3(0.2126, 0.7152, 0.0722));
}

#define TXAA_WEIGHT 0.05
#define TXAA_SHARPNESS 0.85

vec3 FastCatmulRom(sampler2D colorTex, vec2 texcoord, vec4 rtMetrics, float sharpenAmount) {
    vec2 position = rtMetrics.zw * texcoord;
    vec2 centerPosition = floor(position - 0.5) + 0.5;
    vec2 f = position - centerPosition;
    vec2 f2 = f * f;
    vec2 f3 = f * f2;

    float c = sharpenAmount;
    vec2 w0 =        -c  * f3 +  2.0 * c         * f2 - c * f;
    vec2 w1 =  (2.0 - c) * f3 - (3.0 - c)        * f2         + 1.0;
    vec2 w2 = -(2.0 - c) * f3 + (3.0 -  2.0 * c) * f2 + c * f;
    vec2 w3 =         c  * f3 -                c * f2;

    vec2 w12 = w1 + w2;
    vec2 tc12 = rtMetrics.xy * (centerPosition + w2 / w12);
    vec3 centerColor = pow(texture(colorTex, vec2(tc12.x, tc12.y)).rgb, vec3(ACCUM_GAMMA));

    vec2 tc0 = rtMetrics.xy * (centerPosition - 1.0);
    vec2 tc3 = rtMetrics.xy * (centerPosition + 2.0);
    vec4 color = vec4(pow(texture(colorTex, vec2(tc12.x, tc0.y )).rgb, vec3(ACCUM_GAMMA)), 1.0) * (w12.x *  w0.y) +
                 vec4(pow(texture(colorTex, vec2(tc0.x,  tc12.y)).rgb, vec3(ACCUM_GAMMA)), 1.0) * ( w0.x * w12.y) +
                 vec4(centerColor,                                 1.0) * (w12.x * w12.y) +
                 vec4(pow(texture(colorTex, vec2(tc3.x,  tc12.y)).rgb, vec3(ACCUM_GAMMA)), 1.0) * ( w3.x * w12.y) +
                 vec4(pow(texture(colorTex, vec2(tc12.x, tc3.y )).rgb, vec3(ACCUM_GAMMA)), 1.0) * (w12.x *  w3.y);
    
	return color.rgb/color.a;
}

#define REPROJECT
#ifdef REPROJECT
    const bool do_reproject = true;
#else
    const bool do_reproject = false;
#endif

vec3 calculateTAA(inout float history) {
    if (accum && dot(vec4(1.0), textureGather(colortex8, texcoord, 2)) < 0.5
    && unpackUnorm4x8(floatBitsToUint(texelFetch(colortex6, ivec2(gl_FragCoord.xy), 0).r)).a < 0.5) {
        
        vec4 curr = texture(colortex11, texcoord);
        vec4 prev = pow(texture(colortex13, texcoord), vec4(vec3(ACCUM_GAMMA), 1.0));
        
        history = prev.a + 1.0;
        return mix(prev.rgb, curr.rgb, 1.0 / history);
    }
    
    vec3 color = texture(colortex11, texcoord).rgb;
    
    if (!do_reproject)
        return color;
    
    float depth = texture(depthtex0, texcoord).x;
    
    vec2 reproject = Reproject(vec3(texcoord, depth)).xy;
    
    if (any(greaterThanEqual(abs(reproject - vec2(0.5)), vec2(0.5))))
        return color;
    
    vec2 velocity = reproject.xy - texcoord;
    
    vec3 prevColor = max(FastCatmulRom(colortex13, reproject, vec4(1.0/viewSize, viewSize), TXAA_SHARPNESS).rgb, 0.0);
    
    vec3 minCol = vec3( 10000000000.0);
    vec3 maxCol = vec3(-10000000000.0);
    
    for (int yy = -1; yy <= 1; ++yy) {
        for (int xx = -1; xx <= 1; ++xx) {
            vec3 col = texelFetch(colortex11, ivec2(gl_FragCoord.xy) + ivec2(xx, yy), 0).rgb;
            minCol = min(col, minCol);
            maxCol = max(col, maxCol);
        }
    }
    
    vec3 clampedHist = clamp(prevColor, minCol, maxCol);
    
    float amountClamped = distance(prevColor, clampedHist) / Luminance(prevColor);
    
    float velocityRejection = (0.1 + amountClamped) * clamp(length(velocity * viewSize), 0.0, 1.0);
    
    return mix(clampedHist, color, clamp(TXAA_WEIGHT + velocityRejection, 0.0, 1.0));
}

#define TAA

/* RENDERTARGETS:13,8 */

void main() {
    ivec2 coord = ivec2(gl_FragCoord.xy);
    float depth = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x;
    
    // vec3(0.2126, 0.7152, 0.0722)
    
    vec3 color;
    float history = 1.0;
    
    #ifdef TAA
        color = pow(calculateTAA(history), vec3(1.0 / ACCUM_GAMMA));
    #else
        color = pow(texelFetch(colortex11, coord, 0).rgb, vec3(1.0 / ACCUM_GAMMA));
    #endif
    
    vec3 gbufferEncode = texelFetch(colortex6, ivec2(gl_FragCoord.xy), 0).rgb;
    
    gl_FragData[0] = vec4(color, history);
    gl_FragData[1] = vec4(depth, gbufferEncode.g, unpackUnorm4x8(floatBitsToUint(gbufferEncode.r)).a, 0.0);
    
    exit();
}
