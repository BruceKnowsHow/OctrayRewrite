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
uniform float far;
uniform float frameTimeCounter;

#include "../../includes/Voxelization.glsl"

out mat3 tangent_mat;
out vec4 vertex_color;
out vec3 world_pos;
flat out vec2 mid_texcoord;
out vec2 texcoord;
flat out int block_id;

// Returns the tangent to world space matrix
mat3 get_tangent_mat() {
    // World-space normal matrix
    mat3 normal_mat = mat3(gbufferModelViewInverse) * gl_NormalMatrix;
    
    vec3 tangent  = normalize(normal_mat * at_tangent.xyz);
    vec3 normal   = normalize(normal_mat *  gl_Normal.xyz);
    vec3 binormal = normalize(cross(tangent, normal));
    
    return mat3(tangent, binormal, normal);
}

void main() {
    vertex_color = gl_Color;
    texcoord     = gl_MultiTexCoord0.xy;
    tangent_mat  = get_tangent_mat();
    block_id     = backport_id(int(mc_Entity.x)) % 256;
    mid_texcoord = mc_midTexCoord;
    
    world_pos    = (gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex).xyz;
    
    gl_Position  = gbufferProjection * gbufferModelView * vec4(world_pos, 1.0);
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
uniform float far;

#include "../../includes/Voxelization.glsl"

layout (r32ui) uniform uimage2D sparse_data_img0;
layout (r32ui) uniform uimage2D voxel_data_img0;

in mat3 tangent_mat[];
in vec4 vertex_color[];
in vec3 world_pos[];
flat in vec2 mid_texcoord[];
in vec2 texcoord[];
flat in int block_id[];

out mat3 _tangent_mat;
out vec4 _vertex_color;
out vec3 _world_pos;
out vec2 _texcoord;

vec3 rgb_to_hsv(vec3 c) {
    const vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
    const vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main() {
    for (int i = 0; i < 3; ++i) {
        gl_Position = gl_in[i].gl_Position;
        _tangent_mat = tangent_mat[i];
        _vertex_color = vertex_color[i];
        _world_pos = world_pos[i];
        _texcoord = texcoord[i];
        EmitVertex();
    }
    
    if (!is_voxelized(block_id[0]))
        return;
    
    vec3 tri_centroid = (world_pos[0] + world_pos[1] + world_pos[2]) / 3.0 - tangent_mat[0][2] / 4096.0;
    
    
    // Subvoxel culling section.
    // Lots of subvoxel blocks have certain faces with poorly positioned texture coordinates.
    // These blocks usually have at least one "good face".
    // This section selects the bad faces that steal priority from the good faces, and culls them by doing return.
    if (abs(dot(world_pos[0] - world_pos[1], world_pos[2] - world_pos[1])) < 0.001) return;
    
    if (((block_id[0] == 3
      || block_id[0] == 4
      || (block_id[0] >=  6 && block_id[0] <= 12)) && abs(tangent_mat[0][2].y) < 0.9)
      || ((block_id[0] >= 14 && block_id[0] <= 21) && abs(tangent_mat[0][2].y) < 0.9)
    )
        return;
    
    if (block_id[0] == 5 && (abs(tangent_mat[0][2]).y < 0.9 || abs(fract(WorldToVoxelSpace(tri_centroid).y) - 0.5) > 0.1 )) return;
    
    ivec3 voxel_pos = ivec3(WorldToVoxelSpace(tri_centroid));
    
    // Store into chunk bitmap so that this chunk will be allocated next frame.
    imageStore(sparse_data_img0, get_sparse_chunk_coord(voxel_pos), uvec4(1));
    
    // Allocate extra chunks along the movement vector.
    // This prevents flickering when stepping over chunk borders.
    vec2 chunk_grow = 16.0 * sign(previousCameraPosition.xz - cameraPosition.xz);
    imageStore(sparse_data_img0, get_sparse_chunk_coord(voxel_pos + ivec3(chunk_grow.x, 0, 0)), uvec4(1));
    imageStore(sparse_data_img0, get_sparse_chunk_coord(voxel_pos + ivec3(0, 0, chunk_grow.y)), uvec4(1));
    
    // If this chunk was allocated in the previous frame
    bool alloc_flag = imageLoad(sparse_data_img0, get_sparse_chunk_coord(voxel_pos) + SPARSE0).r != 0;
    if (!alloc_flag)
        return;
    
    // Store all of its data into the sparse texture
    vec2 corner_texcoord   = mid_texcoord[0] - abs(mid_texcoord[0] - texcoord[0]);
    uint packed_tex_coord  = packUnorm2x16(corner_texcoord);
    
    vec2 hue_sat           = rgb_to_hsv(vertex_color[0].rgb).rg;
    uint packed_voxel_data = 0;
    packed_voxel_data |= block_id[0];
    packed_voxel_data |= int(clamp(hue_sat.r, 0.0, 1.0) * 255.0) << VMB_hue_start;
    packed_voxel_data |= int(clamp(hue_sat.g, 0.0, 1.0) * 255.0) << VMB_sat_start;
    if (is_sub_voxel(block_id[0])) packed_voxel_data |= VBM_AABB_bit;
    
    
    uint chunk_addr = imageLoad(sparse_data_img0, get_sparse_chunk_coord(voxel_pos) + SPARSE0).r;
    ivec2 chunk_coord = get_sparse_voxel_coord(chunk_addr, voxel_pos, 0);
    
    imageAtomicMax(voxel_data_img0, chunk_coord, packed_tex_coord);
    imageAtomicMax(voxel_data_img0, chunk_coord + DATA0, packed_voxel_data);
    
    for (int lod = 1; lod <= 7; ++lod) {
        chunk_coord = get_sparse_voxel_coord(chunk_addr, voxel_pos, lod);
        imageStore(voxel_data_img0, chunk_coord + DATA0, uvec4(1));
    }
}

#endif
/**********************************************************************/

/**********************************************************************/
#if defined fsh

uniform sampler2D tex;

in mat3 _tangent_mat;
in vec4 _vertex_color;
in vec3 _world_pos;
in vec2 _texcoord;

/* DRAWBUFFERS:89 */

void main() {
    vec4 diffuse = texture(tex, _texcoord);
    
    if (diffuse.a < 0.1) {
        discard;
    }
    
    diffuse.rgb *= _vertex_color.rgb * _vertex_color.a;
    
    gl_FragData[0] = diffuse;
    gl_FragData[1] = vec4(_tangent_mat[2], 0.0);
}

#endif
/**********************************************************************/