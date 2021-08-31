layout (local_size_x = 16, local_size_y = 16) in;
const ivec3 workGroups = ivec3(64, 64, 1);

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec2 viewSize;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform float far;

uniform sampler2D depthtex2;
ivec2 atlasSize = ivec2(textureSize(depthtex2, 0).xy);

#include "../../includes/Parallax.glsl"

void main() {
    
    
    #ifdef PARALLAX
    if (imageLoad(colorimg2, ivec2(4095)).r != 0) return;
    
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    
    for (int x = 0; x < 16*1024; x += 16*64) {
        for (int y = 0; y < 16*1024; y += 16*64) {
            float texel_height = texelFetch(depthtex2, coord+ivec2(x,y), 0).a;
            
            // imageAtomicMax(colorimg2, get_POM_coord(coord + ivec2(x, y), 0), floatBitsToUint(texel_height));
            imageAtomicMax(colorimg2, get_POM_coord(coord + ivec2(x, y), 1), floatBitsToUint(texel_height));
            imageAtomicMax(colorimg2, get_POM_coord(coord + ivec2(x, y), 2), floatBitsToUint(texel_height));
            imageAtomicMax(colorimg2, get_POM_coord(coord + ivec2(x, y), 3), floatBitsToUint(texel_height));
            imageAtomicMax(colorimg2, get_POM_coord(coord + ivec2(x, y), 4), floatBitsToUint(texel_height));
            // imageAtomicMax(colorimg2, get_POM_coord(coord + ivec2(x, y), 5), floatBitsToUint(texel_height));
            // imageAtomicMax(colorimg2, get_POM_coord(coord + ivec2(x, y), 6), floatBitsToUint(texel_height));
            // imageAtomicMax(colorimg2, get_POM_coord(coord + ivec2(x, y), 7), floatBitsToUint(texel_height));
            // imageAtomicMax(colorimg2, get_POM_coord(coord + ivec2(x, y), 8), floatBitsToUint(texel_height));
            // imageAtomicMax(colorimg2, get_POM_coord(coord + ivec2(x, y), 9), floatBitsToUint(texel_height));
        }
    }
    #endif
}
