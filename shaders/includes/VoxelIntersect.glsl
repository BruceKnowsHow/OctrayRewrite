uniform usampler2D voxel_data_tex0;
uniform  sampler2D atlas_tex      ;
uniform  sampler2D atlas_tex_n    ;
uniform  sampler2D atlas_tex_s    ;

struct VoxelIntersectOut {
    bool  hit  ;
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
    ivec3 b0 = (data >> ivec3(0, 5, 10)) & ((1 << 5) - 1);
    ivec3 b1 = (data >> ivec3(15, 20, 25)) & ((1 << 5) - 1);
    
    AABB aabb;
    aabb.minBounds = vec3(b0) / 16.0;
    aabb.maxBounds = vec3(b1) / 16.0;
    return aabb;
}

const ivec4 bounds[6] = ivec4[6](
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
    
    uint chunk_addr = texelFetch(sparse_data_tex0, get_sparse_chunk_coord(uvPos), 0).r;
    
    voxel_coord = get_sparse_voxel_coord(chunk_addr & chunk_addr_mask, uvPos, lod);
    data = texelFetch(voxel_data_tex0, voxel_coord + DATA0, 0).x & 255;
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
        lod = min(lod, 7);
        uvPos = UnsortMinComp(newPos, uplane);
        chunk_addr = texelFetch(sparse_data_tex0, get_sparse_chunk_coord(uvPos), 0).r;
        voxel_coord = get_sparse_voxel_coord(chunk_addr & chunk_addr_mask, uvPos, lod);
        uint data = 0;
        if (chunk_addr != 0)
            data = texelFetch(voxel_data_tex0, voxel_coord + DATA0, 0).x;
        hit = int(data != 0);
        lod -= hit;
        
        if (is_AABB(data)) {
            vec3 fract_pos = mix(temp - floorTemp, 1 - vec3(dir_pos), vec3(-uplane));
            int block_id = decode_block_id(data);
            
            if (!IntersectAABB(fract_pos, worldDir, unpack_AABB(bounds[block_id/4][block_id%4]))) {
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
