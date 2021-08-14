#include "../../BlockMappings.glsl"

/**********************************************************************/
#if defined vsh

attribute vec4 at_tangent;
attribute vec3 mc_Entity;
attribute vec2 mc_midTexCoord;

uniform sampler2D tex;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
ivec2 atlasSize = ivec2(textureSize(tex, 0).xy);
uniform vec2 taaJitter;

uniform vec2 viewSize;
uniform float far;
uniform float frameTimeCounter;
uniform int frameCounter;

#include "../../includes/Voxelization.glsl"
#include "../../includes/Random.glsl"

layout (r32ui) uniform uimage2D voxel_data_img;
layout (r32ui) uniform uimage2D colorimg3;


#define tanMat _tanMat
#define vertexColor _vertexColor
#define worldPos _worldPos
#define viewPos _viewPos
#define voxelPos _voxelPos
#define midTexcoord _midTexcoord
#define cornerTexcoord _cornerTexcoord
#define texcoord _texcoord
#define spriteSize _spriteSize
#define blockID _blockID

out mat3 tanMat;
out vec4 vertexColor;
out vec3 worldPos;
out vec3 viewPos;
out vec3 voxelPos;
flat out vec2 midTexcoord;
flat out vec2 cornerTexcoord;
out vec2 texcoord;
out vec2 spriteSize;
flat out int blockID;

// Returns the tangent to world space matrix
mat3 GetTangentMat() {
    // World-space normal matrix
    mat3 normal_mat = mat3(gbufferModelViewInverse) * gl_NormalMatrix;
    
    vec3 tangent  = normalize(normal_mat * at_tangent.xyz);
    vec3 normal   = normalize(normal_mat *  gl_Normal.xyz);
    vec3 binormal = normalize(cross(tangent, normal));
    
    return mat3(tangent, binormal, normal);
}

void main() {
    vertexColor    = gl_Color;
    texcoord       = gl_MultiTexCoord0.xy;
    tanMat         = GetTangentMat();
    blockID        = backport_id(int(mc_Entity.x)) % 256;
    midTexcoord    = mc_midTexCoord;
    cornerTexcoord = mc_midTexCoord.xy - abs(mc_midTexCoord.xy - texcoord);
    vec2 texDirection = sign(texcoord - mc_midTexCoord)*vec2(1,sign(at_tangent.w));
    worldPos    = (gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 triCentroid = worldPos.xyz - (tanMat * vec3(texDirection,0.5)) - tanMat[2] / 32.0;
    triCentroid = mix(worldPos, triCentroid, 0.5);
    voxelPos    = WorldToVoxelSpace(worldPos) + tanMat[2] * exp2(-11);
    viewPos     = (gbufferModelView * vec4(worldPos, 1.0)).xyz;
    
    gl_Position = gbufferProjection * vec4(viewPos, 1.0);
    gl_Position.xy += TAAHash() * gl_Position.w;
    
    viewPos = (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
    
    if (!is_voxelized(blockID))
        return;
    
    if (((blockID == 3
      || blockID == 4
      || (blockID >=  6 && blockID <= 12)) && abs(tanMat[2].y) < 0.9)
      || ((blockID >= 14 && blockID <= 21) && abs(tanMat[2].y) < 0.9)
    )
        return;
    
    if (blockID == 5 && (abs(tanMat[2]).y < 0.9 || abs(fract(WorldToVoxelSpace(triCentroid).y) - 0.5) > 0.1 ))
        return;
    
    vec2 spriteSize = abs(midTexcoord - texcoord) * 2.0 * atlasSize;
    
    ivec3 voxelPos = ivec3(WorldToVoxelSpace(triCentroid));
    
    // Store into chunk bitmap so that this chunk will be allocated next frame.
    imageStore(colorimg3, old_get_sparse_chunk_coord(voxelPos), uvec4(1));
    
    // Allocate extra chunks along the movement vector.
    // This prevents flickering when stepping over chunk borders.
    vec2 chunkGrow = 16.0 * sign(previousCameraPosition.xz - cameraPosition.xz);
    imageStore(colorimg3, old_get_sparse_chunk_coord(voxelPos + ivec3(chunkGrow.x, 0, 0)), uvec4(1));
    imageStore(colorimg3, old_get_sparse_chunk_coord(voxelPos + ivec3(0, 0, chunkGrow.y)), uvec4(1));
    
    uint chunkAddr = imageLoad(colorimg3, old_get_sparse_chunk_coord(voxelPos) + SPARSE0).r;
    bool allocFlag = chunkAddr != 0;
    if (!allocFlag)
        return;
    
    // Store all of its data into the sparse texture
    uint packed_tex_coord = packUnorm2x16(cornerTexcoord);
    
    vec2 hueSat           = RGBtoHSV(vertexColor.rgb).rg;
    uint packedVoxelData = 0;
    packedVoxelData |= blockID;
    packedVoxelData |= int(clamp(hueSat.r, 0.0, 1.0) * 255.0) << VBM_hue_start;
    packedVoxelData |= int(clamp(hueSat.g, 0.0, 1.0) * 255.0) << VBM_sat_start;
    packedVoxelData |= int(round(log2(spriteSize.x))) << VBM_sprite_size_start;
    if (is_sub_voxel(blockID)) packedVoxelData |= VBM_AABB_bit;
    
    ivec2 chunkCoord = get_sparse_voxel_coord(chunkAddr, voxelPos, 0);
    
    imageAtomicMax(voxel_data_img, chunkCoord, packed_tex_coord);
    imageAtomicMax(voxel_data_img, chunkCoord + DATA0, packedVoxelData);
    
    for (int lod = 1; lod <= 4; ++lod) {
        chunkCoord = get_sparse_voxel_coord(chunkAddr, voxelPos, lod);
        imageStore(voxel_data_img, chunkCoord + DATA0, uvec4(1));
    }
}

#endif
/**********************************************************************/

/**********************************************************************/
#if defined fsh

uniform sampler2D tex;
uniform sampler2D normals;
uniform sampler2D specular;

ivec2 atlasSize = ivec2(textureSize(tex, 0).xy);

in mat3 _tanMat;
in vec4 _vertexColor;
in vec3 _worldPos;
in vec3 _viewPos;
in vec3 _voxelPos;
in vec2 _texcoord;
flat in vec2 _cornerTexcoord;
flat in vec2 _spriteSize;
flat in int _blockID;

#include "../../includes/debug.glsl"

float EncodeNormal(vec3 normal) {
    const float bits = 11.0;
    
	normal    = clamp(normal, -1.0, 1.0);
	normal.xy = vec2(atan(normal.x, normal.z), acos(normal.y)) / 3.14159;
	normal.x += 1.0;
	normal.xy = round(normal.xy * exp2(bits));
	
	return normal.x + normal.y * exp2(bits + 2.0);
}

#include "../../includes/Parallax.glsl"

/* RENDERTARGETS:6,7 */

void main() {
    vec3 plane = vec3(0,0,1);
    ivec2 corner = ivec2(_cornerTexcoord*atlasSize);
    float LOD = max(0.0, textureQueryLod(tex, _texcoord).y)*0;
    vec3 tangent_pos = vec3((_texcoord - _cornerTexcoord)*atlasSize, 1.0);
    vec3 tangent_ray = normalize(_viewPos*_tanMat);
    
    ivec2 spriteSize = ivec2(_spriteSize);
    
    ivec2 pCoord = Parallax(tangent_pos, tangent_ray, plane, corner, spriteSize, int(LOD));
    
    vec2 tCoord = _texcoord;
    // vec2 tCoord = vec2(pCoord)/atlasSize;
    
    vec4 diffuse = textureLod(tex, tCoord, LOD);
    
    if (diffuse.a < 0.1) {
        discard;
    }
    
    diffuse.rgb *= pow(_vertexColor.rgb, vec3(1.0 / 2.2));
    
    vec4 tex_n = texture(normals, tCoord);
    
    vec3 normal;
    normal.xy = tex_n.xy * 2.0 - 1.0;
    normal.z = sqrt(max(1.0 - dot(normal.xy, normal.xy), 0.0));
    normal = normalize(normal);
    
    vec3 surfaceNormal = _tanMat * normal;
    
    #if (defined gbuffers_entities) || (defined gbuffers_hand)
        diffuse.a = 1.0;
    #else
        diffuse.a = 0.0;
    #endif
    
    gl_FragData[0] = vec4(uintBitsToFloat(packUnorm4x8(diffuse * 255.0 / 256.0)), EncodeNormal(surfaceNormal), uintBitsToFloat(packUnorm4x8(texture(specular, tCoord) * 255.0 / 256.0)), _blockID);
    gl_FragData[1].rgb = _voxelPos + _tanMat[2] * exp2(-11);
    
    // exit();
}

#endif
/**********************************************************************/