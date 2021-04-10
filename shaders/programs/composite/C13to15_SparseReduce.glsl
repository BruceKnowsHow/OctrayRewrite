
uniform int frameCounter;

/**********************************************************************/
#if defined composite13

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec2 viewSize;
uniform float frameTimeCounter;
uniform float far;

#include "../../includes/Voxelization.glsl"

layout (r32ui) uniform uimage2D sparse_data_img0;

uniform usampler2D sparse_data_tex0;

layout (local_size_x = 512) in;
const ivec3 workGroups = ivec3(1, 512, 1);

shared uint row_data[sparse_chunk_map_size];

vec2 texcoord = gl_GlobalInvocationID.xy / viewSize * MC_RENDER_QUALITY;

void main()  {
    // Get the boolean chunk sample from this gbuffer frame
    uint pix = texelFetch(sparse_data_tex0, ivec2(gl_GlobalInvocationID.xy), 0).x;
    
    row_data[int(gl_GlobalInvocationID.x)] = pix;
    
    barrier();
    
    // Count all allocations so far in this row
    uint data = 0;
    for (int i = 0; i <= int(gl_GlobalInvocationID.x); ++i) {
        data += row_data[i];
    }
    
    // Write back
    imageStore(sparse_data_img0, ivec2(gl_GlobalInvocationID.xy), uvec4(data));
    
    // Store boolean mask for later
    imageStore(sparse_data_img0, ivec2(gl_GlobalInvocationID.xy)+SPARSE0, uvec4(pix));
}
#endif
/**********************************************************************/



/**********************************************************************/
#if defined composite14

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec2 viewSize;
uniform float frameTimeCounter;
uniform float far;

#include "../../includes/Voxelization.glsl"

layout (r32ui) uniform uimage2D sparse_data_img0;

uniform usampler2D sparse_data_tex0;

vec2 texcoord = gl_GlobalInvocationID.xy / viewSize * MC_RENDER_QUALITY;

layout (local_size_x = 512) in;

shared uint row_data[512];
const ivec3 workGroups = ivec3(1, 1, 1);


void main() {
    row_data[int(gl_GlobalInvocationID.x)] = texelFetch(sparse_data_tex0, ivec2(sparse_chunk_map_size-1, gl_GlobalInvocationID.x), 0).x;
    barrier();
    
    uint data = 0;
    for (int i = 0; i < int(gl_GlobalInvocationID.x); ++i) {
        data += row_data[i];
    }
    
    imageStore(sparse_data_img0, ivec2(gl_GlobalInvocationID.x, sparse_chunk_map_size), uvec4(data));
}

#endif
/**********************************************************************/



/**********************************************************************/
#if defined composite15

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec2 viewSize;
uniform float far;

vec2 texcoord = gl_GlobalInvocationID.xy / viewSize * MC_RENDER_QUALITY;

#include "../../includes/Voxelization.glsl"

layout (r32ui) uniform uimage2D sparse_data_img0;

uniform usampler2D sparse_data_tex0;

layout (local_size_x = 16, local_size_y = 16) in;
const ivec3 workGroups = ivec3(32, 32, 1);


void main() {
    uvec4 data =
    uvec4( texelFetch(sparse_data_tex0, ivec2(gl_GlobalInvocationID.xy) + SPARSE0, 0).r * 
      (texelFetch(sparse_data_tex0, ivec2(gl_GlobalInvocationID.xy), 0).x
      + texelFetch(sparse_data_tex0, ivec2(gl_GlobalInvocationID.y, sparse_chunk_map_size), 0).x ));
    
    imageStore(sparse_data_img0, ivec2(gl_GlobalInvocationID.xy) + SPARSE0, data);
    
    // Clear sparse_data_tex0 for the next frame of rendering
    imageStore(sparse_data_img0, ivec2(gl_GlobalInvocationID.xy), uvec4(0));
    if (ivec2(gl_GlobalInvocationID.xy).y == sparse_chunk_map_size-1)
        imageStore(sparse_data_img0, ivec2(gl_GlobalInvocationID.x, sparse_chunk_map_size), uvec4(0));
}

#endif
/**********************************************************************/