layout (local_size_x = 32, local_size_y = 32) in;
const ivec3 workGroups = ivec3(128, 8, 1);

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 sunDirection;
uniform vec2 viewSize;
uniform ivec2 atlasSize;
uniform float frameTimeCounter;
uniform float far;
uniform int frameCounter;

#include "../../includes/Debug.glsl"


// Voxelization and voxel intersection
#include "../../includes/Voxelization.glsl"
#include "../../BlockMappings.glsl"
#include "../../includes/VoxelIntersect.glsl"
/**********************************************************************/


// Random
#define RAND_SEED uint(uint(gl_GlobalInvocationID.x) + uint(16384) * frameCounter)
#include "../../includes/Random.glsl"
/**********************************************************************/


// Path tracing & ray buffer
layout (r32ui) uniform uimage2D voxel_data_img;
#include "../../includes/Raybuffer.glsl"
#include "../../includes/Pathtracing.glsl"
/**********************************************************************/


// Sky
uniform sampler2D noisetex;

#define sky_tex colortex11
uniform sampler3D sky_tex;
#include "../../includes/Sky.glsl"
/**********************************************************************/


void main()  {
    uint qFront = RaybufferReadWarp(raybuffer_front);
    uint qBack  = RaybufferReadWarp(raybuffer_back);
    
    int count = 0;
    
    while (qFront < qBack && count++ < 128) {
        qFront = RaybufferPopWarp();
        
        BufferedRay buf = ReadBufferedRay(qFront);
        
        ivec2 screenCoord = ivec2(buf._0.xy);
        
        // screenCoord = UnpackCoord(buf._0.x);
        // 0.0 is the clear value for the ray buffer.
        // Some fake (0, 0) rays are picked up by threads when the buffer is nearly empty.
        // These threads will do costly atomic operations on the same pixel,
        // and VoxelIntersect() on undefined data.
        if (screenCoord.x == 0 && screenCoord.y == 0) continue;
        
        RayStruct curr = UnpackBufferedRay(buf);
        
        VoxelIntersectOut VIO = VoxelIntersect(curr.voxelPos, curr.worldDir);
        
        vec3 color = vec3(0.0);
        
        if (!VIO.hit || IsSunlightRay(curr)) {
            if (IsSunlightRay(curr))
                color += curr.absorb * vec3(1.0) * GetSunIrradiance(kPoint(VoxelToWorldSpace(VIO.voxelPos)), sunDirection);
            else
                color += ComputeTotalSky(VoxelToWorldSpace(VIO.voxelPos), curr.worldDir, curr.absorb, false) * 0.2 / (IsPrimaryRay(curr) ? 4.0 : 1.0);
            
            if (!(IsSunlightRay(curr) && VIO.hit))
                WriteColor(color, screenCoord);
            
            continue;
        }
        
        if (GetRayDepth(curr) >= 3)
            continue;
        
        uint packedVoxelData = texelFetch(voxel_data_tex, VIO.voxel_coord + DATA0, 0).r;
        int  blockID = decode_block_id(packedVoxelData);
        
        vec2 tCoord;
        
        if (is_AABB(packedVoxelData)) {
            vec3 fract_pos = fract(VIO.voxelPos - VIO.plane * exp2(-12));
            VIO.voxelPos = VIO.voxelPos - fract_pos;
            IntersectAABB(fract_pos, curr.worldDir, unpack_AABB(bounds[blockID/4][blockID%4]), VIO.plane);
            
            VIO.plane *= -sign(curr.worldDir);
            
            tCoord = (((fract_pos) * 2.0 - 1.0) * mat2x3(RecoverTangentMat(VIO.plane))) * 0.5 + 0.5;
            
            VIO.voxelPos = VIO.voxelPos + fract_pos;
        } else {
            tCoord = ((fract(VIO.voxelPos) * 2.0 - 1.0) * mat2x3(RecoverTangentMat(VIO.plane))) * 0.5 + 0.5;
        }
        
        vec2 cornerTexcoord = floor(unpackUnorm2x16(texelFetch(voxel_data_tex, VIO.voxel_coord, 0).r) * atlasSize) / atlasSize;
        
        vec2 spriteSize;
        spriteSize = exp2(vec2(decode_sprite_size(packedVoxelData)));
        
        ivec2 texel_coord = ivec2(cornerTexcoord * atlasSize + tCoord * spriteSize);
        
        vec4 diffuse = texelFetch(atlas_tex, texel_coord, 0);
        
        if (diffuse.a < 0.1)
            continue;
        
        float hue = decode_hue(packedVoxelData);
        float sat = decode_sat(packedVoxelData);
        
        diffuse.rgb = pow(diffuse.rgb, vec3(2.2));
        diffuse.rgb *= HSVtoRGB(vec3(hue, sat, 1.0));
        
        mat3 tanMat = RecoverTangentMat(VIO.plane);
        
        vec4 tex_n = texelFetch(atlas_tex_n, texel_coord, 0);
        vec4 tex_s = texelFetch(atlas_tex_s, texel_coord, 0);
        
        curr.absorb *= diffuse.rgb;
        curr.voxelPos = VIO.voxelPos + VIO.plane * exp2(-11);
        
        vec3 normal;
        normal.xy = tex_n.xy * 2.0 - 1.0;
        normal.z = sqrt(max(1.0 - dot(normal.xy, normal.xy), 0.0));
        normal = normalize(normal);
        
        vec3 surfaceNormal = tanMat * normal;
        
        uint info = curr.info;
        
        curr.info = GetRayDepth(curr) + 1;
        
        RayStruct specRay = curr;
        RayStruct  ambRay = curr;
        RayStruct  sunRay = curr;
        
        specRay.info |= SPECULAR_RAY_TYPE;
        ambRay.info  |= AMBIENT_RAY_TYPE;
        sunRay.info  |= SUNLIGHT_RAY_TYPE;
        
        DoPBR(diffuse, surfaceNormal, tanMat[2], tex_s, curr.worldDir, specRay, ambRay, sunRay);
        
        if ((info & AMBIENT_RAY_TYPE) != 0) sunRay.absorb *= 4;
        
        WriteBufferedRay(qBack, buf, specRay);
        WriteBufferedRay(qBack, buf, ambRay);
        WriteBufferedRay(qBack, buf, sunRay);
    }
}
