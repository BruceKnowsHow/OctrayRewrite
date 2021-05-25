uniform sampler2D colortex9;
uniform sampler2D colortex8;
uniform sampler2D colortex5;
uniform sampler2D depthtex0;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferModelView;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec2 viewSize;
uniform float far;
uniform bool accum;

vec2 texcoord = gl_FragCoord.xy / viewSize;

#include "../../includes/Debug.glsl"
#include "../../includes/Voxelization.glsl"


// Atomic color read
uniform usampler2D voxel_data_tex;

vec3 DecodeColor(uvec2 enc) {
    uvec3 col;
    col.r = enc.r & ((1<<16)-1);
    col.g = enc.r >> 16;
    col.b = enc.g;
    
    vec3 color = vec3(col);
    return color / 256.0;
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
    vec4 pos  = gbufferModelViewInverse * gbufferProjectionInverse * vec4(screenPos * 2.0 - 1.0, 1.0);
         pos /= pos.w;
    
    pos.xyz += cameraPosition - previousCameraPosition;
    
    pos  = gbufferPreviousProjection * gbufferPreviousModelView * pos;
    pos /= pos.w;
    
    return pos.xyz * 0.5 + 0.5;
}

/* DRAWBUFFERS:9 */

void main() {
    ivec2 coord = ivec2(gl_FragCoord.xy);
    
    float depth = texelFetch(depthtex0, coord, 0).x;
    
    vec4 color = vec4(ReadColor(ivec2(gl_FragCoord.xy)), 1.0);
    
    if (depth >= 1.0) {
        gl_FragData[0] = color;
        exit();
        return;
    }
    
    #define PT_ACCUMULATION
    #define PT_REPROJECTION
    
    #ifdef PT_ACCUMULATION
        
        #ifdef PT_REPROJECTION
            
            vec3 prevCoord = Reproject(vec3(texcoord, depth));
            float prevDepth = texelFetch(colortex8, ivec2(prevCoord.xy * viewSize), 0).x;
            
            float currLinDepth = LinearizeDepth(depth);
            float prevLinDepth = LinearizeDepth(prevDepth);
            
            float reprojWeight = 1.0 - abs((currLinDepth - prevLinDepth) / currLinDepth) * 10.0;
            
            if (reprojWeight > 0.0 && prevDepth < 1.0) {
                vec4 color_prev = textureLod(colortex9, prevCoord.xy, 0);
                
                color += color_prev * reprojWeight;
            }
            
        #else
        
            if (accum) color += texelFetch(colortex9, coord, 0);
            
        #endif
        
    #endif
    
    gl_FragData[0] = color;
    
    exit();
}
