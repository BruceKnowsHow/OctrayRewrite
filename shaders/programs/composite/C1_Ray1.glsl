layout (local_size_x = 32, local_size_y = 32) in;
const ivec3 workGroups = ivec3(128, 8, 1);

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 sunDirection;
uniform vec2 viewSize;
uniform float frameTimeCounter;
uniform float far;
uniform int frameCounter;

#include "../../includes/debug.glsl"

// Voxelization and voxel intersection
#include "../../includes/Voxelization.glsl"
#include "../../BlockMappings.glsl"

uniform usampler2D voxel_data_tex;
uniform usampler2D colortex3;
uniform usampler2D atlas_tex;
uniform usampler2D atlas_tex_n;
uniform usampler2D atlas_tex_s;

struct VoxelIntersectOut {
    bool  hit;
    vec3  voxelPos;
    vec3  plane;
    ivec2 voxel_coord;
};

#define BinaryDot(a, b) ((a.x & b.x) | (a.y & b.y) | (a.z & b.z))
#define BinaryMix(a, b, c) ((a & (~c)) | (b & c))

float BinaryDotF(vec3 v, ivec3 uplane) {
    ivec3 u = floatBitsToInt(v);
    return intBitsToFloat(BinaryDot(u, uplane));
}

float MinComp(vec3 v, out vec3 minCompMask) {
    float minComp = min(v.x, min(v.y, v.z));
    minCompMask.xy = 1.0 - clamp((v.xy - minComp) * 1e35, 0.0, 1.0);
    minCompMask.z = 1.0 - minCompMask.x - minCompMask.y;
    return minComp;
}

ivec3 GetMinCompMask(vec3 v) {
    ivec3 ia = floatBitsToInt(v);
    ivec3 iCompMask;
    iCompMask.xy = ((ia.xy - ia.yx) & (ia.xy - ia.zz)) >> 31;
    iCompMask.z = (-1) ^ iCompMask.x ^ iCompMask.y;
    
    return iCompMask;
}

ivec2 GetNonMinComps(ivec3 xyz, ivec3 uplane) {
    return BinaryMix(xyz.xz, xyz.yy, uplane.xz);
}

int GetMinComp(ivec3 xyz, ivec3 uplane) {
    return BinaryDot(xyz, uplane);
}

ivec3 SortMinComp(ivec3 xyz, ivec3 uplane) {
    ivec3 ret;
    ret.xy = GetNonMinComps(xyz, uplane);
    ret.z  = (xyz.x ^ xyz.y) ^ xyz.z ^ (ret.x ^ ret.y);
    return ret;
}

ivec3 UnsortMinComp(ivec3 uvw, ivec3 uplane) {
    ivec3 ret;
    ret.xz = BinaryMix(uvw.xy, uvw.zz, uplane.xz);
    ret.y = (uvw.x ^ uvw.y) ^ uvw.z ^ (ret.x ^ ret.z);
    return ret;
}

mat3 RecoverTangentMat(vec3 plane) {
    mat3 tbn;
    
    vec3 plane3 = abs(plane);
    
    tbn[0].z = -plane.x;
    tbn[0].y = 0.0;
    tbn[0].x = plane3.y + plane.z;
    
    tbn[1].x = 0.0;
    tbn[1].y = -plane3.x - plane3.z;
    tbn[1].z = plane3.y;
    
    tbn[2] = plane;
    
    return tbn;
}

uint EncodePlane(vec3 plane) {
    if (plane.x > 0.5) return 0;
    if (plane.x < -0.5) return 1;
    if (plane.y > 0.5) return 2;
    if (plane.y < -0.5) return 3;
    if (plane.z > 0.5) return 4;
    if (plane.z < -0.5) return 5;
}

vec3 DecodePlane(uint enc) {
    if (enc == 0) return vec3(1, 0, 0);
    if (enc == 1) return vec3(-1, 0, 0);
    if (enc == 2) return vec3(0, 1, 0);
    if (enc == 3) return vec3(0, -1, 0);
    if (enc == 4) return vec3(0, 0, 1);
    return vec3(0, 0, -1);
}

struct AABB {
    vec3 minBounds;
    vec3 maxBounds;
};

// Optimized AABB function that only does binary checks.
// Will erroniously find intersections which happen behind pos.
// Useful for the interior marching loop, which needs to be very fast.
bool SimpleIntersectAABB(vec3 pos, vec3 dir, AABB aabb) {
    vec3 minBoundsDist = (aabb.minBounds - pos) / dir;
    vec3 maxBoundsDist = (aabb.maxBounds - pos) / dir;
    
    vec3 minDists = min(minBoundsDist, maxBoundsDist);
    vec3 maxDists = intBitsToFloat(floatBitsToInt(minBoundsDist) ^ floatBitsToInt(maxBoundsDist) ^ floatBitsToInt(minDists));
    
    ivec3 a = floatBitsToInt(minDists - maxDists.yzx);
    ivec3 b = floatBitsToInt(minDists - maxDists.zxy);
    a = a & b;
    return (a.x & a.y & a.z) < 0;
}

// More general AABB check.
// Avoids reporting intersections behind pos.
// Returns normal and position information for hit.
bool IntersectAABB(inout vec3 pos, vec3 dir, AABB aabb, out vec3 plane) {
    vec3 minBoundsDist = (aabb.minBounds - pos) / dir;
    vec3 maxBoundsDist = (aabb.maxBounds - pos) / dir;
    
    vec3 minDists = min(minBoundsDist, maxBoundsDist);
    vec3 maxDists = intBitsToFloat(floatBitsToInt(minBoundsDist) ^ floatBitsToInt(maxBoundsDist) ^ floatBitsToInt(minDists));
    
    ivec3 a = floatBitsToInt(minDists - maxDists.yzx);
    ivec3 b = floatBitsToInt(minDists - maxDists.zxy);
    a = a & b;
    if ((a.x & a.y & a.z) >= 0)
        return false;
    
    vec3 positiveDir = step(0.0, dir);
    vec3 dists = mix(maxBoundsDist, minBoundsDist, positiveDir);
    
    MinComp(-dists, plane);
         dists = max(vec3(0.0), dists);
    
    float dist;
    
    if (dists.x > dists.y) {
        if (dists.x > dists.z) {
            dist = dists.x;
        } else {
            dist = dists.z;
        }
    } else if (dists.y > dists.z) {
        dist = dists.y;
    } else {
        dist = dists.z;
    }
    
    
    pos = pos + dir * dist;
    
    return dist > 0.0;
}

int PackAABB(vec3 minBounds, vec3 maxBounds) {
    int ret = 0;
    ivec3 b0 = ivec3(minBounds * 16.0);
    ivec3 b1 = ivec3(maxBounds * 16.0);
    
    b0.yz = b0.yz << ivec2(5, 10);
    b1.yz = b1.yz << ivec2(5, 10);
    
    b1 = b1 << 15;
    
    b0 |= b1;
    
    return b0.x | b0.y | b0.z;
}

AABB unpack_AABB(int data) {
    ivec3 b0 = (ivec3(data) >> ivec3(0, 5, 10)) & ivec3((1 << 5) - 1);
    ivec3 b1 = (ivec3(data) >> ivec3(15, 20, 25)) & ivec3((1 << 5) - 1);
    
    AABB aabb;
    aabb.minBounds = vec3(b0) / 16.0;
    aabb.maxBounds = vec3(b1) / 16.0;
    return aabb;
}

ivec4 bounds[6] = ivec4[6](
    ivec4( PackAABB(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0)),
           PackAABB(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0)),
           PackAABB(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0)),
           PackAABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 0.5, 1.0)) ),
    ivec4( PackAABB(vec3(0.0, 0.5, 0.0), vec3(1.0, 1.0, 1.0)),
           PackAABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 0.5, 1.0)),
           PackAABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 1.0/8.0, 1.0)),
           PackAABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 2.0/8.0, 1.0)) ),
    ivec4( PackAABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 3.0/8.0, 1.0)),
           PackAABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 4.0/8.0, 1.0)),
           PackAABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 5.0/8.0, 1.0)),
           PackAABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 6.0/8.0, 1.0)) ),
    ivec4( PackAABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 7.0/8.0, 1.0)),
           PackAABB(vec3(1.0/16.0, 0.0, 1.0/16.0), vec3(15.0/16.0, 1.0/16.0, 15.0 / 16.0)),
           PackAABB(vec3(5.0/16.0, 6.0/16.0, 14.0/16.0), vec3(11.0/16.0, 10.0/16.0, 16.0 / 16.0)),
           PackAABB(vec3(5.0/16.0, 6.0/16.0, 0.0/16.0), vec3(11.0/16.0, 10.0/16.0, 2.0 / 16.0)) ),
    ivec4( PackAABB(vec3(5.0/16.0, 6.0/16.0, 0.0/16.0).zyx, vec3(11.0/16.0, 10.0/16.0, 2.0 / 16.0).zyx),
           PackAABB(vec3(5.0/16.0, 6.0/16.0, 14.0/16.0).zyx, vec3(11.0/16.0, 10.0/16.0, 16.0 / 16.0).zyx),
           PackAABB(vec3(5.0/16.0, 0.0/16.0, 6.0/16.0), vec3(11.0/16.0, 2.0/16.0, 10.0 / 16.0)),
           PackAABB(vec3(5.0/16.0, 0.0/16.0, 6.0/16.0).zyx, vec3(11.0/16.0, 2.0/16.0, 10.0 / 16.0).zyx) ),
    ivec4( PackAABB(vec3(5.0/16.0, 14.0/16.0, 6.0/16.0), vec3(11.0/16.0, 16.0/16.0, 10.0 / 16.0)),
           PackAABB(vec3(5.0/16.0, 14.0/16.0, 6.0/16.0).zyx, vec3(11.0/16.0, 16.0/16.0, 10.0 / 16.0).zyx),
           0,
           0 )
);

bool SubvoxelIntersect(int block_id, vec3 worldDir, inout vec3 fract_pos, out vec3 plane) {
    return IntersectAABB(fract_pos, worldDir, unpack_AABB(bounds[block_id/4][block_id%4]), plane);
}

VoxelIntersectOut VoxelIntersect(vec3 voxelPos, vec3 worldDir) {
    // http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.42.3443&rep=rep1&type=pdf
    
    ivec3 dir_pos = ivec3(max(sign(worldDir), 0));
    ivec3 uvPos = ivec3(voxelPos);
    ivec3 bound = uvPos + ivec3(dir_pos);
    
    ivec3 voxel_pos_0 = uvPos;
    vec3 fPos = fract(voxelPos);
    vec3 fPosMAD = fPos / worldDir;
    
    int lod = 0;
    int hit = 0;
    uint data;
    ivec2 voxel_coord;
    VoxelIntersectOut VIO;
    int steps = 0;
    
    uint chunk_addr = texelFetch(colortex3, old_get_sparse_chunk_coord(uvPos) + SPARSE0, 0).r;
    
    voxel_coord = get_sparse_voxel_coord(chunk_addr, uvPos, lod);
    data = texelFetch(voxel_data_tex, voxel_coord + DATA0, 0).x & 255;
    vec4 voxel_data = unpackUnorm4x8(data);
    int block_id = decode_block_id(data);
    if (data != 0 && is_sub_voxel(block_id) && SubvoxelIntersect(block_id, worldDir, fPos, VIO.plane)) {
        VIO.voxel_coord = voxel_coord;
        VIO.hit = true;
        VIO.voxelPos = voxelPos;
        return VIO;
    }
    
    while (true) {
        vec3 distToBoundary = (bound - voxel_pos_0) * (1.0 / worldDir) - fPosMAD;
        ivec3 uplane = GetMinCompMask(distToBoundary);
        
        ivec3 isPos = SortMinComp(dir_pos, uplane);
        
        int nearBound = GetMinComp(bound, uplane);
        
        ivec3 newPos;
        newPos.z = nearBound + isPos.z - 1;
        
        float tLength = BinaryDotF(distToBoundary, uplane);
        vec3 temp = fPos + worldDir * tLength;
        vec3 floorTemp = floor(temp);
        
        if ( lod < 0 || OutOfVoxelBounds(newPos.z, uplane) || ++steps > 256) { break; }
        
        newPos.xy = GetNonMinComps(ivec3(floorTemp) + voxel_pos_0, uplane);
        
        int oldPos = GetMinComp(uvPos, uplane);
        lod += int((newPos.z >> (lod+1)) != (oldPos >> (lod+1)));
        lod = min(lod, 4);
        uvPos = UnsortMinComp(newPos, uplane);
        chunk_addr = texelFetch(colortex3, old_get_sparse_chunk_coord(uvPos) + SPARSE0, 0).r;
        voxel_coord = get_sparse_voxel_coord(chunk_addr, uvPos, lod);
        uint data = 0;
        if (lod > 4 || chunk_addr != 0)
            data = texelFetch(voxel_data_tex, voxel_coord + DATA0, 0).x;
        hit = int(data != 0);
        lod -= hit;
        
        if (is_AABB(data)) {
            vec3 fract_pos = mix(temp - floorTemp, 1 - vec3(dir_pos), vec3(-uplane));
            int block_id = decode_block_id(data);
            
            if (!SimpleIntersectAABB(fract_pos, worldDir, unpack_AABB(bounds[block_id/4][block_id%4]))) {
                lod = 0;
                hit = 0;
            }
        }
        
        bound.xy  = ((newPos.xy >> lod) + isPos.xy) << lod;
        bound.z   = nearBound + ((hit-1) & ((isPos.z * 2 - 1) << lod));
        bound     = UnsortMinComp(bound, uplane);
    }
    
    VIO.voxel_coord = voxel_coord;
    VIO.hit = bool(hit);
    VIO.voxelPos = voxelPos + worldDir * MinComp((bound - voxel_pos_0) * (1.0 / worldDir) - fPosMAD, VIO.plane);
    VIO.plane *= sign(-worldDir);
    
    return VIO;
}

ivec2 atlasSize = ivec2(textureSize(atlas_tex, 0).xy);
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
uniform usampler2D noisetex;
#define sky_tex colortex15
uniform usampler2D sky_tex;
#include "../../includes/Sky.glsl"
/**********************************************************************/


void Something(vec3 voxelPos, uint packedVoxelData, vec4 diffuse, ivec2 texel_coord,
               vec4 tex_n, vec3 plane, inout RayStruct curr, inout uint qFront, inout uint qBack,
               inout int queue_size, inout int fetch, const uint flag) {
    // Create the new rays
    float hue = decode_hue(packedVoxelData);
    float sat = decode_sat(packedVoxelData);
    
    diffuse.rgb = pow(diffuse.rgb, vec3(2.2));
    diffuse.rgb *= HSVtoRGB(vec3(hue, sat, 1.0));
    
    vec4 tex_s = uintBitsToFloat(texelFetch(atlas_tex_s, texel_coord, 0));
    
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
    
#   if (defined MC_GL_VENDOR_NVIDIA)
    if (uint(ballotARB(true)) == uint(~0)) {
        fetch = 0;
        
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
#   endif
    
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
    int fetch = 1;
    while (queue_size > 0 && queue_size < ray_queue_cap && count++ < 1024) {
        if (fetch != 0) {
            qFront = RaybufferPopWarp();
            curr = UnpackBufferedRay(ReadBufferedRay(qFront));
        }
        
        fetch = 13;
        
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
            
            ivec2 voxel_coord = get_sparse_voxel_coord(texelFetch(voxel_data_tex, old_get_sparse_chunk_coord(ivec3(curr.voxelPos)), 0).r, ivec3(curr.voxelPos), 0);
            uint packedVoxelData = texelFetch(voxel_data_tex, voxel_coord + DATA0, 0).r;
            vec2 spriteSize = exp2(vec2(decode_sprite_size(packedVoxelData)));
            vec2 cornerTexcoord = floor(unpackUnorm2x16(texelFetch(voxel_data_tex, voxel_coord, 0).r) * atlasSize) / atlasSize;
            ivec2 texel_coord = ivec2(cornerTexcoord * atlasSize + tCoord * spriteSize);
            
            vec4 diffuse = uintBitsToFloat(texelFetch(atlas_tex, texel_coord, 0));
            
            if (diffuse.a < 0.1) { // Escape
                curr.voxelPos += fract_pos + -plane * exp2(-11);
                curr.info &= ~STENCIL_RAY_TYPE;
                WriteRay(qBack, curr);
            } else { // Hit
                if (IsSunlightRay(curr)) continue;
                if (GetRayDepth(curr) >= MAX_LIGHT_BOUNCES) continue;
                
                vec4 tex_n = uintBitsToFloat(texelFetch(atlas_tex_n, texel_coord, 0));
                
                Something(curr.voxelPos + fract_pos, packedVoxelData, diffuse, texel_coord,
                          tex_n, -plane, curr, qFront, qBack, queue_size, fetch, STENCIL_RAY_TYPE);
            }
            
            continue;
        } else if (IsParallaxRay(curr)) {
            vec3 pl = DecodePlane(curr.info >> 24);
            
            ivec2 voxel_coord = get_sparse_voxel_coord(texelFetch(voxel_data_tex, old_get_sparse_chunk_coord(ivec3(curr.voxelPos)), 0).r, ivec3(curr.voxelPos), 0);
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
            vec4 diffuse = uintBitsToFloat(texelFetch(atlas_tex, texel_coord, 0));
            diffuse.rgb = pow(diffuse.rgb, vec3(2.2));
            
            curr.absorb *= diffuse.rgb;
            curr.extra.xyz = tanPos;
            
            vec4 tex_n = uintBitsToFloat(texelFetch(atlas_tex_n, texel_coord, 0));
            vec4 tex_s = uintBitsToFloat(texelFetch(atlas_tex_s, texel_coord, 0));
            
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
                color += curr.absorb * vec3(1.0) * GetSunIrradiance(kPoint(VoxelToWorldSpace(VIO.voxelPos)), sunDirection) * (1.0 + 3.0 * float(GetRayDepth(curr) > 1));
            else
                color += ComputeTotalSky(VoxelToWorldSpace(VIO.voxelPos), curr.worldDir, curr.absorb, false);
            
            if (!(IsSunlightRay(curr) && VIO.hit))
                WriteColor(color, curr.screenCoord);
            
            continue;
        }
        
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
        
        vec4 diffuse = uintBitsToFloat(texelFetch(atlas_tex, texel_coord, 0));
        vec4 tex_n = uintBitsToFloat(texelFetch(atlas_tex_n, texel_coord, 0));
        
        
        if (is_emissive(blockID) && !IsSunlightRay(curr)) {
            float hue = decode_hue(packedVoxelData);
            float sat = decode_sat(packedVoxelData);
            
            vec3 diffuse2 = pow(diffuse.rgb, vec3(1.0));
            diffuse2 *= HSVtoRGB(vec3(hue, sat, 1.0));
            WriteColor(curr.absorb * diffuse2.rgb * 4.0, curr.screenCoord);
        }
        
        if (GetRayDepth(curr) >= MAX_LIGHT_BOUNCES)
            continue;
        
        // if (GetRayDepth(curr) == 0) {
        //     show(diffuse);
        //     exitCoord(curr.screenCoord);
        // }
        if (diffuse.a <= 0.1) { // Stencil
            // curr.info |= STENCIL_RAY_TYPE;
            // curr.voxelPos = VIO.voxelPos - VIO.plane * exp2(-12);
            // WriteRay(qBack, curr);
            
            // continue;
        } else if (diffuse.a < 1.0) { // Translucent
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
        
        // if (diffuse.a < 1.0) {
        //     WriteColor(curr.absorb * 4.0 * vec3(1.0, 0.5, 0.3), curr.screenCoord);
        // }
        
        // Create the new rays
        Something(VIO.voxelPos, packedVoxelData, diffuse, texel_coord, tex_n,
                  VIO.plane, curr, qFront, qBack, queue_size, fetch, 0);
    }
}
