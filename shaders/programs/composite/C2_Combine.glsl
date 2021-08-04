uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform sampler2D colortex8;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D depthtex0;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferModelView;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec2 viewSize;
uniform vec2 taaJitter;
uniform vec2 taaPrevJitter;
uniform float far;
uniform bool accum;

vec2 texcoord = (gl_FragCoord.xy + vec2(0.5)) / viewSize;

#include "../../includes/debug.glsl"
#include "../../includes/Voxelization.glsl"


// Atomic color read
uniform usampler2D voxel_data_tex;

vec3 DecodeColor(uvec2 enc) {
    uvec3 col;
    col.r = enc.r & ((1<<16)-1);
    col.g = enc.r >> 16;
    col.b = enc.g;
    
    vec3 color = vec3(col);
    return color / 1024.0;
}

vec3 ReadColor(ivec2 screenCoord) {
    ivec2 coord = ScreenToVoxelBuffer(screenCoord);
    
    uvec2 enc;
    
    enc.x = texelFetch(voxel_data_tex, coord              , 0).r;
    enc.y = texelFetch(voxel_data_tex, coord + ivec2(1, 0), 0).r;
    
    return DecodeColor(enc);
}
/**********************************************************************/


float LinearizeDepth(float depth) {
	return -1.0 / ((depth * 2.0 - 1.0) * gbufferProjectionInverse[2].w + gbufferProjectionInverse[3].w);
}

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

vec3 CalculateViewSpacePosition(vec3 screenPos) {
    vec4 pos = gbufferProjectionInverse * vec4(screenPos * 2.0 - 1.0, 1.0);
    
    return pos.xyz / pos.w;
}

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

/* RENDERTARGETS: 9,10,11 */

#define TAA
#ifdef TAA
#endif

void main() {
    ivec2 coord = ivec2(gl_FragCoord.xy);
    
    float depth = texelFetch(depthtex0, coord, 0).x;
    
    vec3 diffuse = ReadColor(ivec2(gl_FragCoord.xy));
    
    if (depth >= 1.0) {
        gl_FragData[0] = vec4(0.0, 0.0, 0.0, 1.0);
        
        exit();
        return;
    }
    
    vec3 gbufferEncode = texelFetch(colortex6, ivec2(gl_FragCoord.xy), 0).rgb;
    vec3 albedo = unpackUnorm4x8(floatBitsToUint(gbufferEncode.r)).rgb * 256.0 / 255.0;
    vec3 normal = DecodeNormal(gbufferEncode.g);
    
    albedo = pow(albedo, vec3(2.2));
    diffuse /= max(albedo, vec3(0.001));
    
    float diffuseLum = Luminance(diffuse);
    
    float linDepth = LinearizeDepth(depth);
    
    vec3 reproject = Reproject(vec3(texcoord - taaJitter * 0.5, depth));
    
    reproject.xy += taaPrevJitter * 0.5;
    
    float reprojDist = length(reproject.xy * viewSize - 0.5 - (gl_FragCoord.xy));
    
	vec3 temporalDiffuse = vec3(0.0);
	vec2 moments  = vec2(0.0);
    float history = 0.0;
    
    float temporalSumDifW = 0.0;
    
    vec2  prevCoord  = reproject.xy * viewSize - 1.0;
    vec2  fractCoord = fract(prevCoord);
    
    // Bilinear
    const ivec2 offsets[4] = {{0, 0}, {1, 0}, {0, 1}, {1, 1}};
    vec4 bilinWeight = vec4(
        (1.0 - fractCoord.x) * (1.0 - fractCoord.y),
        (fractCoord.x      ) * (1.0 - fractCoord.y),
        (1.0 - fractCoord.x) * (fractCoord.y      ),
        (fractCoord.x      ) * (fractCoord.y      )
    );
    
    if (accum && dot(vec4(1.0), textureGather(colortex8, texcoord, 2)) < 0.5 && unpackUnorm4x8(floatBitsToUint(gbufferEncode.r)).a < 0.5) {
        temporalDiffuse = texelFetch(colortex9 , ivec2(gl_FragCoord.xy), 0).rgb;
        moments = texelFetch(colortex10 , ivec2(gl_FragCoord.xy), 0).rg;
        history = texelFetch(colortex10 , ivec2(gl_FragCoord.xy), 0).b;
    } else {
    // Quad search for reprojected pixels
    for (int i = 0; i < 4; ++i) {
        ivec2 coord = ivec2(prevCoord) + offsets[i];
        
        vec4  prevData  = texelFetch(colortex8, coord, 0);
        float prevDepth = prevData.r;
        
        bool offscreen = any(greaterThan(coord, viewSize)) || any(lessThan(coord, ivec2(0)));
        bool isSky     = prevDepth >= 1.0;
        
        if (offscreen || isSky)
            continue;
        
        vec3  prevNormal   = DecodeNormal(prevData.g);
        float prevLinDepth = LinearizeDepth(prevDepth);
        
        float distDepth  = abs(LinearizeDepth(reproject.z) - prevLinDepth) * 4.0;
        float dotNormals = dot(normal, prevNormal);
        
        if (distDepth < 2.0 && dotNormals > 0.5) {
            float wDiff = bilinWeight[i] * dotNormals;
            
            temporalDiffuse += texelFetch(colortex9 , coord, 0).rgb * wDiff;
            moments         += texelFetch(colortex10, coord, 0).rg  * wDiff;
            history         += texelFetch(colortex10, coord, 0).b   * wDiff;
            
            temporalSumDifW += wDiff;
        }
    }
    
    if (temporalSumDifW > 0.001) {
        temporalDiffuse /= temporalSumDifW;
        moments  /= temporalSumDifW;
        history  /= temporalSumDifW;
    }
    
    }
    
    
    // Spatial moment filter
    vec2 spatialMoments = vec2(0.0);
    float spatialSumDifW = 0.0;
    int spatialDist = int(3.0 / clamp(history, 1.0, 3.0));
    
    for (int yy = -spatialDist; yy <= spatialDist; yy++) {
        for (int xx = -spatialDist; xx <= spatialDist; xx++) {
            ivec2 p = ivec2(gl_FragCoord.xy) + ivec2(xx, yy);
            
            vec3 gbufferEncodeP = texelFetch(colortex6, p, 0).rgb;
            
            vec3 albedoP = unpackUnorm4x8(floatBitsToUint(gbufferEncodeP.r)).rgb * 256.0 / 255.0;
            albedoP = pow(albedoP, vec3(2.2));
            
            vec3 diffuseP = ReadColor(p) / max(albedoP, vec3(0.001));
            
            float diffuseLumP = Luminance(diffuseP);
            vec3 normalP = DecodeNormal(gbufferEncodeP.g);
            float linDepthP = LinearizeDepth(texelFetch(depthtex0, p, 0).x);
            
            float distZ = abs(linDepth - linDepthP) * 16.0;
            
            if (distZ < 2.0) {
                float diffW = pow(max(0.0, dot(normal, normalP)), 16.0);
                
                spatialMoments += vec2(diffuseLumP, diffuseLumP * diffuseLumP) * diffW;
                spatialSumDifW += diffW;
            }
        }
    }
    
    spatialMoments /= spatialSumDifW;
    
    
    history += 1.0;
    
    moments = mix(moments, spatialMoments, 1.0 / history);
    diffuse = mix(temporalDiffuse, diffuse, 1.0 / history);
    
    gl_FragData[0] = vec4(diffuse, 0.0);
    gl_FragData[1] = vec4(moments, history, 0.0);
    gl_FragData[2] = vec4(diffuse, 0.0);
    
    exit();
}
