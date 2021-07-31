#define ANY_ATROUS_FILTER

#define ATROUS_FILTER_PASSES_1
#define ATROUS_FILTER_PASSES_2
#define ATROUS_FILTER_PASSES_3
#define ATROUS_FILTER_PASSES_4
#define ATROUS_FILTER_PASSES_5

#ifdef ANY_ATROUS_FILTER
#endif
#ifdef ATROUS_FILTER_PASSES_1
#endif
#ifdef ATROUS_FILTER_PASSES_2
#endif
#ifdef ATROUS_FILTER_PASSES_3
#endif
#ifdef ATROUS_FILTER_PASSES_4
#endif
#ifdef ATROUS_FILTER_PASSES_5
#endif

uniform sampler2D colortex6;
uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D depthtex0;

#include "../../includes/debug.glsl"

uniform mat4 gbufferProjectionInverse;
uniform vec2 viewSize;

/* RENDERTARGETS:11,9 */

vec3 DecodeNormal(float enc) {
    const float bits = 11.0;
    
	vec4 normal;
	
	normal.y    = exp2(bits + 2.0) * floor(enc / exp2(bits + 2.0));
	normal.x    = enc - normal.y;
	normal.xy  /= exp2(vec2(bits, bits * 2.0 + 2.0));
	normal.x   -= 1.0;
	normal.xy  *= 3.14159;
	normal.xwzy = vec4(sin(normal.xy), cos(normal.xy));
	normal.xz  *= normal.w;
	
	return normal.xyz;
}

float LinearizeDepth(float depth) {
	return -1.0 / ((depth * 2.0 - 1.0) * gbufferProjectionInverse[2].w + gbufferProjectionInverse[3].w);
}

float Luminance(vec3 x) {
    return dot(x, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
    float depth = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x;
    
    if (depth >= 1.0) {
        gl_FragData[0] = vec4(0.0, 0.0, 0.0, 1.0);
		return;
	}
    
    vec3 diffuse = texelFetch(colortex11, ivec2(gl_FragCoord.xy), 0).rgb;
    
    vec3 gbufferEncode = texelFetch(colortex6, ivec2(gl_FragCoord.xy), 0).rgb;
    vec3 normal = DecodeNormal(gbufferEncode.g);
    float linDepth = LinearizeDepth(depth);
    
    float diffuseLum = Luminance(diffuse);
    
    vec2 moments = texelFetch(colortex10, ivec2(gl_FragCoord.xy), 0).rg;
    float diffuseHistory = texelFetch(colortex10, ivec2(gl_FragCoord.xy), 0).b;
    
    
    float variance = max(1e-10, moments.y - moments.x * moments.x);
    
    float diffuseSigma = diffuseHistory / (2.0 * variance);
    
    if (diffuseLum <= sqrt(moments.x))
        diffuseSigma /= abs(moments.x - diffuseLum + 1.0);
    
    float diffuseNormalWeight = clamp(diffuseHistory / 8.0, 0.0, 1.0) * 128.0;
    
    const int stepSize = 1 << ATROUS_INDEX;
    
    vec3 diffuseSum = diffuse;
    vec2 momentsSum = moments;
    
    float diffuseSumW = 1.0;
    
    const vec3 kernel = vec3(6.0, 4.0, 1.0);
    
    float v = max(1.0, diffuseHistory - 32.0);
    
    const int r = min(1, int(2.0 / log(v)));
    for (int yy = -r; yy <= r; yy++) {
        for (int xx = -r; xx <= r; xx++) {
            ivec2 p = ivec2(gl_FragCoord.xy) + ivec2(xx, yy) * stepSize;
            bool outside = any(lessThan(p, ivec2(0))) || any(greaterThan(p, ivec2(viewSize)));
            
            float depthP = texelFetch(depthtex0, p, 0).x;
            
            if (xx == 0 && yy == 0 || outside || depthP >= 1.0)
                continue;
            
            vec3  gbufferEncodeP = texelFetch(colortex6, p, 0).rgb;
            vec3  diffuseP       = texelFetch(colortex11, p, 0).rgb;
            vec2  momentsP       = texelFetch(colortex10, p, 0).rg;
            vec3  normalP        = DecodeNormal(gbufferEncodeP.g);
            float linDepthP      = LinearizeDepth(depthP);
            
            float diffuseLumP = Luminance(diffuseP);
            float diffuseLumDist = abs(moments.x - diffuseLumP);
            
            float distL = diffuseLumDist * diffuseLumDist * diffuseSigma;
            float distZ = abs(linDepth - linDepthP) * 16.0 / float(stepSize);
            float NdotN = max(0.0, dot(normal, normalP));
            
            float weight  = exp(0.0 - distZ - distL);
                  weight *= kernel[abs(xx)] * kernel[abs(yy)];
            
            float diffuseW = weight * pow(NdotN, diffuseNormalWeight);
            diffuseSum   += diffuseP * diffuseW;
            momentsSum   += momentsP * diffuseW;
            diffuseSumW  += diffuseW;
        }
    }
    
    diffuseSum /= diffuseSumW;
    momentsSum /= diffuseSumW;
    
    diffuse = mix(diffuse, diffuseSum, 1.0 / diffuseHistory);
    
    gl_FragData[0] = vec4(diffuseSum, 0.0);
    gl_FragData[1] = vec4(diffuse, 0);
    
    exit();
}