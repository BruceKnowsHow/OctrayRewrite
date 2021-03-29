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

#define atlas_tex depthtex1
#define atlas_tex_n depthtex2
#define atlas_tex_s shadowtex1

#define sparse_data_tex0 colortex0
#define sparse_data_img0 colorimg0

#define SPARSE0 ivec2(512, 0)
#define DATA0 ivec2(8192, 0)

#define voxel_data_img0 colorimg1
#define voxel_data_tex0 colortex1

// Voxel bit mask
const int VBM_block_id_start = 0;
const int VBM_block_id_size  = 8;
const int VBM_block_id_mask  = (1 << VBM_block_id_size) - 1;

const int VBM_AABB_bit = 1 << (VBM_block_id_size);

const int VMB_hue_start = VBM_block_id_start + 1;
const int VMB_hue_size  = 8;
const int VBM_hue_mask  = (1 << VMB_hue_size) - 1;

const int VMB_sat_start = VMB_hue_start + VMB_hue_size;
const int VMB_sat_size  = 8;
const int VBM_sat_mask  = (1 << VMB_sat_size) - 1;

int decode_block_id(uint encoded) {
    return int(encoded & VBM_block_id_mask);
}

float decode_hue(uint encoded) {
    return float((encoded >> VMB_hue_start) & VBM_hue_mask) / 255.0;
}

float decode_sat(uint encoded) {
    return float((encoded >> VMB_sat_start) & VBM_sat_mask) / 255.0;
}

bool is_AABB(uint encoded) {
    return (encoded & VBM_AABB_bit) != 0;
}

const int sparse_chunk_map_size = 512;

const int sparse_voxel_buffer_width = 4096;

const int   const_voxel_radius     = 1024;
const int   const_voxel_diameter   = 2 * const_voxel_radius;
const ivec3 const_voxel_dimensions = ivec3(const_voxel_diameter, 256, const_voxel_diameter);

const int const_voxel_area   = const_voxel_dimensions.x * const_voxel_dimensions.z;
const int const_voxel_volume = const_voxel_dimensions.y * const_voxel_area;

int   voxel_radius     = int(min(const_voxel_radius, far + 16));
int   voxel_diameter   = 2 * voxel_radius;
ivec3 voxel_dimensions = ivec3(voxel_diameter, 256, voxel_diameter);

int voxel_area   = voxel_dimensions.x * voxel_dimensions.z;
int voxel_volume = voxel_dimensions.y * voxel_area;

vec3 WorldToVoxelSpace(vec3 position) {
    vec3 WtoV = gbufferModelViewInverse[3].xyz;
    WtoV.y += cameraPosition.y;
    WtoV.xz += voxel_radius + (cameraPosition.xz - floor(cameraPosition.xz/16.0)*16.0);
    return position + WtoV;
}

// vec3 VoxelToWorldSpace(vec3 position) {
//     vec3 WtoV = vec2(0.0, floor(cameraPosition.y)).xyx + vec2(0.0, voxel_radius).yxy + gbufferModelViewInverse[3].xyz + fract(cameraPosition);
//     return position - WtoV;
// }


// Get the base address of all voxel data with this lod
int get_lod_base_addr(int lod) {
    return ((const_voxel_volume*8) - ((const_voxel_volume*8) >> int(lod*3)))/7;
}

// Get the voxel offset from the lod base address
int get_voxel_offset(ivec3 voxel_pos, int lod) {
    voxel_pos   =  voxel_pos >> lod;
    voxel_pos.x = (voxel_pos.x * const_voxel_diameter) >>  lod     ;
    voxel_pos.y = (voxel_pos.y * const_voxel_area    ) >> (lod * 2);
    
    return voxel_pos.x + voxel_pos.y + voxel_pos.z;
}

// Get the complete voxel address for this position & lod level
int get_voxel_addr(ivec3 voxel_pos, int lod) {
    int lod_base_addr = get_lod_base_addr(lod);
    int voxel_offset  = get_voxel_offset(voxel_pos, lod);
    
    return lod_base_addr + voxel_offset;
}


ivec2 get_sparse_chunk_coord(ivec3 voxel_pos) {
    int sparse_chunk_addr = get_voxel_offset(voxel_pos, 4);
    
    return ivec2(sparse_chunk_addr % sparse_chunk_map_size, sparse_chunk_addr / sparse_chunk_map_size);
}

int get_sub_chunk_lod_base_addr(int lod) {
    if (lod == 0) return 0;
    if (lod == 1) return 16*16*16;
    if (lod == 2) return 16*16*16 + 8*8*8;
    if (lod == 3) return 16*16*16 + 8*8*8 + 4*4*4;
    if (lod == 4) return 16*16*16 + 8*8*8 + 4*4*4 + 2*2*2;
    
    return 0;
}

int get_sub_chunk_voxel_offset(ivec3 voxel_pos, int lod) {
    voxel_pos   = voxel_pos % 16;
    voxel_pos   = voxel_pos >> lod;
    voxel_pos.x = (voxel_pos.x * 16     ) >>  lod;
    voxel_pos.y = (voxel_pos.y * 16 * 16) >> (lod * 2);
    
    return voxel_pos.x + voxel_pos.y + voxel_pos.z;
}

int get_sub_chunk_addr(ivec3 voxel_pos, int lod) {
    return get_sub_chunk_lod_base_addr(lod) + get_sub_chunk_voxel_offset(voxel_pos, lod);
}

const int chunk_mem_size = (16*16*16) + (8*8*8) + (4*4*4) + (2*2*2) + (1*1*1) + 7;

uint get_sparse_voxel_addr(uint chunk_addr, ivec3 voxel_pos, int lod) {
    return chunk_addr * chunk_mem_size + get_sub_chunk_addr(voxel_pos, lod);
}

const int ebinb = sparse_voxel_buffer_width * 11000 - get_lod_base_addr(5);

ivec2 get_sparse_voxel_coord(uint chunk_addr, ivec3 voxel_pos, int lod) {
    uint sparse_voxel_addr;
    
    if (lod > 4) {
        sparse_voxel_addr = ebinb + get_voxel_offset(voxel_pos, lod) + get_lod_base_addr(lod);
    } else {
        sparse_voxel_addr = get_sparse_voxel_addr(chunk_addr, voxel_pos, lod);
    }
    
    return ivec2(sparse_voxel_addr % sparse_voxel_buffer_width, sparse_voxel_addr / sparse_voxel_buffer_width);
}

bool OutOfVoxelBounds(int point, ivec3 uplane) {
    int comp = (voxel_dimensions.x & uplane.x) | (voxel_dimensions.y & uplane.y) | (voxel_dimensions.z & uplane.z);
    return point >= comp || point < 0;
}

#endif