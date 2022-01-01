uniform vec3 cameraPosition;
uniform vec2 viewSize;
uniform float far;

#include "../../includes/Voxelization.glsl"

/**********************************************************************/
#if defined composite13

layout (r32ui) uniform uimage2D colorimg3;

uniform usampler2D colortex3;

layout (local_size_x = 512) in;

#if MC_VERSION >= 11800
const ivec3 workGroups = ivec3(1, 768, 1);
#else
const ivec3 workGroups = ivec3(1, 512, 1);
#endif

shared uint row_data[chunk_map_width];

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

#if MC_VERSION >= 11800
layout (local_size_x = 768) in;
#else
layout (local_size_x = 512) in;
#endif

const ivec3 workGroups = ivec3(1, 1, 1);

shared uint row_data2[chunk_map_width];

void main() {
    row_data2[int(gl_GlobalInvocationID.x)] = texelFetch(colortex3, ivec2(chunk_map_width-1, gl_GlobalInvocationID.x), 0).x;
    barrier();
    
    uint data = 0;
    for (int i = 0; i < int(gl_GlobalInvocationID.x); ++i) {
        data += row_data2[i];
    }
    
    imageStore(colorimg3, ivec2(gl_GlobalInvocationID.x, chunk_map_height), uvec4(data));
}

#endif
/**********************************************************************/



/**********************************************************************/
#if defined composite15

layout (r32ui) uniform uimage2D colorimg3;

uniform usampler2D colortex3;

layout (local_size_x = 16, local_size_y = 16) in;

#if MC_VERSION >= 11800
const ivec3 workGroups = ivec3(32, 48, 1);
#else
const ivec3 workGroups = ivec3(32, 32, 1);
#endif


void main() {
    uvec4 data =
    uvec4( texelFetch(colortex3, ivec2(gl_GlobalInvocationID.xy) + SPARSE0, 0).r * 
      (texelFetch(colortex3, ivec2(gl_GlobalInvocationID.xy), 0).x
      + texelFetch(colortex3, ivec2(gl_GlobalInvocationID.y, chunk_map_height), 0).x ));
    
    imageStore(colorimg3, ivec2(gl_GlobalInvocationID.xy) + SPARSE0, data);
    
    // Clear colortex3 for the next frame of rendering
    imageStore(colorimg3, ivec2(gl_GlobalInvocationID.xy), uvec4(0));
    
    if (gl_GlobalInvocationID.x == 0 && gl_GlobalInvocationID.y == 0) {
        imageStore(colorimg3, ivec2(2, chunk_map_height+1), uvec4(imageLoad(colorimg3, ivec2(0, chunk_map_height+1)).x));
        imageStore(colorimg3, ivec2(3, chunk_map_height+1), uvec4(imageLoad(colorimg3, ivec2(1, chunk_map_height+1)).x));
        
        imageStore(colorimg3, ivec2(0, chunk_map_height+1), uvec4(0));
        imageStore(colorimg3, ivec2(1, chunk_map_height+1), uvec4(0));
    }
    
    if (gl_GlobalInvocationID.x == chunk_map_height-1 && gl_GlobalInvocationID.y == chunk_map_height-1) {
        imageStore(colorimg3, ivec2(5, chunk_map_height+1), uvec4(texelFetch(colortex3, ivec2(chunk_map_height-1, chunk_map_height), 0).x));
    }
}

#endif
/**********************************************************************/