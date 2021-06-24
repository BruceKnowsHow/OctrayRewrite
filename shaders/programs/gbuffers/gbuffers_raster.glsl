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
uniform ivec2 atlasSize;
uniform vec2 taaJitter;

uniform vec2 viewSize;
uniform float far;
uniform float frameTimeCounter;

#include "../../includes/Voxelization.glsl"

layout (r32ui) uniform uimage2D voxel_data_img;


out mat3 tanMat;
out vec4 vertexColor;
out vec3 worldPos;
out vec3 viewPos;
out vec3 voxelPos;
flat out vec2 midTexcoord;
flat out vec2 cornerTexcoord;
out vec2 texcoord;
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
    
    worldPos    = (gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex).xyz;
    voxelPos    = WorldToVoxelSpace(worldPos) + tanMat[2] * exp2(-11);
    viewPos     = (gbufferModelView * vec4(worldPos, 1.0)).xyz;
    
    gl_Position = gbufferProjection * vec4(viewPos, 1.0);
    gl_Position.xy += taaJitter * gl_Position.w;
    
    viewPos = (mat3(gbufferModelViewInverse) * (gl_ModelViewMatrix * gl_Vertex).xyz);
    
    vec2 texDirection = sign(texcoord - mc_midTexCoord)*vec2(1,sign(at_tangent.w));
    vec3 triCentroid = worldPos.xyz - (tanMat * vec3(texDirection,0.5));
    ivec3 voxelPos = ivec3(WorldToVoxelSpace(triCentroid));
    ivec2 CC = get_sparse_chunk_coord(voxelPos);
    
    if ((imageLoad(voxel_data_img, CC).r & chunk_locked_bit) == 0) {
        if ((imageAtomicOr(voxel_data_img, CC, chunk_locked_bit) & chunk_locked_bit) == 0) {
            imageAtomicOr(voxel_data_img, CC, imageAtomicAdd(voxel_data_img, chunk_alloc_counter, 1));
        }
    }
}

#endif
/**********************************************************************/

/**********************************************************************/
#if defined gsh

layout (triangles) in;
layout (triangle_strip, max_vertices = 3) out;

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform ivec2 atlasSize;
uniform vec2 viewSize;
uniform float far;

#include "../../includes/Voxelization.glsl"

layout (r32ui) uniform uimage2D voxel_data_img;

in mat3 tanMat[];
in vec4 vertexColor[];
in vec3 worldPos[];
in vec3 viewPos[];
in vec3 voxelPos[];
flat in vec2 midTexcoord[];
flat in vec2 cornerTexcoord[];
in vec2 texcoord[];
flat in int blockID[];

out mat3 _tanMat;
out vec4 _vertexColor;
out vec3 _worldPos;
out vec3 _viewPos;
out vec3 _voxelPos;
out vec2 _texcoord;
flat out vec2 _cornerTexcoord;
flat out vec2 _spriteSize;

void main() {
    _spriteSize = abs(midTexcoord[0] - texcoord[0]) * 2.0 * atlasSize;
    
    for (int i = 0; i < 3; ++i) {
        gl_Position = gl_in[i].gl_Position;
        _tanMat = tanMat[i];
        _vertexColor = vertexColor[i];
        _worldPos = worldPos[i];
        _viewPos  = viewPos[i];
        _voxelPos = voxelPos[i];
        _texcoord = texcoord[i];
        _cornerTexcoord = cornerTexcoord[i];
        EmitVertex();
    }
    
    if (!is_voxelized(blockID[0]))
        return;
    
    vec3 triCentroid = (worldPos[0] + worldPos[1] + worldPos[2]) / 3.0 - tanMat[0][2] / 1024.0;
    
    
    // Subvoxel culling section.
    // Lots of subvoxel blocks have certain faces with poorly positioned texture coordinates.
    // These blocks usually have at least one "good face".
    // This section selects the bad faces that steal priority from the good faces, and culls them by doing return.
    if (abs(dot(worldPos[0] - worldPos[1], worldPos[2] - worldPos[1])) < 0.001) return;
    
    if (((blockID[0] == 3
      || blockID[0] == 4
      || (blockID[0] >=  6 && blockID[0] <= 12)) && abs(tanMat[0][2].y) < 0.9)
      || ((blockID[0] >= 14 && blockID[0] <= 21) && abs(tanMat[0][2].y) < 0.9)
    )
        return;
    
    if (blockID[0] == 5 && (abs(tanMat[0][2]).y < 0.9 || abs(fract(WorldToVoxelSpace(triCentroid).y) - 0.5) > 0.1 )) return;
    
    ivec3 voxelPos = ivec3(WorldToVoxelSpace(triCentroid));
    
    // Store all of its data into the sparse texture
    uint packed_tex_coord = packUnorm2x16(cornerTexcoord[0]);
    
    vec2 hueSat           = RGBtoHSV(vertexColor[0].rgb).rg;
    uint packedVoxelData = 0;
    packedVoxelData |= blockID[0];
    packedVoxelData |= int(clamp(hueSat.r, 0.0, 1.0) * 255.0) << VMB_hue_start;
    packedVoxelData |= int(clamp(hueSat.g, 0.0, 1.0) * 255.0) << VMB_sat_start;
    packedVoxelData |= int(round(log2(_spriteSize.x))) << VMB_sprite_size_start;
    if (is_sub_voxel(blockID[0])) packedVoxelData |= VBM_AABB_bit;
    
    uint chunkAddr = imageLoad(voxel_data_img, get_sparse_chunk_coord(voxelPos)).r & chunk_addr_mask;
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

uniform ivec2 atlasSize;

in mat3 _tanMat;
in vec4 _vertexColor;
in vec3 _worldPos;
in vec3 _viewPos;
in vec3 _voxelPos;
in vec2 _texcoord;
flat in vec2 _cornerTexcoord;
flat in vec2 _spriteSize;

#include "../../includes/Debug.glsl"

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
    
    gl_FragData[0].rgb = vec3(uintBitsToFloat(packUnorm4x8(diffuse * 255.0 / 256.0)), EncodeNormal(surfaceNormal), uintBitsToFloat(packUnorm4x8(texture(specular, tCoord) * 255.0 / 256.0)));
    gl_FragData[1].rgb = _voxelPos + _tanMat[2] * exp2(-11);
    
    // exit();
}

#endif
/**********************************************************************/