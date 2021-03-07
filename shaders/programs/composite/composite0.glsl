uniform sampler2D depthtex0;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferProjection;
uniform vec3 cameraPosition;
uniform vec2 viewSize;
uniform float frameTimeCounter;
uniform float far;

int X = 8;
int Y = 8;
ivec2 Z = ivec2(X, Y);

vec2 texcoord = gl_FragCoord.xy / viewSize;
// vec2 texcoord = vec2(((ivec2(gl_FragCoord.xy) % Z) * Z + (ivec2(gl_FragCoord.xy) % (Z*Z)) / Z + (ivec2(gl_FragCoord.xy) / Z) * Z)) / viewSize;

vec3 GetWorldSpacePosition(vec2 coord, float depth) {
    vec4 pos = vec4(vec3(coord, depth) * 2.0 - 1.0, 1.0);
    pos = gbufferProjectionInverse * pos;
    pos /= pos.w;
    pos.xyz = mat3(gbufferModelViewInverse) * pos.xyz;
    
    return pos.xyz;
}

#include "../../includes/Voxelization.glsl"
#include "../../BlockMappings.glsl"

layout (rgba8) uniform image2D colorimg1;
layout (rgba8) uniform image2D colorimg4;

uniform usampler2D sparse_data_tex1;
uniform usampler2D voxel_data_tex0 ;
uniform usampler2D voxel_data_tex1 ;
uniform  sampler2D atlas_tex       ;

vec2 atlas_size = textureSize(atlas_tex, 0).xy;

struct VoxelMarchOut {
    uint  hit  ;
    vec3  vPos ;
    vec3  plane;
    uint  data;
    ivec2 vCoord;
    uint  steps;
};

#define BinaryDot(a, b) ((a.x & b.x) | (a.y & b.y) | (a.z & b.z))
#define BinaryMix(a, b, c) ((a & (~c)) | (b & c))

float BinaryDotF(vec3 v, uvec3 uplane) {
    uvec3 u = floatBitsToUint(v);
    return uintBitsToFloat(BinaryDot(u, uplane));
}

float MinComp(vec3 v, out vec3 minCompMask) {
    float minComp = min(v.x, min(v.y, v.z));
    minCompMask.xy = 1.0 - clamp((v.xy - minComp) * 1e35, 0.0, 1.0);
    minCompMask.z = 1.0 - minCompMask.x - minCompMask.y;
    return minComp;
}

uvec3 GetMinCompMask(vec3 v) {
    ivec3 ia = floatBitsToInt(v);
    ivec3 iCompMask;
    iCompMask.xy = ((ia.xy - ia.yx) & (ia.xy - ia.zz)) >> 31;
    iCompMask.z = (-1) ^ iCompMask.x ^ iCompMask.y;
    
    return uvec3(iCompMask);
}

uvec2 GetNonMinComps(uvec3 xyz, uvec3 uplane) {
    return BinaryMix(xyz.xz, xyz.yy, uplane.xz);
}

uint GetMinComp(uvec3 xyz, uvec3 uplane) {
    return BinaryDot(xyz, uplane);
}

uvec3 SortMinComp(uvec3 xyz, uvec3 uplane) {
    uvec3 ret;
    ret.xy = GetNonMinComps(xyz, uplane);
    ret.z  = xyz.x ^ xyz.y ^ xyz.z ^ ret.x ^ ret.y;
    return ret;
}

uvec3 UnsortMinComp(uvec3 uvw, uvec3 uplane) {
    uvec3 ret;
    ret.xz = BinaryMix(uvw.xy, uvw.zz, uplane.xz);
    ret.y = uvw.x ^ uvw.y ^ uvw.z ^ ret.x ^ ret.z;
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

const vec3 bounds_arr[11] = vec3[11](
    vec3(0.0, -0.5, 0.0), // Bottom Slab
    vec3(0.0, 0.5, 0.0), // Top Slab
    vec3(0.0, 0.0, 0.5), // Normal Stairs
    vec3(0.0, -0.5, 0.0), // Normal Stairs
    vec3(0.0, -1.0 / 8.0, 0.0), // Snow layer 1
    vec3(0.0, -2.0 / 8.0, 0.0), // Snow layer 1
    vec3(0.0, -3.0 / 8.0, 0.0), // Snow layer 1
    vec3(0.0, -4.0 / 8.0, 0.0), // Snow layer 1
    vec3(0.0, -5.0 / 8.0, 0.0), // Snow layer 1
    vec3(0.0, -6.0 / 8.0, 0.0), // Snow layer 1
    vec3(0.0, -7.0 / 8.0, 0.0) // Snow layer 1
);

// vec3[2](vec3(origin), vec3(normal), vec3(vec2(size), 0.0))
const vec3 plane_array[10][3] = vec3[10][3](
    vec3[3](vec3(0.5, 0.5, 0.5), vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0)), // Bottom Slab middle
    vec3[3](vec3(0.5, 0.5, 0.5), vec3(0.0, 0.0, 1.0), vec3(1.0, 1.0, 0.0)), // Normal stair horizontal face
    vec3[3](vec3(0.5, 0.5, 0.5), vec3(0.0, -1.0, 0.0), vec3(1.0, 1.0, 0.0)), // Top slab middle
    vec3[3](vec3(0.5, 1.0 / 8.0, 0.5), vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0)), // Snow layer 1
    vec3[3](vec3(0.5, 2.0 / 8.0, 0.5), vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0)), // Snow layer 2
    vec3[3](vec3(0.5, 3.0 / 8.0, 0.5), vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0)), // Snow layer 3
    vec3[3](vec3(0.5, 4.0 / 8.0, 0.5), vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0)), // Snow layer 4
    vec3[3](vec3(0.5, 5.0 / 8.0, 0.5), vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0)), // Snow layer 5
    vec3[3](vec3(0.5, 6.0 / 8.0, 0.5), vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0)), // Snow layer 6
    vec3[3](vec3(0.5, 7.0 / 8.0, 0.5), vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0)) // Snow layer 7
);

void get_subvoxel_data(int block_id, out int plane_index, out int plane_count, out int bounds_index, out int bounds_count) {
    plane_index = block_id - 5;
    plane_count = 0;
    
    if (block_id == 3) plane_index = 0, plane_count = 1, bounds_index = 0, bounds_count = 1; // Bottom Slab
    if (block_id == 4) plane_index = 2, plane_count = 1, bounds_index = 1, bounds_count = 1; // Top Slab
    if (block_id == 5) plane_index = 0, plane_count = 2, bounds_index = 0, bounds_count = 0; // Normal Stairs
}

const vec3 symmetry_vecs[8] = vec3[8](
    vec3( 1.0,  1.0,  1.0),
    vec3(-1.0,  1.0,  1.0),
    vec3( 1.0, -1.0,  1.0),
    vec3( 1.0,  1.0, -1.0),
    vec3(-1.0, -1.0,  1.0),
    vec3(-1.0,  1.0, -1.0),
    vec3( 1.0, -1.0, -1.0),
    vec3(-1.0, -1.0, -1.0)
);

const mat3 symmetry_mats[6] = mat3[6](
    mat3( 1.0,  0.0,  0.0,  0.0,  1.0,  0.0,  0.0,  0.0,  1.0), // ( x,  y,  z) 0
    mat3( 1.0,  0.0,  0.0,  0.0,  0.0,  1.0,  0.0,  1.0,  0.0), // ( x,  z,  y) 1
    mat3( 0.0,  1.0,  0.0,  1.0,  0.0,  0.0,  0.0,  0.0,  1.0), // ( y,  x,  z) 2
    mat3( 0.0,  1.0,  0.0,  0.0,  0.0,  1.0,  1.0,  0.0,  0.0), // ( y,  z,  x) 3
    mat3( 0.0,  0.0,  1.0,  1.0,  0.0,  0.0,  0.0,  1.0,  0.0), // ( z,  x,  y) 4
    mat3( 0.0,  0.0,  1.0,  0.0,  1.0,  0.0,  1.0,  0.0,  0.0) // ( z,  y,  x) 5
);

// (bound_start, bound_count, plane_start, plane_count)
// Negative bound_count signals an && operation over the bound, instead of an ||
// (int           , int           ,  (int, int),  (int, int))
const int block_indices_size = 10;
const ivec4 block_indices[block_indices_size] = ivec4[block_indices_size](
    ivec4(0, 1,    0, 1), // Bottom Slab
    ivec4(1, 1,    2, 1), // Top Slab
    ivec4(2, 2,    0, 2), // Normal Stair
    ivec4(4, 1,    3, 1), // Snow layer 1
    ivec4(5, 1,    4, 1), // Snow layer 2
    ivec4(6, 1,    5, 1), // Snow layer 3
    ivec4(7, 1,    6, 1), // Snow layer 4
    ivec4(8, 1,    7, 1), // Snow layer 5
    ivec4(9, 1,    8, 1), // Snow layer 6
    ivec4(10, 1,    9, 1) // Snow layer 7
);

uniform int frameCounter;
bool subvoxel_intersect(int block_id, vec3 world_dir, vec3 voxel_pos) {
    if (!is_sub_voxel(block_id)) return true;
    
    vec3 fract_pos = fract(voxel_pos);
    
    ivec2 symmetry_indices = ivec2(0, 0); // Comes from block texel data
    vec3 symmetry_vec = symmetry_vecs[symmetry_indices.x];
    mat3 symmetry_mat = symmetry_mats[symmetry_indices.y];
    
    fract_pos = (symmetry_mat * ((fract_pos * 2.0 - 1.0) * symmetry_vec)) * 0.5 + 0.5;
    world_dir =  symmetry_mat *  (world_dir * symmetry_vec);
    
    ivec4 block_ids = block_indices[(block_id - 3) % block_indices_size];
    
    int first_bound = block_ids[0];
    int bound_count = block_ids[1];
    int bound_end = first_bound + abs(bound_count);
    
    bool result = false;
    for (int bound_i = first_bound; bound_i < bound_end; ++bound_i) {
        vec3 bound = bounds_arr[bound_i];
        vec3 compare_pos = fract_pos * sign(bound);
        result = result || all(greaterThanEqual(compare_pos, bound));
    }
    if (result) return true;
    
    vec3  normal = vec3(0.0);
    
    float smallest_ray_len = 1e35;
    
    vec3 starting_voxel_pos = voxel_pos;
    
    int first_plane = block_ids[2];
    int plane_count = block_ids[3];
    int plane_end = first_plane + plane_count;
    
    for (int plane = first_plane; plane < plane_end; ++plane) {
        vec3 plane_origin = plane_array[plane][0];
        vec3 plane_normal = plane_array[plane][1];
        vec2 plane_size   = plane_array[plane][2].xy;
        vec2 plane_extent = plane_size / 2.0;
        
        float ray_len = dot(plane_origin - fract_pos, plane_normal) / dot(world_dir, plane_normal);
        
        vec3 hit_point = fract_pos + world_dir * ray_len;
        
        if (ray_len > 0 && ray_len < smallest_ray_len && all(lessThan(abs(hit_point - 0.5), vec3(0.5)))) {
            mat3 plane_tangent_mat = recover_tangent_mat(plane_normal);
            vec3 tangent_coord = ((hit_point * 2.0 - 1.0) * plane_tangent_mat);
            
            // gl_FragData[0].rgb = abs(fract_pos);
            
            tangent_coord = tangent_coord * 0.5 + 0.5;
            
            vec2 plane_coord = ((hit_point - plane_origin) * plane_tangent_mat).xy * 2.0;
            
            if (any(greaterThan(abs(plane_coord), plane_size))) continue;
            
            smallest_ray_len = ray_len;
            normal = plane_normal;
            voxel_pos = starting_voxel_pos + world_dir * smallest_ray_len + plane_tangent_mat[2] * exp2(-12);
        }
    }
    
    return smallest_ray_len != 1e35;
}

void subvoxel_intersect(int block_id, vec3 world_dir, vec2 corner_texcoord, vec2 sprite_scale,
    inout vec3 voxel_pos, inout mat3 tangent_mat, inout vec2 tCoord, inout bool hit)
{
    if (!is_sub_voxel(block_id)) return;
    
    vec3  fract_pos = fract(voxel_pos);
    
    ivec2 symmetry_indices = ivec2(0, 0); // Comes from block texel data
    vec3 symmetry_vec = symmetry_vecs[symmetry_indices.x];
    mat3 symmetry_mat = symmetry_mats[symmetry_indices.y];
    
    fract_pos = (symmetry_mat * ((fract_pos * 2.0 - 1.0) * symmetry_vec)) * 0.5 + 0.5;
    world_dir =  symmetry_mat *  (world_dir * symmetry_vec);
    
    
    ivec4 block_ids = block_indices[(block_id - 3) % block_indices_size];
    
    int first_bound = block_ids[0];
    int bound_count = block_ids[1];
    int bound_end = first_bound + abs(bound_count);
    
    bool result = false;
    for (int bound_i = first_bound; bound_i < bound_end; ++bound_i) {
        vec3 bound = bounds_arr[bound_i];
        vec3 compare_pos = fract_pos * sign(bound);
        result = result || all(greaterThanEqual(compare_pos, bound));
    }
    if (result) return;
    
    
    vec3  normal    = vec3(0.0);
    
    float smallest_ray_len = 1e35;
    
    vec3 starting_voxel_pos = voxel_pos;
    
    int first_plane = block_ids[2];
    int plane_count = block_ids[3];
    int plane_end = first_plane + plane_count;
    
    for (int plane = first_plane; plane < plane_end; ++plane) {
        vec3 plane_origin = plane_array[plane][0];
        vec3 plane_normal = plane_array[plane][1];
        vec2 plane_size   = plane_array[plane][2].xy;
        vec2 plane_extent = plane_size / 2.0;
        
        float ray_len = dot(plane_origin - fract_pos, plane_normal) / dot(world_dir, plane_normal);
        
        vec3 hit_point = fract_pos + world_dir * ray_len;
        
        if (ray_len > 0 && ray_len < smallest_ray_len && all(lessThan(abs(hit_point - 0.5), vec3(0.5)))) {
            mat3 plane_tangent_mat = recover_tangent_mat(plane_normal);
            vec3 tangent_coord = ((hit_point * 2.0 - 1.0) * plane_tangent_mat);
            
            tangent_coord = tangent_coord * 0.5 + 0.5;
            
            vec2 plane_coord = ((hit_point - plane_origin) * plane_tangent_mat).xy * 2.0;
            
            if (any(greaterThan(abs(plane_coord), plane_size))) continue;
            
            vec2 coord = plane_coord.xy * sprite_scale + corner_texcoord;
            
            // vec4 diffuse = textureLod(atlas_tex, coord, 0);
            vec4 diffuse = vec4(1);
            
            if (diffuse.a > 0.1) {
                smallest_ray_len = ray_len;
                normal = plane_normal;
                tangent_mat = plane_tangent_mat;
                tCoord = tangent_coord.xy;
                voxel_pos = starting_voxel_pos + world_dir * smallest_ray_len + tangent_mat[2] * exp2(-12);
            }
        }
    }
    
    hit = smallest_ray_len != 1e35;
}

VoxelMarchOut VoxelMarch(vec3 vPos, vec3 wDir) {
    // http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.42.3443&rep=rep1&type=pdf
    
    uvec3 dirIsPositive = uvec3(max(sign(wDir), 0));
    uvec3 boundary = uvec3(vPos) + dirIsPositive;
    uvec3 uvPos = uvec3(vPos);
    
    uvec3 vvPos = uvPos;
    vec3 fPos = fract(vPos);
    
    uint LOD = 0;
    uint hit = 1;
    uint data;
    ivec2 vCoord;
    VoxelMarchOut VMO;
    VMO.steps = 0;
    
    vCoord = get_sparse_voxel_coord(sparse_data_tex1, uvPos, LOD);
    data = texelFetch(voxel_data_tex1, vCoord, 0).x;
    vec4 voxel_data = unpackUnorm4x8(data);
    int block_id = int((1.0 - voxel_data.z) * 255.0);
    if (data != 0 && subvoxel_intersect(block_id, wDir, vPos)) {
        VMO.vCoord = vCoord;
        VMO.hit = 1;
        VMO.data = data;
        VMO.vPos = vPos;
        VMO.plane *= 0;
        return VMO;
    }
    
    while (true) {
        vec3 distToBoundary = (boundary - vPos) / wDir;
        uvec3 uplane = GetMinCompMask(distToBoundary);
        VMO.plane = vec3(-uplane);
        
        uvec3 isPos = SortMinComp(dirIsPositive, uplane);
        
        uint nearBound = GetMinComp(boundary, uplane);
        
        uvec3 newPos;
        newPos.z = nearBound + isPos.z - 1;
        
        if (LOD >= 8 ) {
            vec4 voxel_data = unpackUnorm4x8(data);
            int block_id = int((1.0 - voxel_data.z) * 255.0);
            
            if (!subvoxel_intersect(block_id, wDir, vPos + VMO.plane*sign(wDir) * exp2(-8) + float(VMO.steps>0)*wDir * MinComp((boundary - vPos) / wDir, VMO.plane))) {
                LOD = 0;
                hit = 0;
                float tLength = BinaryDotF(distToBoundary, uplane);
                newPos.xy = GetNonMinComps(ivec3(floor(fPos + wDir * tLength)) + vvPos, uplane);
                uvPos = UnsortMinComp(newPos, uplane);
                boundary.xy  = ((newPos.xy >> LOD) + isPos.xy) << LOD;
                boundary.z   = nearBound + ((isPos.z * 2 - 1) << LOD);
                boundary     = UnsortMinComp(boundary, uplane);
                ++VMO.steps;
                continue;
            }
        }
        
        if ( LOD >= 8 || OutOfVoxelBounds(newPos.z, uplane) || ++VMO.steps >= 512 ) { break; }
        
        float tLength = BinaryDotF(distToBoundary, uplane);
        newPos.xy = GetNonMinComps(ivec3(floor(fPos + wDir * tLength)) + vvPos, uplane);
        uint oldPos = GetMinComp(uvPos, uplane);
        uvPos = UnsortMinComp(newPos, uplane);
        
        // DEBUG_VM_ACCUM();
        // DEBUG_VM_ACCUM_LOD(LOD);
        
        LOD = (1-hit)*findMSB(newPos.z ^ oldPos)+(LOD*hit);
        LOD = min(LOD, 4);
        vCoord = get_sparse_voxel_coord(sparse_data_tex1, uvPos, LOD);
        data = texelFetch(voxel_data_tex1, vCoord, 0).x;
        hit = uint(data != 0);
        uint miss = 1-hit;
        LOD -= hit;
        
        boundary.xy  = ((newPos.xy >> LOD) + isPos.xy) << LOD;
        boundary.z   = nearBound + miss * ((isPos.z * 2 - 1) << LOD);
        boundary     = UnsortMinComp(boundary, uplane);
    }
    
    VMO.vCoord = vCoord;
    VMO.hit = hit;
    VMO.data = data;
    VMO.vPos = vPos + wDir * MinComp((boundary - vPos) / wDir, VMO.plane);
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

uniform sampler2D noisetex;

const int noiseTextureResolution = 8;

// uint randState = triple32(uint(texelFetch(noisetex, ivec2(texcoord*viewSize) % 8, 0).x*255) + uint(viewSize.x * viewSize.y) * frameCounter);
uint randState = triple32(uint(floor(gl_FragCoord.x/X)*X + viewSize.x * floor(gl_FragCoord.y/Y)*Y) + uint(viewSize.x * viewSize.y) * frameCounter);
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

#define RAY_BUFFER_CAPACITY 8
RayStruct ray_buffer[RAY_BUFFER_CAPACITY];

int ray_buffer_index = 0;

bool ray_buffer_full()  { return ray_buffer_index == RAY_BUFFER_CAPACITY; }
bool ray_buffer_empty() { return ray_buffer_index == 0; }

/* DRAWBUFFERS:9 */

void main() {
    if (texture(depthtex0, texcoord).x >= 1.0) {gl_FragData[0] = vec4(1); return; }
    
	vec3 world_dir = GetWorldSpacePosition(texcoord, 1);
    vec3 voxel_pos = WorldToVoxelSpace(vec3(0.0));
    
    VoxelMarchOut VMO = VoxelMarch(voxel_pos, world_dir);
	VMO.vPos -= VMO.plane * exp2(-12);
	vec2 corner_texcoord = floor(unpackUnorm2x16(texelFetch(voxel_data_tex0, VMO.vCoord, 0).r) * atlas_size) / atlas_size;
	vec2 tCoord = ((fract(VMO.vPos) * 2.0 - 1.0) * mat2x3(recover_tangent_mat(VMO.plane))) * 0.5 + 0.5;
	
	vec4 voxel_data = unpackUnorm4x8(texelFetch(voxel_data_tex1, VMO.vCoord, 0).r);
    int block_id = int((1.0 - voxel_data.z) * 255.0);
    vec4 diffuse = texture(atlas_tex, corner_texcoord + tCoord / atlas_size * 16.0);
    vec3 vertex_color = hsv_to_rgb(vec3(voxel_data.xy, 1.0));
	mat3 tangent_mat = recover_tangent_mat(VMO.plane);
    bool hit = true;
    
    if (is_sub_voxel(block_id)) {
        subvoxel_intersect(block_id, world_dir, corner_texcoord, 16.0 / atlas_size,
            VMO.vPos, tangent_mat, tCoord, hit);
        
        if (hit) {
            diffuse = texture(atlas_tex, corner_texcoord + (tCoord + vec2(0,-0 / 16.0)) / atlas_size * 16.0);
        }
    }
    
	gl_FragData[0] = diffuse * vec4(vertex_color, 1.0);
    
    if (bool(VMO.hit)) {
        vec3 sun_ray = normalize(vec3(0.5, 1.0, 0.3));
        sun_ray = recover_tangent_mat(VMO.plane) * CalculateConeVector(RandNextF(), radians(90.0), 32);
        
        VoxelMarchOut VMO2 = VoxelMarch(VMO.vPos + VMO.plane * exp2(-11), sun_ray);
        gl_FragData[0] *= (bool(VMO2.hit) ? 0.5 : 1.0);
    }
    
    imageStore(colorimg4, ivec2(texcoord*viewSize), gl_FragData[0]);
}
