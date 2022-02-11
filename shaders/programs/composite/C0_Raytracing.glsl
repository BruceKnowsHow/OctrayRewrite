layout (local_size_x = 32, local_size_y = 32) in;
const vec2 workGroupsRender = vec2(1.0, 1.0);

uniform sampler2D depthtex0;
uniform sampler2D colortex6;
uniform sampler2D colortex3;
uniform sampler2D colortex7;
uniform sampler2D colortex12;
uniform sampler2D colortex14;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferProjection;
uniform vec3 cameraPosition;
uniform vec3 sunDirection;
uniform vec2 viewSize;
uniform float frameTimeCounter;
uniform float far;
uniform int frameCounter;
uniform bool accum;
uniform int hideGUI;

vec2 texcoord = gl_GlobalInvocationID.xy / viewSize;

#include "../../includes/debug.glsl"

#include "../../includes/Voxelization.glsl"
#include "../../BlockMappings.glsl"

uniform usampler2D atlas_tex;
uniform usampler2D atlas_tex_n;
uniform usampler2D atlas_tex_s;
ivec2 atlasSize = ivec2(textureSize(atlas_tex, 0).xy);

uniform usampler2D voxel_data_tex;
layout (r32ui) uniform uimage2D voxel_data_img;
layout (r32ui) uniform uimage2D colorimg3;

#define RAND_SEED uint(uint(gl_GlobalInvocationID.x * gl_GlobalInvocationID.y) + uint(viewSize.x * viewSize.y) * frameCounter)
#include "../../includes/Random.glsl"

vec3 GetWorldSpacePosition(vec2 coord, float depth) {
    vec4 pos = vec4(vec3(coord, depth) * 2.0 - 1.0, 1.0);
    pos = gbufferProjectionInverse * pos;
    pos = vec4(vec3(coord - (TAAHash() * pos.w)*0, depth) * 2.0 - 1.0, 1.0);
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

mat3 RecoverTangentMat(vec3 plane) {
    mat3 tbn;
    
    vec3 plane3 = abs(plane);
    
    tbn[0].z = -plane.x;
    tbn[0].y = 0.0;
    tbn[0].x = plane3.y + plane.z;
    
    tbn[1].x = 0.0;
    tbn[1].y = -plane3.x - plane3.z;
    tbn[1].z = plane3.y;
    
    tbn[2] = plane;
    
    if (plane.y < -0.5) tbn = mat3(1,0,0,0,0,-1,0,-1,0);
    
    return tbn;
}

#include "../../includes/Parallax.glsl"

void main() {
    float depth0 = texelFetch(depthtex0, ivec2(gl_GlobalInvocationID.xy), 0).x;
    
    vec3 worldPos = GetWorldSpacePosition(texcoord, depth0);
    vec3 worldDir = normalize(worldPos);
    vec3 voxelPos = WorldToVoxelSpace(worldPos);
    vec3 absorb = vec3(1.0);
    
    // ivec2 cobble_corner = ivec2(18, 7) * 16;
    // ivec2 cobble_corner = ivec2(18+9, 0) * 16;
    // ivec2 cobble_corner = ivec2(7, 1) * 512;
    // ivec2 cobble_corner = ivec2(13, 8) * 512;
    // // ivec2 cobble_corner = ivec2(21, 2) * 256;
    
    // // vec3 tangent_pos = vec3(mod(cameraPosition.xz, 512), mod(cameraPosition.y/2.0, 8.0) - 4.0);
    // vec3 tangent_pos = vec3(mod(cameraPosition.xz, 512), mod(cameraPosition.y/2.0, 512.0) - 256.0);
    // vec3 plane;
    // // ivec2 pCoord = Parallax(tangent_pos, worldDir.xzy, plane, cobble_corner, ivec2(16), 0);
    // // pCoord = Parallax(tangent_pos, normalize(vec3(1,2,3)), plane, cobble_corner, ivec2(16), 0);
    // ivec2 pCoord = Parallax(tangent_pos, worldDir.xzy, plane, cobble_corner, ivec2(512), 0);
    
    // vec3 diffuse2 = uintBitsToFloat(texelFetch(atlas_tex, pCoord, 0)).rgb;
    // // vec3 diffuse2 = uintBitsToFloat(texelFetch(atlas_tex, ivec2(gl_GlobalInvocationID.xy) * 16, 0)).rgb;
    // // show(diffuse2);
    // if (hideGUI == 0)
    //     show(diffuse2);
    // exitCoord(ivec2(gl_GlobalInvocationID.xy));
    // return;
    
    #define RASTER_ENGINE
    #ifdef RASTER_ENGINE
        if (depth0 >= 1.0) {
            exitCoord(ivec2(gl_GlobalInvocationID.xy));
            return;
        }
        
        vec4 gbufferEncode = texelFetch(colortex6, ivec2(gl_GlobalInvocationID.xy), 0).rgba;
        
        vec4 diffuse = unpackUnorm4x8(floatBitsToUint(gbufferEncode.r));
        diffuse.rgb = diffuse.rgb * 256.0 / 255.0;
        vec3 surfaceNormal = DecodeNormal(gbufferEncode.g);
        vec4 tex_s = unpackUnorm4x8(floatBitsToUint(gbufferEncode.b)) * 256.0 / 255.0;
        
        RayStruct curr;
        curr.voxelPos = texelFetch(colortex7, ivec2(gl_GlobalInvocationID.xy), 0).rgb;
        
        curr.worldDir   = worldDir;
        curr.absorb     = pow(diffuse.rgb, vec3(2.2));
        curr.info       = 1;
        curr.screenCoord = ivec2(gl_GlobalInvocationID.xy);
        
        mat3 tanMat = mat3(1,0,0,0,1,0,0,0,1);
        
        
        #ifdef PARALLAX
        vec4 parallax_data = texelFetch(colortex12, ivec2(gl_GlobalInvocationID.xy), 0);
        uint pData = floatBitsToUint(parallax_data.a);
        
        if (pData >= 8) {
            pData = pData % 8;
            
            vec3 plane = DecodePlane(pData);
            tanMat = RecoverTangentMat(plane);
            
            surfaceNormal = normalize(surfaceNormal*tanMat);
            curr.voxelPos = curr.voxelPos - plane * exp2(-9);
            curr.info |= pData << 24;
            curr.info |= PARALLAX_RAY_TYPE;
            
            curr.worldDir = normalize(curr.worldDir * tanMat);
            curr.extra.xyz = parallax_data.rgb;
        }
        #endif
        
        curr.absorb     = vec3(1.0);
        
        RayStruct specRay = curr;
        RayStruct  ambRay = curr;
        RayStruct  sunRay = curr;
        
        specRay.info |= SPECULAR_RAY_TYPE;
        ambRay.info  |= AMBIENT_RAY_TYPE;
        sunRay.info  |= SUNLIGHT_RAY_TYPE;
        
        DoPBR(diffuse, surfaceNormal, surfaceNormal, tex_s, curr.worldDir, specRay, ambRay, sunRay, tanMat);
        
        if (is_water(int(gbufferEncode.a))) {
            specRay.absorb = vec3(5.0);
            specRay.absorb *= 1-dot(specRay.worldDir, surfaceNormal);
            specRay.info = 0 | SPECULAR_RAY_TYPE;
            
            ambRay.absorb *= 0.0;
            sunRay.absorb *= 0.0;
        }
        
        if (is_iron_block(int(gbufferEncode.a))) {
            specRay.absorb *= 1/vec3(pow(0.65 / 5.0, 1.0/1.0));
        }
        
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
