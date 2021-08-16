uniform vec3 cameraPosition;
uniform vec2 viewSize;
uniform float far;

#include "../../includes/Voxelization.glsl"

/**********************************************************************/
#if defined composite13

layout (r32ui) uniform uimage2D colorimg3;

uniform usampler2D colortex3;

layout (local_size_x = 512) in;
const ivec3 workGroups = ivec3(1, 512, 1);

shared uint row_data[sparse_chunk_map_size];

void main()  {
    // Get the boolean chunk sample from this gbuffer frame
    uint pix = texelFetch(colortex3, ivec2(gl_GlobalInvocationID.xy), 0).x;
    
    row_data[int(gl_GlobalInvocationID.x)] = pix;
    
    barrier();
    
    // Count all allocations so far in this row
    uint data = 0;
    for (int i = 0; i <= int(gl_GlobalInvocationID.x); ++i) {
        data += row_data[i];
    }
    
    // Write back
    imageStore(colorimg3, ivec2(gl_GlobalInvocationID.xy), uvec4(data));
    
    // Store boolean mask for later
    imageStore(colorimg3, ivec2(gl_GlobalInvocationID.xy)+SPARSE0, uvec4(pix));
}
#endif
/**********************************************************************/



/**********************************************************************/
#if defined composite14

layout (r32ui) uniform uimage2D colorimg3;

uniform usampler2D colortex3;

layout (local_size_x = 512) in;

shared uint row_data2[512];
const ivec3 workGroups = ivec3(1, 1, 1);


void main() {
    row_data2[int(gl_GlobalInvocationID.x)] = texelFetch(colortex3, ivec2(sparse_chunk_map_size-1, gl_GlobalInvocationID.x), 0).x;
    barrier();
    
    uint data = 0;
    for (int i = 0; i < int(gl_GlobalInvocationID.x); ++i) {
        data += row_data2[i];
    }
    
    imageStore(colorimg3, ivec2(gl_GlobalInvocationID.x, sparse_chunk_map_size), uvec4(data));
}

#endif
/**********************************************************************/



/**********************************************************************/
#if defined composite15

layout (r32ui) uniform uimage2D colorimg3;

uniform usampler2D colortex3;

layout (local_size_x = 16, local_size_y = 16) in;
const ivec3 workGroups = ivec3(32, 32, 1);


void main() {
    uvec4 data =
    uvec4( texelFetch(colortex3, ivec2(gl_GlobalInvocationID.xy) + SPARSE0, 0).r * 
      (texelFetch(colortex3, ivec2(gl_GlobalInvocationID.xy), 0).x
      + texelFetch(colortex3, ivec2(gl_GlobalInvocationID.y, sparse_chunk_map_size), 0).x ));
    
    imageStore(colorimg3, ivec2(gl_GlobalInvocationID.xy) + SPARSE0, data);
    
    // Clear colortex3 for the next frame of rendering
    imageStore(colorimg3, ivec2(gl_GlobalInvocationID.xy), uvec4(0));
    
    if (gl_GlobalInvocationID.x == 0 && gl_GlobalInvocationID.y == 0) {
        imageStore(colorimg3, ivec2(2, 513), uvec4(imageLoad(colorimg3, ivec2(0, 513)).x));
        imageStore(colorimg3, ivec2(3, 513), uvec4(imageLoad(colorimg3, ivec2(1, 513)).x));
        
        imageStore(colorimg3, ivec2(0, 513), uvec4(0));
        imageStore(colorimg3, ivec2(1, 513), uvec4(0));
    }
    
    if (gl_GlobalInvocationID.x == 511 && gl_GlobalInvocationID.y == 511) {
        imageStore(colorimg3, ivec2(5, 513), uvec4(texelFetch(colortex3, ivec2(511, 512), 0).x));
    }
}

#endif
/**********************************************************************/