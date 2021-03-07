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

#define VOXELIZATION_DISTANCE 1024

#define atlas_tex depthtex1
#define atlas_tex_n depthtex2
#define atlas_tex_s shadowtex1

#define sparse_data_tex0 colortex0
#define sparse_data_img0 colorimg0
#define sparse_data_tex1 colortex1
#define sparse_data_img1 colorimg1

#define voxel_data_img0 colorimg2
#define voxel_data_tex0 colortex2
#define voxel_data_img1 colorimg3
#define voxel_data_tex1 colortex3

const int sparse_chunk_map_size = 512;

const int sparse_voxel_buffer_width = 4096;

const int   const_voxel_radius     = int(VOXELIZATION_DISTANCE);
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
uint get_lod_base_addr(uint lod) {
    return ((const_voxel_volume*8) - ((const_voxel_volume*8) >> int(lod*3)))/7;
}

// Get the voxel offset from the lod base address
uint get_voxel_offset(uvec3 voxel_pos, uint lod) {
    voxel_pos   =  voxel_pos >> lod;
    voxel_pos.x = (voxel_pos.x * const_voxel_diameter) >>  lod     ;
    voxel_pos.y = (voxel_pos.y * const_voxel_area    ) >> (lod * 2);
    
    return voxel_pos.x + voxel_pos.y + voxel_pos.z;
}

// Get the complete voxel address for this position & lod level
uint get_voxel_addr(uvec3 voxel_pos, uint lod) {
    uint lod_base_addr = get_lod_base_addr(lod);
    uint voxel_offset  = get_voxel_offset(voxel_pos, lod);
    
    return lod_base_addr + voxel_offset;
}


ivec2 get_sparse_chunk_coord(uvec3 voxel_pos) {
    uint sparse_chunk_addr = get_voxel_offset(voxel_pos, 4);
    
    return ivec2(sparse_chunk_addr % sparse_chunk_map_size, sparse_chunk_addr / sparse_chunk_map_size);
}

uint get_sparse_chunk_addr(layout(r32ui) uimage2D chunk_addr_img, uvec3 voxel_pos) {
    ivec2 sparse_chunk_coord = get_sparse_chunk_coord(voxel_pos);
    
    return imageLoad(chunk_addr_img, sparse_chunk_coord).r;
}

uint get_sparse_chunk_addr(usampler2D chunk_addr_tex, uvec3 voxel_pos) {
    ivec2 sparse_chunk_coord = get_sparse_chunk_coord(voxel_pos);
    
    return texelFetch(chunk_addr_tex, sparse_chunk_coord, 0).r;
}

uint get_sub_chunk_lod_base_addr(uint lod) {
    if (lod == 0) return 0;
    if (lod == 1) return 16*16*16;
    if (lod == 2) return 16*16*16 + 8*8*8;
    if (lod == 3) return 16*16*16 + 8*8*8 + 4*4*4;
    if (lod == 4) return 16*16*16 + 8*8*8 + 4*4*4 + 2*2*2;
    
    return 0;
}

uint get_sub_chunk_voxel_offset(uvec3 voxel_pos, uint lod) {
    voxel_pos   = voxel_pos % 16;
    voxel_pos   = voxel_pos >> lod;
    voxel_pos.x = (voxel_pos.x * 16     ) >>  lod;
    voxel_pos.y = (voxel_pos.y * 16 * 16) >> (lod * 2);
    
    return voxel_pos.x + voxel_pos.y + voxel_pos.z;
}

uint get_sub_chunk_addr(uvec3 voxel_pos, uint lod) {
    return get_sub_chunk_lod_base_addr(lod) + get_sub_chunk_voxel_offset(voxel_pos, lod);
}

uint get_sparse_voxel_addr(layout(r32ui) uimage2D chunk_addr_img, uvec3 voxel_pos, uint lod) {
    uint chunk_mem_size = (16*16*16) + (8*8*8) + (4*4*4) + (2*2*2) + (1*1*1) + 7;
    
    uint chunk_addr    = get_sparse_chunk_addr(chunk_addr_img, voxel_pos);
    
    return get_sub_chunk_addr(voxel_pos, lod) + (chunk_addr * chunk_mem_size);
}

ivec2 get_sparse_voxel_coord(layout(r32ui) uimage2D chunk_addr_img, uvec3 voxel_pos, uint lod) {
    uint sparse_voxel_addr = get_sparse_voxel_addr(chunk_addr_img, voxel_pos, lod);
    
    return ivec2(sparse_voxel_addr % sparse_voxel_buffer_width, sparse_voxel_addr / sparse_voxel_buffer_width);
}

uint get_sparse_voxel_addr(usampler2D chunk_addr_tex, uvec3 voxel_pos, uint lod) {
    uint chunk_mem_size = (16*16*16) + (8*8*8) + (4*4*4) + (2*2*2) + (1*1*1) + 7;
    
    uint chunk_addr    = get_sparse_chunk_addr(chunk_addr_tex, voxel_pos);
    
    return get_sub_chunk_addr(voxel_pos, lod) + (chunk_addr * chunk_mem_size);
}

uint get_sparse_voxel_addr(uint chunk_addr, uvec3 voxel_pos, uint lod) {
    uint chunk_mem_size = (16*16*16) + (8*8*8) + (4*4*4) + (2*2*2) + (1*1*1) + 7;
    
    return get_sub_chunk_addr(voxel_pos, lod) + (chunk_addr * chunk_mem_size);
}

ivec2 get_sparse_voxel_coord(usampler2D chunk_addr_tex, uvec3 voxel_pos, uint lod) {
    uint sparse_voxel_addr = get_sparse_voxel_addr(chunk_addr_tex, voxel_pos, lod);
    
    return ivec2(sparse_voxel_addr % sparse_voxel_buffer_width, sparse_voxel_addr / sparse_voxel_buffer_width);
}

ivec2 get_sparse_voxel_coord(uint chunk_addr, uvec3 voxel_pos, uint lod) {
    uint sparse_voxel_addr = get_sparse_voxel_addr(chunk_addr, voxel_pos, lod);
    
    return ivec2(sparse_voxel_addr % sparse_voxel_buffer_width, sparse_voxel_addr / sparse_voxel_buffer_width);
}

bool OutOfVoxelBounds(uint point, uvec3 uplane) {
    uint comp = (uvec3(voxel_dimensions).x & uplane.x) | (uvec3(voxel_dimensions).y & uplane.y) | (uvec3(voxel_dimensions).z & uplane.z);
    return point >= comp;
}

#endif