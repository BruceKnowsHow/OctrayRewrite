#if !defined PARALLAX_GLSL
#define PARALLAX_GLSL

layout (r32ui) uniform uimage2D colorimg2;

vec3 MinComponent(vec3 a) {
    vec2 b = clamp(clamp((a.yz - a.xy), 0.0, 1.0) * (a.zx - a.xy) * 1e35, 0.0, 1.0);
    return vec3(b.x, b.y, 1.0 - b.x - b.y);
}

vec2 MinComponent2(vec2 a) {
    return clamp((a.yx - a.xy) * 1e35, 0.0, 1.0);
    
    if (a.x < a.y) return vec2(1,0);
    return vec2(0,1);
}

float EncodeTangentPos(vec2 tanPos, vec2 spriteSize) {
    tanPos = clamp((tanPos / spriteSize + 0.5) / 2.0, 0.0, 1.0);
    uvec2 iv = uvec2(tanPos * exp2(16)) << uvec2(0, 16);
    return uintBitsToFloat(iv.y | iv.x);
}

vec2 DecodeTangentPos(float fenc, vec2 spriteSize) {
    uint enc = floatBitsToUint(fenc);
    uvec2 iv = uvec2(enc % (1 << 16), enc >> 16);
    return ((vec2(iv) * exp2(-16)) * 2.0 - 0.5) * spriteSize;
}

ivec2 get_POM_LOD_offset(int LOD) {
    ivec2 ret = ivec2(0);
    
    if (LOD > 1) ret.y += atlasSize.y >> 1;
    
    // for (int i = 1; i < LOD; ++i) {
    //     ret.y += atlasSize.y >> i;
    // }
    
    for (int i = 2; i < LOD; ++i) {
        int val = (atlasSize.y >> i); 
        ret.x += val + (val >> 1); // * 1.5
    }
    
    return ret;
}

ivec2 get_POM_coord(ivec2 coord, int LOD) {
    return (coord >> LOD) + get_POM_LOD_offset(LOD);
}

ivec2 SpriteCoord(vec2 tPos, ivec2 sprite_size) {
    return (ivec2(tPos) + sprite_size * 8) % sprite_size;
}

#define MAX_TEXTURE_RESOLUTION 256 // [256 512]

#if (MAX_TEXTURE_RESOLUTION >= 512)
// #define QUADTREE_POM
#endif

#ifdef QUADTREE_POM
const bool bool_quadtree_parallax = true;
#else
const bool bool_quadtree_parallax = false;
#endif

#define POM_DEPTH_MULT 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00 4.00]

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

// #define PARALLAX
#ifdef PARALLAX
const bool bool_parallax = true;
#else
const bool bool_parallax = false;
#endif

// #define POM_SILHOUETTE

// bool sideHit = tangent_pos.z  + tangent_ray.z *dot(dists,plane)*exp2(-16) < boundary.z;
#if (!defined composite3)

#define FloorL(x, y) (floor((x) * exp2(-(y))) * exp2(y))

float GetTexelHeight(ivec2 coord, int lod, float sprite_size) {
    float ret;
    
    #ifdef QUADTREE_POM
        if (lod == 0)
            ret = mix(1.0, uintBitsToFloat(texelFetch(atlas_tex_n, coord, 0).a), sprite_size/4.0 * POM_DEPTH_MULT * 0.75);
        else
            ret = mix(1.0, uintBitsToFloat(imageLoad(colorimg2, get_POM_coord(coord, lod)).r), sprite_size/4.0 * POM_DEPTH_MULT * 0.75);
    #else
        #if (!defined composite0) && (!defined composite3)
            ret = mix(1.0, uintBitsToFloat(texelFetch(atlas_tex_n, coord, 0).a), sprite_size/4.0 * POM_DEPTH_MULT * 0.75);
        #else
            ret = 1.0;
        #endif
    #endif
    
    return ret;
}

ivec2 LinearParallax(inout vec3 tangent_pos, vec3 tangent_ray, out vec3 normal, ivec2 corner, ivec2 sprite_size, int lodLimit) {
    vec3 step_dir = sign(tangent_ray);
    vec3 dir_is_positive = max(step_dir, vec3(0.0));
    
    if (tangent_pos.z > 1.0) {
        if (tangent_ray.z > 0) return ivec2(-10);
        tangent_pos = tangent_pos + tangent_ray * (1.0 - tangent_pos.z) / tangent_ray.z * 0.999999;
    }
    
    int steps = 0;
    
    vec3 boundary;
    vec3 tPos = tangent_pos;
    boundary.xy = floor(tPos.xy) + dir_is_positive.xy;
    vec2 prevDist;
    bool hit = false;
    
    while (++steps < 512) {
        float sampleHeight = GetTexelHeight(corner + SpriteCoord(tPos.xy, sprite_size), 0, sprite_size.x);
        
        if (tPos.z < sampleHeight) {
            vec2 prevPlane = MinComponent2(prevDist);
            normal = vec3(prevPlane, 0.0);
            tangent_pos = tangent_pos + tangent_ray*dot(prevDist, prevPlane);
            
            hit = true;
            break;
        }
        
        vec2 dists = (boundary.xy - tangent_pos.xy) / tangent_ray.xy;
        vec2 plane = MinComponent2(dists.xy);
        tPos.z = tangent_pos.z + tangent_ray.z * dot(dists.xy, plane);
        
        if (tPos.z < sampleHeight) {
            normal = vec3(0.0, 0.0, 1.0);
            tangent_pos = tangent_pos + tangent_ray * (sampleHeight - tangent_pos.z) / tangent_ray.z;
            
            hit = true;
            break;
        }
        
        // Escaped out the top.
        if (tPos.z > 1.0001) {
            tangent_pos = tangent_pos + tangent_ray * (1.0 - tangent_pos.z) / tangent_ray.z;
            break;
        }
        
        prevDist=dists;
        boundary.xy += plane.xy * step_dir.xy;
        tPos.xy += plane.xy * step_dir.xy;
    }
    
    if (hit) {
        normal *= -sign(tangent_ray);
        tangent_pos += normal * exp2(-10);
        return corner + SpriteCoord(floor(tangent_pos.xy - normal.xy * exp2(-9)), sprite_size);
    }
    
    return ivec2(-10);
}

// struct ParallaxOut {
//     bool  hit;
//     vec3  tangent_pos;
//     vec3  plane;
//     ivec2 texel_coord;
//     bvec2 overflow;
// };

ivec2 Parallax(inout vec3 tangent_pos, vec3 tangent_ray, out vec3 normal, ivec2 corner, ivec2 sprite_size, int lodLimit, bool edgeLimit) {
    if (!bool_quadtree_parallax)
        return LinearParallax(tangent_pos, tangent_ray, normal, corner, sprite_size, lodLimit);
    
    vec4 tDelta = vec4(tangent_ray.xy / tangent_ray.z, 1.0 / tangent_ray.xy);
    vec3 step_dir = sign(tangent_ray);
    vec3 dir_is_positive = max(step_dir, vec3(0.0));
    
    // if (!edgeLimit)
        tangent_pos.xy = mix(tangent_pos.xy + sprite_size * 1, tangent_pos.xy, dir_is_positive.xy);
    
    if (tangent_pos.z > 1.0) {
        if (tangent_ray.z > 0) { return ivec2(-10); }
        tangent_pos = tangent_pos + tangent_ray * (1.0 - tangent_pos.z) / tangent_ray.z * 0.999999;
    }
    
    int lod = (tangent_pos.z >= 1.0) ? 4 : 0;
    int steps = 0;
    
    
    vec3 initBound;
    vec2 tPos = tangent_pos.xy;
    vec2 boundary = FloorL(tPos, lod) + dir_is_positive.xy*exp2(lod);
    initBound.xy = FloorL(tPos, lod) + dir_is_positive.xy*exp2(lod);
    vec2 prevPlane = vec2(0.0);
    float sampleHeight = 1.0;
    
    while (++steps < 256) {
        sampleHeight = GetTexelHeight(corner + SpriteCoord(tPos, sprite_size), lod, sprite_size.x);
        
        // if ((edgeLimit) && (tPos.x < 0.0 || tPos.y < 0.0 || tPos.x >= sprite_size.x || tPos.y >= sprite_size.y)) {
        //     sampleHeight = 1.0;
        // }
        
        boundary = FloorL(tPos, lod) + dir_is_positive.xy*exp2(lod);
        vec2 dists = (boundary - tangent_pos.xy) * tDelta.zw;
        vec2 plane = MinComponent2(dists.xy);
        
        vec2 exi = tangent_pos.xy + tDelta.xy * (sampleHeight - tangent_pos.z);
        
        vec2 backAxis = plane;
        vec2 boundAxis = boundary;
        if (tangent_ray.z > 0.0) {
            backAxis = prevPlane;
            boundAxis = boundary - step_dir.xy*exp2(lod);
        }
        
        // Escaped out the top.
        if (tangent_pos.z + tangent_ray.z * dot((boundAxis.xy - tangent_pos.xy) * tDelta.zw, plane) > 1.000001) {
            lod = 100;
            break;
        }
        
        if (dot(backAxis, (exi.xy - boundAxis)*step_dir.xy*step_dir.z) > 0) {
            normal = vec3(prevPlane, 0.0);
            
            int oldLod = lod;
            
            if (oldLod > 0) {
                lod--;
            }
            
            if (tangent_ray.z < 0.0 && (dot(prevPlane, (exi.xy - (boundary - step_dir.xy*exp2(lod)))*step_dir.xy*step_dir.z) < 0.0)) {
                normal.xy = vec2(0.0, 0.0);
            }
            
            if (oldLod > 0) {
                if (normal.x + normal.y < 0.5) {
                    tPos = tangent_pos.xy + tDelta.xy*(sampleHeight - tangent_pos.z);
                }
                
                continue;
            } else {
                lod = 42;
                break;
            }
        }
        
        int oldPos = int(dot(tPos, plane.xy));
        
        tPos  = tangent_pos.xy + tangent_ray.xy*dot(dists,plane);
        tPos  = mix(tPos, boundary, plane);
        tPos += step_dir.xy*exp2(-11);
        
        int newPos = int(dot(tPos, plane.xy));
        int shouldStepUp = int((newPos >> (lod+1)) != (oldPos >> (lod+1)));
        lod = min(lod + shouldStepUp, 4);
        
        prevPlane = plane;
    }
    
    if (lod == 42) {
        normal.z = 1.0 - normal.x - normal.y;
        if (normal.z > 0.5) {
            tangent_pos = tangent_pos + tangent_ray*(sampleHeight - tangent_pos.z)/tangent_ray.z - step_dir*exp2(-11);
        } else {
            tangent_pos = tangent_pos + tangent_ray*dot(((boundary-step_dir.xy) - tangent_pos.xy)/tangent_ray.xy, prevPlane) - step_dir*exp2(-11);
        }
        lod = 0;
    }
    
    // if (!edgeLimit)
        tangent_pos.xy = mix(tangent_pos.xy - sprite_size * 1, tangent_pos.xy, dir_is_positive.xy);
    
    if (lod == 0) {
        normal.z = 1.0 - normal.x - normal.y;
        normal *= -sign(tangent_ray);
        tangent_pos += normal * exp2(-10);
        return corner + SpriteCoord(floor(tangent_pos.xy - normal.xy * exp2(-9)), sprite_size);
    } else if (lod == 100) {
        tangent_pos = tangent_pos + tangent_ray * (1.0 - tangent_pos.z) / tangent_ray.z;
    } else {
        normal = vec3(0.0);
    }
    
    return ivec2(-10);
}

#endif

#endif