uniform sampler2D depthtex0;
uniform usampler2D colortex0;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferProjection;
uniform vec3 cameraPosition;
uniform vec2 viewSize;
uniform float frameTimeCounter;
uniform float far;
uniform int frameCounter;

vec2 texcoord = gl_FragCoord.xy / viewSize;

#include "../../includes/debug.glsl"

vec3 GetWorldSpacePosition(vec2 coord, float depth) {
    vec4 pos = vec4(vec3(coord, depth) * 2.0 - 1.0, 1.0);
    pos = gbufferProjectionInverse * pos;
    pos /= pos.w;
    pos.xyz = mat3(gbufferModelViewInverse) * pos.xyz;
    
    return pos.xyz;
}

#include "../../includes/Voxelization.glsl"
#include "../../BlockMappings.glsl"

uniform usampler2D voxel_data_tex0;
uniform  sampler2D atlas_tex      ;
uniform  sampler2D atlas_tex_n    ;
uniform  sampler2D atlas_tex_s    ;

vec2 atlas_size = textureSize(atlas_tex, 0).xy;

struct VoxelMarchOut {
    uint  hit  ;
    vec3  vPos ;
    vec3  plane;
    ivec2 vCoord;
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

mat3 recover_tangent_mat(vec3 plane) {
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

struct AABB {
    vec3 minBounds;
    vec3 maxBounds;
};

// Optimized AABB function that only does binary checks.
// Will erroniously find intersections which happen behind pos.
// Useful for the interior marching loop, which needs to be very fast.
bool IntersectAABB(vec3 pos, vec3 dir, AABB aabb) {
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

int pack_AABB(vec3 minBounds, vec3 maxBounds) {
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
    ivec3 b0 = (data >> ivec3(0, 5, 10)) & ((1 << 5) - 1);
    ivec3 b1 = (data >> ivec3(15, 20, 25)) & ((1 << 5) - 1);
    
    AABB aabb;
    aabb.minBounds = vec3(b0) / 16.0;
    aabb.maxBounds = vec3(b1) / 16.0;
    return aabb;
}

const ivec4 bounds[6] = ivec4[6](
    ivec4( pack_AABB(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0)),
           pack_AABB(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0)),
           pack_AABB(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0)),
           pack_AABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 0.5, 1.0)) ),
    ivec4( pack_AABB(vec3(0.0, 0.5, 0.0), vec3(1.0, 1.0, 1.0)),
           pack_AABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 0.5, 1.0)),
           pack_AABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 1.0/8.0, 1.0)),
           pack_AABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 2.0/8.0, 1.0)) ),
    ivec4( pack_AABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 3.0/8.0, 1.0)),
           pack_AABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 4.0/8.0, 1.0)),
           pack_AABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 5.0/8.0, 1.0)),
           pack_AABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 6.0/8.0, 1.0)) ),
    ivec4( pack_AABB(vec3(0.0, 0.0, 0.0), vec3(1.0, 7.0/8.0, 1.0)),
           pack_AABB(vec3(1.0/16.0, 0.0, 1.0/16.0), vec3(15.0/16.0, 1.0/16.0, 15.0 / 16.0)),
           pack_AABB(vec3(5.0/16.0, 6.0/16.0, 14.0/16.0), vec3(11.0/16.0, 10.0/16.0, 16.0 / 16.0)),
           pack_AABB(vec3(5.0/16.0, 6.0/16.0, 0.0/16.0), vec3(11.0/16.0, 10.0/16.0, 2.0 / 16.0)) ),
    ivec4( pack_AABB(vec3(5.0/16.0, 6.0/16.0, 0.0/16.0).zyx, vec3(11.0/16.0, 10.0/16.0, 2.0 / 16.0).zyx),
           pack_AABB(vec3(5.0/16.0, 6.0/16.0, 14.0/16.0).zyx, vec3(11.0/16.0, 10.0/16.0, 16.0 / 16.0).zyx),
           pack_AABB(vec3(5.0/16.0, 0.0/16.0, 6.0/16.0), vec3(11.0/16.0, 2.0/16.0, 10.0 / 16.0)),
           pack_AABB(vec3(5.0/16.0, 0.0/16.0, 6.0/16.0).zyx, vec3(11.0/16.0, 2.0/16.0, 10.0 / 16.0).zyx) ),
    ivec4( pack_AABB(vec3(5.0/16.0, 14.0/16.0, 6.0/16.0), vec3(11.0/16.0, 16.0/16.0, 10.0 / 16.0)),
           pack_AABB(vec3(5.0/16.0, 14.0/16.0, 6.0/16.0).zyx, vec3(11.0/16.0, 16.0/16.0, 10.0 / 16.0).zyx),
           0,
           0 )
);

bool subvoxel_intersect(int block_id, vec3 world_dir, inout vec3 fract_pos, out vec3 plane) {
    return IntersectAABB(fract_pos, world_dir, unpack_AABB(bounds[block_id/4][block_id%4]), plane);
}

VoxelMarchOut VoxelMarch(vec3 vPos, vec3 wDir) {
    // http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.42.3443&rep=rep1&type=pdf
    
    ivec3 dirIsPositive = ivec3(max(sign(wDir), 0));
    ivec3 uvPos = ivec3(vPos);
    ivec3 boundary = uvPos + ivec3(dirIsPositive);
    
    ivec3 vvPos = uvPos;
    vec3 fPos = fract(vPos);
    vec3 fPosMAD = fPos / wDir;
    
    int LOD = 0;
    int hit = 1;
    uint data;
    ivec2 vCoord;
    VoxelMarchOut VMO;
    int steps = 0;
    
    uint chunk_addr = texelFetch(sparse_data_tex0, get_sparse_chunk_coord(uvPos) + SPARSE0, 0).r;
    
    // vCoord = get_sparse_voxel_coord(sparse_data_tex1, uvPos, LOD);
    vCoord = get_sparse_voxel_coord(chunk_addr, uvPos, LOD);
    data = texelFetch(voxel_data_tex0, vCoord + DATA0, 0).x & 255;
    vec4 voxel_data = unpackUnorm4x8(data);
    int block_id = decode_block_id(data);
    if (data != 0 && is_sub_voxel(block_id) && subvoxel_intersect(block_id, wDir, fPos, VMO.plane)) {
        VMO.vCoord = vCoord;
        VMO.hit = 1;
        VMO.vPos = vPos;
        return VMO;
    }
    
    while (true) {
        vec3 distToBoundary = (boundary - vvPos) * (1.0 / wDir) - fPosMAD;
        ivec3 uplane = GetMinCompMask(distToBoundary);
        
        ivec3 isPos = SortMinComp(dirIsPositive, uplane);
        
        int nearBound = GetMinComp(boundary, uplane);
        
        ivec3 newPos;
        newPos.z = nearBound + isPos.z - 1;
        
        float tLength = BinaryDotF(distToBoundary, uplane);
        vec3 temp = fPos + wDir * tLength;
        vec3 floorTemp = floor(temp);
        
        if ( LOD < 0 || OutOfVoxelBounds(newPos.z, uplane) || ++steps > 256) { break; }
        
        // newPos.xy = GetNonMinComps(ivec3(temp) + (floatBitsToInt(temp) >> 31) + vvPos, uplane);
        newPos.xy = GetNonMinComps(ivec3(floorTemp) + vvPos, uplane);
        
        int oldPos = GetMinComp(uvPos, uplane);
        int shouldStepUp = int((newPos.z >> (LOD+1)) != (oldPos >> (LOD+1)));
        LOD = LOD + shouldStepUp;
        LOD = min(LOD, 7);
        uvPos = UnsortMinComp(newPos, uplane);
        // if (findMSB(newPos.z ^ oldPos) > 3)
            chunk_addr = texelFetch(sparse_data_tex0, get_sparse_chunk_coord(uvPos) + SPARSE0, 0).r;
        vCoord = get_sparse_voxel_coord(chunk_addr, uvPos, LOD);
        uint data = 0;
        if (chunk_addr != 0 || LOD > 4)
            data = texelFetch(voxel_data_tex0, vCoord + DATA0, 0).x;
        hit = int(data != 0);
        LOD -= hit;
        
        if (is_AABB(data)) {
            // vec3 fract_pos = fract(vec3(-uplane) * sign(wDir) * exp2(-12) + temp);
            vec3 fract_pos = mix(temp - floorTemp, 1-vec3(dirIsPositive), vec3(-uplane));
            int block_id = decode_block_id(data);
            
            if (!IntersectAABB(fract_pos, wDir, unpack_AABB(bounds[block_id/4][block_id%4]))) {
                LOD = 0;
                hit = 0;
            }
        }
        
        boundary.xy  = ((newPos.xy >> LOD) + isPos.xy) << LOD;
        boundary.z   = nearBound + ((hit-1) & ((isPos.z * 2 - 1) << LOD));
        boundary     = UnsortMinComp(boundary, uplane);
    }
    
    VMO.vCoord = vCoord;
    VMO.hit = uint(hit);
    VMO.vPos = vPos + wDir * MinComp((boundary - vvPos) * (1.0 / wDir) - fPosMAD, VMO.plane);
    VMO.plane *= sign(-wDir);
    
    return VMO;
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

uint triple32(uint x) {
    // https://nullprogram.com/blog/2018/07/31/
    x ^= x >> 17;
    x *= 0xed5ad4bbu;
    x ^= x >> 11;
    x *= 0xac4c1b51u;
    x ^= x >> 15;
    x *= 0x31848babu;
    x ^= x >> 14;
    return x;
}

float WangHash(uint seed) {
    seed = (seed ^ 61) ^ (seed >> 16);
    seed *= 9;
    seed = seed ^ (seed >> 4);
    seed *= 0x27d4eb2d;
    seed = seed ^ (seed >> 15);
    return float(seed) / 4294967296.0;
}

vec2 WangHash(uvec2 seed) {
    seed = (seed ^ 61) ^ (seed >> 16);
    seed *= 9;
    seed = seed ^ (seed >> 4);
    seed *= 0x27d4eb2d;
    seed = seed ^ (seed >> 15);
    return vec2(seed) / 4294967296.0;
}

uint randState = triple32(uint(uint(gl_FragCoord.x * gl_FragCoord.y) + uint(viewSize.x * viewSize.y) * frameCounter));
uint RandNext() { return randState = triple32(randState); }
uvec2 RandNext2() { return uvec2(RandNext(), RandNext()); }
uvec3 RandNext3() { return uvec3(RandNext2(), RandNext()); }
uvec4 RandNext4() { return uvec4(RandNext3(), RandNext()); }
float RandNextF() { return float(RandNext()) / float(0xffffffffu); }
vec2 RandNext2F() { return vec2(RandNext2()) / float(0xffffffffu); }
vec3 RandNext3F() { return vec3(RandNext3()) / float(0xffffffffu); }
vec4 RandNext4F() { return vec4(RandNext4()) / float(0xffffffffu); }

float RandF (uint  seed) { return float(triple32(seed))                    / float(0xffffffffu); }
vec2  Rand2F(uvec2 seed) { return vec2(triple32(seed.x), triple32(seed.y)) / float(0xffffffffu); }

vec3 CalculateConeVector(const float i, const float angularRadius, const int steps) {
    float x = i * 2.0 - 1.0;
    float y = i * float(steps) * 1.618 * 256.0;
    
    float angle = acos(x) * angularRadius / 3.14159;
    float s = sin(angle);

    return vec3(cos(y) * s, sin(y) * s, cos(angle));
}

struct RayStruct {
    vec3 voxel_pos;
    vec3 world_dir;
    vec3 absorb;
    uint info;
};

const uint  PRIMARY_RAY_TYPE = (1 <<  8);
const uint SUNLIGHT_RAY_TYPE = (1 <<  9);
const uint  AMBIENT_RAY_TYPE = (1 << 10);
const uint SPECULAR_RAY_TYPE = (1 << 11);

const uint RAY_DEPTH_MASK = (1 << 8) - 1;
const uint RAY_TYPE_MASK  = ((1 << 16) - 1) & (~RAY_DEPTH_MASK);
const uint RAY_ATTR_MASK  = ((1 << 24) - 1) & (~RAY_DEPTH_MASK) & (~RAY_TYPE_MASK);

bool is_ambient_ray (RayStruct ray) { return ((ray.info & AMBIENT_RAY_TYPE)  != 0); }
bool is_sunlight_ray(RayStruct ray) { return ((ray.info & SUNLIGHT_RAY_TYPE) != 0); }
bool is_primary_ray (RayStruct ray) { return ((ray.info & PRIMARY_RAY_TYPE)  != 0); }
bool is_specular_ray(RayStruct ray) { return ((ray.info & SPECULAR_RAY_TYPE) != 0); }

uint get_ray_depth(RayStruct ray) { return ray.info & RAY_DEPTH_MASK; }

struct PackedRayStruct {
    vec4 EBIN;
    vec4 DENIN;
};

PackedRayStruct pack_ray(RayStruct ray) {
    PackedRayStruct ret;
    
    return ret;
}

#define RAY_STACK_CAPACITY 4
RayStruct ray_stack[RAY_STACK_CAPACITY];

int ray_stack_top = 0;

bool ray_stack_full()  { return ray_stack_top == RAY_STACK_CAPACITY; }
bool ray_stack_empty() { return ray_stack_top == 0; }

bool ray_stack_overflow = false;

void ray_stack_push(RayStruct elem) {
    ray_stack_overflow = ray_stack_overflow || ray_stack_full();
    
    if (ray_stack_overflow)
        return;
    // if (!PassesVisibilityThreshold(elem.absorb)) { return;}
    
    ray_stack[ray_stack_top++] = elem;
}

RayStruct ray_pop() {
    return ray_stack[--ray_stack_top];
}

/* DRAWBUFFERS:9 */

void main() {
    float depth0 = texture(depthtex0, texcoord).x;
    
    if (depth0 >= 1.0) { gl_FragData[0] = vec4(0); exit(); return; }
    
    vec3 color = vec3(0.0);
    
    vec3 world_dir = normalize(GetWorldSpacePosition(texcoord, 1));
    vec3 voxel_pos = WorldToVoxelSpace(vec3(0.0));
    
    RayStruct first;
    first.voxel_pos = voxel_pos;
    first.world_dir = world_dir;
    first.absorb    = vec3(0.5);
    first.info      = 0 | PRIMARY_RAY_TYPE;
    
    ray_stack_push(first);
    
    int ray_count = 0;
    while (!ray_stack_empty() && ray_count++ < 4) {
        RayStruct curr = ray_pop();
        
        VoxelMarchOut VMO = VoxelMarch(curr.voxel_pos, curr.world_dir);
        
        
        if (!bool(VMO.hit)) {
            if (is_sunlight_ray(curr))
                color += curr.absorb * vec3(1.0);
            else
                color += curr.absorb * vec3(1.0);//ComputeTotalSky(VoxelToWorldSpace(VMO.vPos), curr.wDir, curr.absorb, IsPrimaryRay(curr)) * skyBrightness;
            
            continue;
        }
        
        if (is_sunlight_ray(curr))
            continue;
        
        
        uint packed_voxel_data = texelFetch(voxel_data_tex0, VMO.vCoord + DATA0, 0).r;
        int  block_id = decode_block_id(packed_voxel_data);
        float hue = decode_hue(packed_voxel_data);
        float sat = decode_sat(packed_voxel_data);
        
        vec2 corner_texcoord;
        vec2 tCoord;
        
        if (is_AABB(packed_voxel_data)) {
            vec3 fract_pos = fract(VMO.vPos - VMO.plane * exp2(-12));
            
            IntersectAABB(fract_pos, curr.world_dir, unpack_AABB(bounds[block_id/4][block_id%4]), VMO.plane);
            
            tCoord = (((fract_pos-vec3(0)) * 2.0 - 1.0) * mat2x3(recover_tangent_mat(VMO.plane))) * 0.5 + 0.5;
        } else {
            tCoord = ((fract(VMO.vPos) * 2.0 - 1.0) * mat2x3(recover_tangent_mat(VMO.plane))) * 0.5 + 0.5;
        }
        
        corner_texcoord = floor(unpackUnorm2x16(texelFetch(voxel_data_tex0, VMO.vCoord, 0).r) * atlas_size) / atlas_size;
        
        ivec2 texel_coord = ivec2(corner_texcoord*atlas_size + tCoord * 16.0);
        
        vec4 diffuse = texelFetch(atlas_tex, texel_coord, 0);
        diffuse.rgb = pow(diffuse.rgb, vec3(2.2));
        diffuse.rgb *= hsv_to_rgb(vec3(hue, sat, 1.0));
        
        mat3 tangent_mat = recover_tangent_mat(VMO.plane);
        
        vec4 tex_n = texelFetch(atlas_tex_n, texel_coord, 0);
        vec4 tex_s = texelFetch(atlas_tex_s, texel_coord, 0);
        
        vec3 normal;
        normal.xy = tex_n.xy * 2.0 - 1.0;
        normal.z = sqrt(1.0 - dot(normal.xy, normal.xy));
        
        normal = tangent_mat * normal;
        
        float roughness = 1.0 - tex_s.r;
        roughness *= roughness;
        
        // color += diffuse.rgb * curr.absorb;
        
        #define DO_SUNLIGHT_RAYS
        #define DO_AMBIENT_RAYS
        
        #ifdef DO_SUNLIGHT_RAYS
            curr.voxel_pos = VMO.vPos + VMO.plane * exp2(-11);
            curr.world_dir = normalize(vec3(0.5, 1.0, 0.3));
            curr.absorb    *= diffuse.rgb;
            curr.info      = (get_ray_depth(curr) + 1) | SUNLIGHT_RAY_TYPE;
            
            ray_stack_push(curr);
        #endif
        
        #ifdef DO_AMBIENT_RAYS
            curr.voxel_pos = VMO.vPos + VMO.plane * exp2(-11);
            curr.world_dir = tangent_mat * CalculateConeVector(RandNextF(), radians(60), 32);
            curr.absorb    *= diffuse.rgb;
            curr.info      = (get_ray_depth(curr) + 1) | AMBIENT_RAY_TYPE;
            
            ray_stack_push(curr);
        #endif
        
    }
    
    gl_FragData[0].rgb = color;
    
    exit();
}
