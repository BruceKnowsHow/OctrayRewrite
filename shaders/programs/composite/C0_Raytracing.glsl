layout (local_size_x = 32, local_size_y = 32) in;
const vec2 workGroupsRender = vec2(1.0, 1.0);

uniform sampler2D depthtex0;
uniform sampler2D colortex6;
uniform sampler2D colortex7;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferProjection;
uniform vec3 cameraPosition;
uniform vec3 sunDirection;
uniform vec2 viewSize;
uniform float frameTimeCounter;
uniform float far;
uniform int frameCounter;

vec2 texcoord = gl_GlobalInvocationID.xy / viewSize;

#include "../../includes/debug.glsl"

#include "../../includes/Voxelization.glsl"
#include "../../BlockMappings.glsl"

uniform usampler2D voxel_data_tex;
layout (r32ui) uniform uimage2D voxel_data_img;
layout (r32ui) uniform uimage2D colorimg3;
uniform  sampler2D atlas_tex      ;
uniform  sampler2D atlas_tex_n    ;
uniform  sampler2D atlas_tex_s    ;

#define RAND_SEED uint(uint(gl_GlobalInvocationID.x * gl_GlobalInvocationID.y) + uint(viewSize.x * viewSize.y) * frameCounter)
#include "../../includes/Random.glsl"

vec3 GetWorldSpacePosition(vec2 coord, float depth) {
    vec4 pos = vec4(vec3(coord, depth) * 2.0 - 1.0, 1.0);
    pos = gbufferProjectionInverse * pos;
    pos /= pos.w;
    pos.xyz = (gbufferModelViewInverse * pos).xyz;
    
    return pos.xyz;
}

#include "../../includes/Raybuffer.glsl"
#include "../../includes/Pathtracing.glsl"

/**********************************************************************/

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

void main() {
    float depth0 = texelFetch(depthtex0, ivec2(gl_GlobalInvocationID.xy), 0).x;
    
    vec3 worldPos = GetWorldSpacePosition(texcoord, depth0);
    vec3 worldDir = normalize(worldPos);
    vec3 voxelPos = WorldToVoxelSpace(worldPos);
    
    vec3 absorb = vec3(1.0);
    
    #define RASTER_ENGINE
    #ifdef RASTER_ENGINE
        if (depth0 >= 1.0) {
            exitCoord(ivec2(gl_GlobalInvocationID.xy));
            return;
        }
        
        vec3 gbufferEncode = texelFetch(colortex6, ivec2(gl_GlobalInvocationID.xy), 0).rgb;
        
        vec4 diffuse = unpackUnorm4x8(floatBitsToUint(gbufferEncode.r)) * 256.0 / 255.0;
        vec3 surfaceNormal = DecodeNormal(gbufferEncode.g);
        vec4 tex_s = unpackUnorm4x8(floatBitsToUint(gbufferEncode.b)) * 256.0 / 255.0;
        
        RayStruct curr;
        curr.voxelPos = texelFetch(colortex7, ivec2(gl_GlobalInvocationID.xy), 0).rgb;
        
        curr.worldDir   = worldDir;
        curr.absorb     = pow(diffuse.rgb, vec3(2.2));
        curr.info       = 1;
        curr.screenCoord = ivec2(gl_GlobalInvocationID.xy);
        
        RayStruct specRay = curr;
        RayStruct  ambRay = curr;
        RayStruct  sunRay = curr;
        
        specRay.info |= SPECULAR_RAY_TYPE;
        ambRay.info  |= AMBIENT_RAY_TYPE;
        sunRay.info  |= SUNLIGHT_RAY_TYPE;
        
        DoPBR(diffuse, surfaceNormal, surfaceNormal, tex_s, curr.worldDir, specRay, ambRay, sunRay);
        
        uint i;
        WriteRay(i, specRay);
        WriteRay(i, ambRay);
        WriteRay(i, sunRay);
    #else
        RayStruct curr;
        curr.voxelPos = WorldToVoxelSpace(vec3(0.0));
        curr.worldDir = worldDir;
        curr.absorb    = vec3(1.0);
        curr.info      = 0 | PRIMARY_RAY_TYPE;
        curr.screenCoord = ivec2(gl_GlobalInvocationID.xy);
        
        uint i;
        WriteRay(i, curr);
    #endif
    
    exitCoord(ivec2(gl_GlobalInvocationID.xy));
}
