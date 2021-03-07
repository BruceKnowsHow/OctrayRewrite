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

layout (r32ui) uniform uimage2D sparse_data_img0;
layout (r32ui) uniform uimage2D sparse_data_img1;
layout (r32ui) uniform uimage2D voxel_data_img0;
layout (r32ui) uniform uimage2D voxel_data_img1;

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
    vertex_color = gl_Color;
    texcoord     = gl_MultiTexCoord0.xy;
    tangent_mat  = get_tangent_mat();
    block_id     = backport_id(int(mc_Entity.x));
    mid_texcoord = mc_midTexCoord;
    
    world_pos    = (gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex).xyz;
    
    gl_Position  = gbufferProjection * gbufferModelView * vec4(world_pos, 1.0);
    
    vec2  mid_delta        = mc_midTexCoord.xy - texcoord;
    vec2  tex_dir          = sign(mid_delta) * vec2(1.0, sign(at_tangent.w));
    vec3  voxel_center     = tangent_mat * vec3(tex_dir, -1.0) * 0.01;
    vec3  centered_pos     = world_pos + voxel_center / 2.0;
    uvec3 voxel_pos        = uvec3(WorldToVoxelSpace(centered_pos));
    
    
    // Store into chunk bitmap so that this chunk will be allocated next frame.
    imageStore(sparse_data_img0, get_sparse_chunk_coord(voxel_pos), uvec4(1));
    
    // Allocate extra chunks along the movement vector.
    // This prevents flickering when stepping over chunk borders.
    vec2 chunk_grow = 16.0 * sign(previousCameraPosition.xz - cameraPosition.xz);
    imageStore(sparse_data_img0, get_sparse_chunk_coord(voxel_pos + ivec3(chunk_grow.x, 0, 0)), uvec4(1));
    imageStore(sparse_data_img0, get_sparse_chunk_coord(voxel_pos + ivec3(0, 0, chunk_grow.y)), uvec4(1));
    
    // If this chunk was allocated in the previous frame
    bool alloc_flag = imageLoad(sparse_data_img1, get_sparse_chunk_coord(voxel_pos)).r != 0;
    if (alloc_flag) {
        // Store all of its data into the sparse texture
        vec2 corner_texcoord   = mc_midTexCoord.xy - abs(mc_midTexCoord.xy - texcoord);
        uint packed_tex_coord  = packUnorm2x16(corner_texcoord);
        
        vec2 hue_sat = rgb_to_hsv(vertex_color.rgb).xy;
        vec4 voxel_data        = vec4(hue_sat, 1.0 - block_id / 255.0, 0.0);
        uint packed_voxel_data = packUnorm4x8(voxel_data);
        
        imageAtomicMax(voxel_data_img0, get_sparse_voxel_coord(sparse_data_img1, voxel_pos, 0), packed_tex_coord);
        imageAtomicMax(voxel_data_img1, get_sparse_voxel_coord(sparse_data_img1, voxel_pos, 0), packed_voxel_data);
        
        for (int lod = 1; lod <= 4; ++lod) {
            imageStore(voxel_data_img1, get_sparse_voxel_coord(sparse_data_img1, voxel_pos, lod), uvec4(1));
        }
    }
}

#endif
/**********************************************************************/

/**********************************************************************/
#if defined fsh

uniform sampler2D tex;

in mat3 tangent_mat;
in vec4 vertex_color;
in vec3 world_pos;
in vec2 texcoord;

/* DRAWBUFFERS:84 */

void main() {
    vec4 diffuse = texture(tex, texcoord);
    
    if (diffuse.a < 0.1) {
        discard;
    }
    
    diffuse.rgb *= vertex_color.rgb * vertex_color.a;
    
    gl_FragData[0] = diffuse;
}

#endif
/**********************************************************************/