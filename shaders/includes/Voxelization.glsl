#if !defined VOXELIZATION_GLSL
#define VOXELIZATION_GLSL

/*
* This file contains everything related to voxel storage and reading.
* Voxelization happens in "voxel space": a positive-only (unsigned) space
* with XZ range [0, voxel_radius - 1] and Y range [0, 256]. Voxel space is
* positive-only because it makes voxel marching simpler.
*
* 3D voxel positions are linearized and stored at a 1D uint coordinate,
* which is basically the address into a big 1D array. This 1D coordinate is
* modulo-wrapped to fill up the 2D texture where the data actually goes.
*/

const float sunPathRotation = -40; // [-60 -55 -50 -45 -40 -35 -30 -25 -20 -15 -10 -5 0 5 10 15 20 25 30 35 40 45 50 55 60]

#define atlas_tex depthtex1
#define atlas_tex_n depthtex2
#define atlas_tex_s shadowtex1

const int chunk_map_width = 512;

#if MC_VERSION >= 11800
const int chunk_map_height = 768;
#else
const int chunk_map_height = 512;
#endif

#define SPARSE0 ivec2(512, 0)
#define DATA0 ivec2(1, 0)

#define voxel_data_img colorimg0
#define voxel_data_tex colortex0

// Voxel Bit Mask
const int VBM_block_id_start = 0;
const int VBM_block_id_size  = 8;
const int VBM_block_id_mask  = (1 << VBM_block_id_size) - 1;

const int VBM_AABB_bit = 1 << (VBM_block_id_size);

const int VBM_hue_start = VBM_block_id_size + 1;
const int VBM_hue_size  = 8;
const int VBM_hue_mask  = (1 << VBM_hue_size) - 1;

const int VBM_sat_start = VBM_hue_start + VBM_hue_size;
const int VBM_sat_size  = 8;
const int VBM_sat_mask  = (1 << VBM_sat_size) - 1;

const int VBM_sprite_size_start = VBM_sat_start + VBM_sat_size;
const int VBM_sprite_size_size  = 8;
const int VBM_sprite_size_mask  = (1 << VBM_sprite_size_size) - 1;

int decode_block_id(uint encoded) {
    return int(encoded & VBM_block_id_mask);
}

float decode_hue(uint encoded) {
    return float((encoded >> VBM_hue_start) & VBM_hue_mask) / 255.0;
}

float decode_sat(uint encoded) {
    return float((encoded >> VBM_sat_start) & VBM_sat_mask) / 255.0;
}

int decode_sprite_size(uint encoded) {
    return int((encoded >> VBM_sprite_size_start) & VBM_sprite_size_mask);
}

bool is_AABB(uint enc) {
    return (enc & VBM_AABB_bit) != 0;
}

bool IsConvexAABB(uint enc) {
    return is_AABB(enc);
}

#define VOXEL_BUFFER_HEIGHT 2048 // [1024 2048 4096 6144 8192 12288 16384]

const int sparse_voxel_buffer_width = 16384;
const int sparse_voxel_buffer_height = VOXEL_BUFFER_HEIGHT;
const int sparse_voxel_buffer_size = sparse_voxel_buffer_width * sparse_voxel_buffer_height;

#if MC_VERSION >= 11800
    #define WORLD_HEIGHT 384
    #define Y_SHIFT 64
#else
    #define WORLD_HEIGHT 256
    #define Y_SHIFT 0
#endif

const int   const_voxel_radius     = 1024;
const int   const_voxel_diameter   = 2 * const_voxel_radius;
const ivec3 const_voxel_dimensions = ivec3(const_voxel_diameter, WORLD_HEIGHT, const_voxel_diameter);

const int const_voxel_area   = const_voxel_dimensions.x * const_voxel_dimensions.z;
const int const_voxel_volume = const_voxel_dimensions.y * const_voxel_area;

int   voxel_radius     = int(min(const_voxel_radius, far + 16));
int   voxel_diameter   = 2 * voxel_radius;
ivec3 voxel_dimensions = ivec3(voxel_diameter, WORLD_HEIGHT, voxel_diameter);

int voxel_area   = voxel_dimensions.x * voxel_dimensions.z;
int voxel_volume = voxel_dimensions.y * voxel_area;

vec3 WorldToVoxelSpace(vec3 position) {
    vec3 WtoV = vec3(0.0);
    WtoV.y += cameraPosition.y + Y_SHIFT;
    WtoV.xz += voxel_radius + (cameraPosition.xz - floor(cameraPosition.xz/16.0)*16.0);
    return position + WtoV;
}

vec3 VoxelToWorldSpace(vec3 position) {
    vec3 WtoV = vec3(0.0);
    WtoV.y += cameraPosition.y + Y_SHIFT;
    WtoV.xz += voxel_radius + (cameraPosition.xz - floor(cameraPosition.xz/16.0)*16.0);
    return position - WtoV;
}


// Get the base address of all voxel data with this lod
int get_lod_base_addr(int lod) {
    return ((const_voxel_volume*8) - ((const_voxel_volume*8) >> int(lod*3)))/7;
}

// Get the voxel offset from the lod base address
int get_voxel_offset(ivec3 voxelPos, int lod) {
    voxelPos   =  voxelPos >> lod;
    voxelPos.x = (voxelPos.x * const_voxel_diameter) >>  lod     ;
    voxelPos.y = (voxelPos.y * const_voxel_area    ) >> (lod * 2);
    
    return voxelPos.x + voxelPos.y + voxelPos.z;
}

// Get the complete voxel address for this position & lod level
int get_voxel_addr(ivec3 voxelPos, int lod) {
    int lod_base_addr = get_lod_base_addr(lod);
    int voxel_offset  = get_voxel_offset(voxelPos, lod);
    
    return lod_base_addr + voxel_offset;
}

ivec2 old_get_sparse_chunk_coord(ivec3 voxelPos) {
    int sparse_chunk_addr = get_voxel_offset(voxelPos, 4);
    
    return ivec2(sparse_chunk_addr % chunk_map_width, sparse_chunk_addr / chunk_map_width);
}

int get_sub_chunk_lod_base_addr(int lod) {
    if (lod == 0) return 0;
    if (lod == 1) return 16*16*16;
    if (lod == 2) return 16*16*16 + 8*8*8;
    if (lod == 3) return 16*16*16 + 8*8*8 + 4*4*4;
    if (lod == 4) return 16*16*16 + 8*8*8 + 4*4*4 + 2*2*2;
    
    return 0;
}

int get_sub_chunk_voxel_offset(ivec3 voxelPos, int lod) {
    voxelPos   = voxelPos % 16;
    voxelPos   = voxelPos >> lod;
    voxelPos.x = (voxelPos.x * 16     ) >>  lod;
    voxelPos.y = (voxelPos.y * 16 * 16) >> (lod * 2);
    
    return voxelPos.x + voxelPos.y + voxelPos.z;
}

int get_sub_chunk_addr(ivec3 voxelPos, int lod) {
    return get_sub_chunk_lod_base_addr(lod) + get_sub_chunk_voxel_offset(voxelPos, lod);
}

const int chunk_mem_size = (16*16*16) + (8*8*8) + (4*4*4) + (2*2*2) + (1*1*1) + 7;

uint get_sparse_voxel_addr(uint chunk_addr, ivec3 voxelPos, int lod) {
    return chunk_addr * chunk_mem_size + get_sub_chunk_addr(voxelPos, lod);
}

ivec2 get_sparse_voxel_coord(uint chunk_addr, ivec3 voxelPos, int lod) {
    uint sparse_voxel_addr;
    
    if (lod > 4) {
        // sparse_voxel_addr = upper_lod_buffer_start + get_voxel_offset(voxelPos, lod) * 2 + get_lod_base_addr(lod);
        sparse_voxel_addr = (get_voxel_offset(voxelPos, lod) + get_lod_base_addr(lod) - get_lod_base_addr(5));
    } else {
        sparse_voxel_addr = 2 * get_sparse_voxel_addr(chunk_addr, voxelPos, lod) + get_lod_base_addr(8) - get_lod_base_addr(5);
    }
    
    return ivec2(sparse_voxel_addr % sparse_voxel_buffer_width, sparse_voxel_addr / sparse_voxel_buffer_width);
}

bool OutOfVoxelBounds(int point, ivec3 uplane) {
    int comp = (voxel_dimensions.x & uplane.x) | (voxel_dimensions.y & uplane.y) | (voxel_dimensions.z & uplane.z);
    return point >= comp || point < 0;
}

vec3 RGBtoHSV(vec3 c) {
    const vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 HSVtoRGB(vec3 c) {
    const vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

mat3 ArbitraryTBN(vec3 normal) {
	mat3 ret;
	ret[2] = normal;
	ret[0] = normalize(vec3(sqrt(2), sqrt(3), sqrt(5)));
	ret[1] = normalize(cross(ret[0], ret[2]));
	ret[0] = cross(ret[1], ret[2]);
	
	return ret;
}

ivec2 ScreenToVoxelBuffer(ivec2 screenCoord) {
    int linearized = (screenCoord.x + screenCoord.y * int(viewSize.x)) * 2;
    linearized = int(sparse_voxel_buffer_size - 1) - linearized;
    
    return ivec2(linearized % sparse_voxel_buffer_width, linearized / sparse_voxel_buffer_width);
}

#endif