#if !defined PARALLAX_GLSL
#define PARALLAX_GLSL

layout (r32ui) uniform uimage2D colorimg2;

vec3 MinComponent(vec3 a) {
    vec2 b = clamp(clamp((a.yz - a.xy), 0.0, 1.0) * (a.zx - a.xy) * 1e35, 0.0, 1.0);
    return vec3(b.x, b.y, 1.0 - b.x - b.y);
}

ivec2 get_POM_LOD_offset(int LOD) {
    ivec2 ret = ivec2(0);
    
    for (int i = 0; i < LOD; ++i) {
        ret.y += atlasSize.y >> i;
    }
    
    return ret;
}

ivec2 get_POM_coord(ivec2 coord, int LOD) {
    return (coord >> LOD) + get_POM_LOD_offset(LOD);
}

float GetTexelHeight(ivec2 coord, int lod, float sprite_size) {
    return mix(1.0, uintBitsToFloat(imageLoad(colorimg2, get_POM_coord(coord, lod)).r), sprite_size/4.0);
}

ivec2 Parallax(ivec2 corner, inout vec3 tangent_pos, vec3 tangent_ray, ivec2 sprite_size, inout vec3 normal, int LOD) {
    int lod = 0;
    
    if (tangent_ray.z >= 1) lod = 4;
    
    vec3 step_dir = sign(tangent_ray);
    vec3 dir_is_positive = max(step_dir, vec3(0.0));
    
    int steps = 0;
    
    vec3 boundary;
    vec3 uvPos;
    uvPos.xy = floor(tangent_pos.xy);
    uvPos.z = tangent_pos.z;
    boundary.xy = floor(uvPos.xy/exp2(lod))*exp2(lod) + (dir_is_positive.xy)*exp2(lod);
    
    while (++steps < 128) {
        if (tangent_ray.z > 0 && uvPos.z > 1.01 ) { return ivec2(0); }
        
        ivec2 C = ivec2(uvPos.xy + sprite_size * 8) % sprite_size;
        
        boundary.z = GetTexelHeight(corner + C, lod, sprite_size.x);
        
        vec3 dists = (boundary - tangent_pos) / tangent_ray;
        
        vec3 plane = MinComponent(dists);
        
        if (dists.z < 0.0) plane = MinComponent(vec3(dists.xy, 1000000.0));
        
        if (lod <= LOD && plane.z > 0.5) {
            if (-(uvPos.z - boundary.z) / tangent_ray.z >= 0.0) normal = plane;
            
            vec3  hit_points = boundary - step_dir * vec3(1.0, 1.0, 0.0);
            float hit_dist   = dot((hit_points - tangent_pos) / tangent_ray, normal);
            tangent_pos = mix(tangent_pos + tangent_ray * hit_dist, hit_points, normal);
            
            normal *= -step_dir;
            
            tangent_pos = tangent_pos + tangent_ray * dot(((boundary-step_dir*vec3(1,1,0)) - tangent_pos) / tangent_ray, normal) + normal * exp2(-8);
            
            return (corner + ivec2(uvPos.xy + sprite_size * 8) % sprite_size);
        } else if (plane.z > 0.5 || uvPos.z < boundary.z) {
            lod--;
        } else {
            int oldPos = int(dot(uvPos.xy, plane.xy));
            uvPos.xy = tangent_pos.xy + 1.0*tangent_ray.xy*dot(dists,plane) + step_dir.xy*plane.xy*exp2(-8);
            uvPos.z = tangent_pos.z + 1.0*tangent_ray.z*dot(dists,plane) + step_dir.z*exp2(-10);
            int newPos = int(dot(uvPos.xy, plane.xy));
            int shouldStepUp = int((newPos >> (lod+1)) != (oldPos >> (lod+1)));
            lod = min(lod + shouldStepUp, 4);
            normal = plane;
        }
        if (lod <= LOD && tangent_ray.z > 0 && uvPos.z < boundary.z) { return ivec2(0); }
        
        boundary.xy = floor(uvPos.xy / exp2(lod))*exp2(lod) + (dir_is_positive.xy )*exp2(lod);
    }
    
    return ivec2(0);
}

#endif