layout (local_size_x = 32, local_size_y = 4) in;
const ivec3 workGroups = ivec3(1024, 8, 1);

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 sunDirection;
uniform vec2 viewSize;
uniform ivec2 atlasSize;
uniform float frameTimeCounter;
uniform float far;
uniform int frameCounter;


// Voxelization and voxel intersection
#include "../../includes/Voxelization.glsl"
uniform usampler2D sparse_data_tex0;
#include "../../BlockMappings.glsl"
#include "../../includes/VoxelIntersect.glsl"
/**********************************************************************/


// Random
#define RAND_SEED uint(uint(gl_GlobalInvocationID.x) + uint(16384) * frameCounter)
#include "../../includes/Random.glsl"
/**********************************************************************/


// Path tracing & ray buffer
layout (rgba32f) uniform image2D colorimg2;
layout (r32i) uniform iimage2D colorimg3;
layout (rgba8) uniform image2D colorimg5;
#include "../../includes/Raybuffer.glsl"
#include "../../includes/Pathtracing.glsl"
/**********************************************************************/


// Atomic color write
#define screen_color_img colorimg4
layout (r32ui) uniform uimage2D screen_color_img;

uvec2 EncodeColor(vec3 color) {
    color = color * 256;
    color = clamp(color, vec3(0.0), vec3(1 << 15));
    
    uvec3 col = uvec3(color);
    return uvec2(col.r + (col.g << 16), col.b);
}

void WriteColor(vec3 color, ivec2 screenCoord) {
    uvec2 enc = EncodeColor(color);
    
    imageAtomicAdd(screen_color_img, screenCoord * ivec2(2, 1)              , enc.x);
    imageAtomicAdd(screen_color_img, screenCoord * ivec2(2, 1) + ivec2(1, 0), enc.y);
}
/**********************************************************************/


// Sky
uniform sampler2D noisetex;

#define sky_tex colortex11
uniform sampler3D sky_tex;
#include "../../includes/Sky.glsl"
/**********************************************************************/


void main()  {
    int qFront = RaybufferReadWarp(raybufferFront);
    int qBack  = RaybufferReadWarp(raybufferBack);
    
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
        
        uint packedVoxelData = texelFetch(voxel_data_tex0, VIO.voxel_coord + DATA0, 0).r;
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
        
        vec2 cornerTexcoord = floor(unpackUnorm2x16(texelFetch(voxel_data_tex0, VIO.voxel_coord, 0).r) * atlasSize) / atlasSize;
        
        vec2 spriteSize;
        int ebin = decode_sprite_size(packedVoxelData);
        spriteSize = exp2(vec2(ebin));
        
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
        
        // vec3 normal;
        // normal.xy = tex_n.xy * 2.0 - 1.0;
        // normal.z = sqrt(max(1.0 - dot(normal.xy, normal.xy), 0.0));
        // normal = normalize(normal);
        
        // vec3 surfaceNormal = tanMat * normal;
        
        
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
        
        // vec4 diffuse, vec4 tex_n, vec4 tex_s, mat3 tanMat, vec3 worldDir,
        //           inout RayStruct specRay, inout RayStruct ambRay, inout RayStruct sunRay
        
        // bool isMetal = tex_s.g > 229.5/255.0;
        
        // float roughness = pow(1.0 - tex_s.r, 2.0);
        // vec3 F0 = (isMetal) ? diffuse.rgb : vec3(tex_s.g);
        
        // RayStruct specular = curr;
        
        // specular.info = (GetRayDepth(specular) + 1) | SPECULAR_RAY_TYPE;
        
        // vec2 uv = RandNext2F();
        
        // vec3 V = reflect(curr.worldDir, surfaceNormal);
        // mat3 atbn = ArbitraryTBN(V);
        // specular.worldDir = normalize(atbn * GGXVNDFSample(V * atbn, roughness*roughness, uv));
        
        // float cosTheta = dot(specular.worldDir, surfaceNormal);
        // float G = GeometrySmith(surfaceNormal, -curr.worldDir, specular.worldDir, roughness);
        
        // vec3 F = fresnelSchlick(cosTheta, vec3(F0));
        // vec3 numerator = G * F;
        
        // float denominator = (4.0*0+1) * max(dot(surfaceNormal, -curr.worldDir), 0.0) * max(dot(surfaceNormal, specular.worldDir), 0.0);
        
        // vec3 spec = numerator / max(denominator, 0.001);
        
        // vec3 kS = F;
        // vec3 kD = (1.0 - kS) * float(!isMetal);
        
        // float NdotL = max(dot(surfaceNormal, specular.worldDir), 0.0);
        
        // vec3 Li = (kD * diffuse.rgb*0 * 4.0 + spec) * NdotL;
        
        // specular.absorb = curr.absorb * Li * float(dot(specular.worldDir, VIO.plane) > 0.0);
        
        
        // RayStruct ambient = curr;
        // ambient.worldDir = ArbitraryTBN(surfaceNormal) * CalculateConeVector(RandNextF(), radians(90.0), 32);
        // ambient.absorb   *= float(dot(ambient.worldDir, VIO.plane) > 0.0) * float(!isMetal);
        // ambient.info      = (GetRayDepth(ambient) + 1) | AMBIENT_RAY_TYPE;
        
        
        // RayStruct sunlight = curr;
        
        // vec3 sun_direction = ArbitraryTBN(sunDirection)*CalculateConeVector(RandNextF(), radians(1.0), 32);
        // sunlight.absorb *= max(0.0, dot(sun_direction, surfaceNormal)) * mix(vec3(1.0), kD, isMetal);
        // sunlight.worldDir = normalize(sun_direction);
        // sunlight.info      = (GetRayDepth(sunlight) + 1) | SUNLIGHT_RAY_TYPE;
        
        // WriteBufferedRay(qBack, buf, specular);
        // WriteBufferedRay(qBack, buf, ambient);
        // WriteBufferedRay(qBack, buf, sunlight);
        
        
        // if (gl_ThreadInWarpNV == findLSB(activeThreadsNV())) {
        //     qBack = imageAtomicOr(buffer_count_img, raybufferBack, 0);
        // }
        
        // qBack = shuffleNV(qBack, findLSB(activeThreadsNV()), 32);
        
        
        // bool specRay = RayIsVisible(specular);
        // bool ambRay = RayIsVisible(ambient);
        // bool sunRay = RayIsVisible(sunlight);
        
        // uint specMask = ballotThreadNV(specRay);
        // uint ambMask = ballotThreadNV(ambRay);
        // uint sunMask = ballotThreadNV(sunRay);
        
        // int specRays = bitCount(specMask);
        // int ambRays = bitCount(ballotThreadNV(ambRay));
        // int sunRays = bitCount(ballotThreadNV(sunRay));
        
        // int ray_alloc = specRays + ambRays + sunRays;
        
        // uint first_thread = findLSB(activeThreadsNV());
        
        // int addr = 0;
        // if (gl_ThreadInWarpNV == first_thread) {
        //     addr = imageAtomicAdd(buffer_count_img, raybufferBack, ray_alloc);
        // }
        
        // addr = shuffleNV(addr, first_thread, 32);
        
        // int specPrefix = bitCount(specMask & ((1 << gl_ThreadInWarpNV) - 1)) - 1;
        // int ambPrefix = bitCount(ambMask & ((1 << gl_ThreadInWarpNV) - 1)) - 1;
        // int sunPrefix = bitCount(sunMask & ((1 << gl_ThreadInWarpNV) - 1)) - 1;
        
        // int specAddr = addr + specPrefix;
        // int ambAddr = addr + ambPrefix + specRays;
        // int sunAddr = addr + sunPrefix + specRays + ambRays;
        
        // if (specRay) { PackBufferedRay(buf, specular); WriteBufferedRay(specAddr, buf); }
        // if (ambRay) { PackBufferedRay(buf, ambient); WriteBufferedRay(ambAddr, buf); }
        // if (sunRay) { PackBufferedRay(buf, sunlight); WriteBufferedRay(sunAddr, buf); }
        
        // qBack = addr + ray_alloc;
    }
}
