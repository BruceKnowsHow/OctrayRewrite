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
layout (r32ui) uniform uimage2D colorimg3;
#include "../../includes/Raybuffer.glsl"
#include "../../includes/Pathtracing.glsl"
/**********************************************************************/


#include "../../includes/Parallax.glsl"


// Sky
uniform sampler2D noisetex;

#define sky_tex colortex11
uniform sampler3D sky_tex;
#include "../../includes/Sky.glsl"
/**********************************************************************/


void Something(vec3 voxelPos, uint packedVoxelData, vec4 diffuse, ivec2 texel_coord,
               vec4 tex_n, vec3 plane, inout RayStruct curr, inout uint qFront, inout uint qBack,
               inout int queue_size, inout bool fetch, const uint flag) {
    // Create the new rays
    float hue = decode_hue(packedVoxelData);
    float sat = decode_sat(packedVoxelData);
    
    diffuse.rgb = pow(diffuse.rgb, vec3(2.2));
    diffuse.rgb *= HSVtoRGB(vec3(hue, sat, 1.0));
    
    vec4 tex_s = texelFetch(atlas_tex_s, texel_coord, 0);
    
    vec3 normal;
    normal.xy = tex_n.xy * 2.0 - 1.0;
    normal.z = sqrt(max(1.0 - dot(normal.xy, normal.xy), 0.0));
    normal = normalize(normal);
    
    mat3 tanMat = RecoverTangentMat(plane);
    
    vec3 surfaceNormal = tanMat * normal;
    
    curr.absorb *= diffuse.rgb;
    curr.voxelPos = voxelPos + plane * exp2(-11);
    
    RayStruct specRay = curr;
    RayStruct  ambRay = curr;
    RayStruct  sunRay = curr;
    
    specRay.info = (GetRayDepth(curr) + 1) | SPECULAR_RAY_TYPE | flag;
    ambRay.info  = (GetRayDepth(curr) + 1) | AMBIENT_RAY_TYPE | flag;
    sunRay.info  = (GetRayDepth(curr) + 1) | SUNLIGHT_RAY_TYPE | flag;
    
    DoPBR(diffuse, surfaceNormal, tanMat[2], tex_s, curr.worldDir, specRay, ambRay, sunRay);
    
    
    // Commit the new rays
    uint rayCount = uint(RayIsVisible(specRay)) + uint(RayIsVisible(ambRay)) + uint(RayIsVisible(sunRay));
    if (rayCount == 0) return;
    
    if (uint(activeThreadsNV()) == uint(~0)) {
        fetch = false;
        
        if (RayIsVisible(specRay)) {
            curr = specRay;
            specRay.absorb *= 0.0;
        } else if (RayIsVisible(ambRay)) {
            curr = ambRay;
            ambRay.absorb *= 0.0;
        } else if (RayIsVisible(sunRay)) {
            curr = sunRay;
            sunRay.absorb *= 0.0;
        }
    }
    
    WriteRay(qBack, specRay);
    WriteRay(qBack, ambRay);
    WriteRay(qBack, sunRay);
    
    queue_size = int(qBack) - int(qFront);
}


void main()  {
    uint qFront = RaybufferReadWarp(raybuffer_front);
    uint qBack  = RaybufferReadWarp(raybuffer_back);
    int queue_size = int(qBack) - int(qFront);
    
    int count = 0;
    
    RayStruct curr;
    bool fetch = true;
    while (queue_size > 0 && queue_size < ray_queue_cap && count++ < 1024) {
        if (fetch) {
            qFront = RaybufferPopWarp();
            curr = UnpackBufferedRay(ReadBufferedRay(qFront));
        }
        
        fetch = true;
        
        // 0.0 is the clear value for the ray buffer.
        // Some fake (0, 0) rays are picked up by threads when the buffer is nearly empty.
        // These threads will do costly atomic operations on the same pixel,
        // and VoxelIntersect() on undefined data.
        if (floatBitsToUint(curr.extra.w) != qFront) return;
        // if (curr.screenCoord.x == 0 && curr.screenCoord.y == 0) return;
        
        
        
        if (IsStencilRay(curr)) {
            vec3 fract_pos = fract(curr.voxelPos);
            curr.voxelPos -= fract_pos;
            
            vec3 plane;
            vec3 bound = sign(curr.worldDir) * 0.5 + 0.5;
            vec3 dists = (bound - fract_pos) / curr.worldDir;
            
            fract_pos += curr.worldDir * MinComp(dists, plane);
            plane *= sign(curr.worldDir);
            
            vec2 tCoord = (((fract_pos) * 2.0 - 1.0) * mat2x3(RecoverTangentMat(plane))) * 0.5 + 0.5;
            
            ivec2 voxel_coord = get_sparse_voxel_coord(texelFetch(voxel_data_tex, get_sparse_chunk_coord(ivec3(curr.voxelPos)), 0).r & chunk_addr_mask, ivec3(curr.voxelPos), 0);
            uint packedVoxelData = texelFetch(voxel_data_tex, voxel_coord + DATA0, 0).r;
            vec2 spriteSize = exp2(vec2(decode_sprite_size(packedVoxelData)));
            vec2 cornerTexcoord = floor(unpackUnorm2x16(texelFetch(voxel_data_tex, voxel_coord, 0).r) * atlasSize) / atlasSize;
            ivec2 texel_coord = ivec2(cornerTexcoord * atlasSize + tCoord * spriteSize);
            
            vec4 diffuse = texelFetch(atlas_tex, texel_coord, 0);
            
            if (diffuse.a < 0.1) { // Escape
                curr.voxelPos += fract_pos + -plane * exp2(-11);
                curr.info &= ~STENCIL_RAY_TYPE;
                WriteRay(qBack, curr);
            } else { // Hit
                if (IsSunlightRay(curr)) continue;
                if (GetRayDepth(curr) >= MAX_LIGHT_BOUNCES) continue;
                
                vec4 tex_n = texelFetch(atlas_tex_n, texel_coord, 0);
                
                Something(curr.voxelPos + fract_pos, packedVoxelData, diffuse, texel_coord,
                          tex_n, -plane, curr, qFront, qBack, queue_size, fetch, STENCIL_RAY_TYPE);
            }
            
            continue;
        } else if (IsParallaxRay(curr)) {
            vec3 pl = DecodePlane(curr.info >> 24);
            
            ivec2 voxel_coord = get_sparse_voxel_coord(texelFetch(voxel_data_tex, get_sparse_chunk_coord(ivec3(curr.voxelPos)), 0).r & chunk_addr_mask, ivec3(curr.voxelPos), 0);
            uint packedVoxelData = texelFetch(voxel_data_tex, voxel_coord + DATA0, 0).r;
            vec2 spriteSize = exp2(vec2(decode_sprite_size(packedVoxelData)));
            vec2 cornerTexcoord = floor(unpackUnorm2x16(texelFetch(voxel_data_tex, voxel_coord, 0).r) * atlasSize) / atlasSize;
            
            mat3 tanMat = RecoverTangentMat(pl);
            
            vec3 tanRay = curr.worldDir;
            vec3 tanPos = curr.extra.xyz;
            
            vec3 plane;
            ivec2 texel_coord = Parallax(tanPos, tanRay, plane, ivec2(cornerTexcoord*atlasSize), ivec2(spriteSize), 0);
            
            bool hit = texel_coord.x != -10;
            
            if (!hit) {
                tanPos.xy /= spriteSize;
                vec3 fract_pos = (tanMat * (tanPos*2.0-1.0))*0.5+0.5;
                curr.voxelPos = floor(curr.voxelPos) + fract_pos + -pl * exp2(-11);
                curr.info &= ~PARALLAX_RAY_TYPE;
                curr.info &= ((1<<24)-1);
                curr.worldDir = tanMat * curr.worldDir;
                WriteRay(qBack, curr);
                continue;
            }
            
            // Create the new rays
            vec4 diffuse = texelFetch(atlas_tex, texel_coord, 0);
            diffuse.rgb = pow(diffuse.rgb, vec3(2.2));
            
            curr.absorb *= diffuse.rgb;
            curr.extra.xyz = tanPos;
            
            vec4 tex_n = texelFetch(atlas_tex_n, texel_coord, 0);
            vec4 tex_s = texelFetch(atlas_tex_s, texel_coord, 0);
            
            vec3 normal;
            normal.xy = tex_n.xy * 2.0 - 1.0;
            normal.z = sqrt(max(1.0 - dot(normal.xy, normal.xy), 0.0));
            normal = normalize(normal);
            
            vec3 surfaceNormal = normal;
            
            if (IsSunlightRay(curr)) continue;
            if (GetRayDepth(curr) >= MAX_LIGHT_BOUNCES) continue;
            
            RayStruct specRay = curr;
            RayStruct  ambRay = curr;
            RayStruct  sunRay = curr;
            
            specRay.info = (GetRayDepth(curr) + 1) | SPECULAR_RAY_TYPE | PARALLAX_RAY_TYPE | (curr.info & (~((1<<24)-1)));
            ambRay.info  = (GetRayDepth(curr) + 1) | AMBIENT_RAY_TYPE | PARALLAX_RAY_TYPE | (curr.info & (~((1<<24)-1)));
            sunRay.info  = (GetRayDepth(curr) + 1) | SUNLIGHT_RAY_TYPE | PARALLAX_RAY_TYPE | (curr.info & (~((1<<24)-1)));
            
            DoPBR(diffuse, plane, plane, tex_s, tanRay, specRay, ambRay, sunRay);
            sunRay.worldDir = sunRay.worldDir * tanMat;
            sunRay.absorb = curr.absorb;
            
            WriteRay(qBack, specRay);
            WriteRay(qBack, ambRay);
            WriteRay(qBack, sunRay);
            continue;
        }
        
        
        
        VoxelIntersectOut VIO = VoxelIntersect(curr.voxelPos, curr.worldDir);
        
        if (!VIO.hit) {
            vec3 color = vec3(0.0);
            
            if (IsSunlightRay(curr))
                color += curr.absorb * vec3(1.0) * GetSunIrradiance(kPoint(VoxelToWorldSpace(VIO.voxelPos)), sunDirection);
            else
                color += ComputeTotalSky(VoxelToWorldSpace(VIO.voxelPos), curr.worldDir, curr.absorb, false) * 0.2 / (IsPrimaryRay(curr) ? 4.0 : 1.0);
            
            if (!(IsSunlightRay(curr) && VIO.hit))
                WriteColor(color, curr.screenCoord);
            
            continue;
        }
        
        if (GetRayDepth(curr) >= MAX_LIGHT_BOUNCES) continue;
        
        uint packedVoxelData = texelFetch(voxel_data_tex, VIO.voxel_coord + DATA0, 0).r;
        int  blockID = decode_block_id(packedVoxelData);
        
        vec2 tCoord;
        
        if (is_AABB(packedVoxelData)) {
            // This should be a more complex AABB, but should not check stenciling
            // As that will be split out into a different kernel
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
        
        vec2 spriteSize = exp2(vec2(decode_sprite_size(packedVoxelData)));
        
        ivec2 texel_coord = ivec2(cornerTexcoord * atlasSize + tCoord * spriteSize);
        
        vec4 diffuse = texelFetch(atlas_tex, texel_coord, 0);
        vec4 tex_n = texelFetch(atlas_tex_n, texel_coord, 0);
        
        
        if (diffuse.a <= 0.1) {
            // curr.info |= STENCIL_RAY_TYPE;
            // curr.voxelPos = VIO.voxelPos - VIO.plane * exp2(-12);
            // WriteRay(qBack, curr);
            
            // continue;
        } else if (diffuse.a < 1.0) {
            // continue;
        } else if (tex_n.a < 1.0) {
            // if (!(IsPrimaryRay(curr) || IsSpecularRay(curr))) continue;
            // curr.info |= PARALLAX_RAY_TYPE;
            // curr.voxelPos = VIO.voxelPos - VIO.plane * exp2(-12);
            // mat3 tanMat = RecoverTangentMat(VIO.plane);
            // vec3 tanPos = vec3(tCoord * spriteSize, 1.0);
            // curr.extra.xyz = tanPos;
            // curr.worldDir = curr.worldDir * tanMat;
            
            // curr.info |= EncodePlane(VIO.plane) << 24;
            
            // WriteRay(qBack, curr);
            
            // continue;
        }
        
        if (IsSunlightRay(curr)) {
            continue;
        }
        
        // Create the new rays
        Something(VIO.voxelPos, packedVoxelData, diffuse, texel_coord, tex_n,
                  VIO.plane, curr, qFront, qBack, queue_size, fetch, 0);
    }
}
