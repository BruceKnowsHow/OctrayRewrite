uniform sampler2D depthtex0;
uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D colortex10;
uniform sampler2D colortex12;

uniform sampler2D noisetex;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferProjection;
uniform vec3 cameraPosition;
uniform vec3 sunDirection;
uniform vec2 viewSize;
uniform float frameTimeCounter;
uniform float far;
uniform int frameCounter;

vec2 texcoord = gl_FragCoord.xy / viewSize;

#include "../../includes/Debug.glsl"

#define sky_tex colortex11
uniform sampler3D sky_tex;
#include "../../includes/Sky.glsl"

#include "../../includes/Voxelization.glsl"
#include "../../BlockMappings.glsl"

uniform usampler2D voxel_data_tex;
layout (r32ui) uniform uimage2D voxel_data_img;
uniform  sampler2D atlas_tex      ;
uniform  sampler2D atlas_tex_n    ;
uniform  sampler2D atlas_tex_s    ;

#define RAND_SEED uint(uint(gl_FragCoord.x * gl_FragCoord.y) + uint(viewSize.x * viewSize.y) * frameCounter)
#include "../../includes/Random.glsl"

vec3 GetWorldSpacePosition(vec2 coord, float depth) {
    // coord.xy += (RandNext2F() - 0.5) / viewSize;
    
    vec4 pos = vec4(vec3(coord, depth) * 2.0 - 1.0, 1.0);
    pos = gbufferProjectionInverse * pos;
    pos /= pos.w;
    pos.xyz = mat3(gbufferModelViewInverse) * pos.xyz;
    
    return pos.xyz;
}

#include "../../includes/Raybuffer.glsl"
#include "../../includes/Pathtracing.glsl"

/**********************************************************************/

/* DRAWBUFFERS:8 */

void main() {
    float depth0 = texture(depthtex0, texcoord).x;
    
    vec3 worldPos = GetWorldSpacePosition(texcoord, depth0);
    vec3 worldDir = normalize(worldPos);
    vec3 voxelPos = WorldToVoxelSpace(worldPos);
    
    vec3 absorb = vec3(1.0);
    if (depth0 >= 1.0) {
        vec3 color = ComputeTotalSky(vec3(0.0), worldDir, absorb, true);
        WriteColor(color / 4.0, ivec2(gl_FragCoord.xy));
        exit();
        return;
    }
    
    // if (all(equal(ivec2(gl_FragCoord.xy), ivec2(0, 0)))) { gl_FragData[0] = vec4(0); exit(); return; }
    
    vec4 diffuse = texture(colortex6, texcoord);
    
    vec3 surfaceNormal = texture(colortex7, texcoord).rgb;
    vec4 tex_s = texture(colortex8, texcoord);
    vec3 flatNormal = texture(colortex10, texcoord).rgb;
    
    vec3 color = vec3(0.0);
    
    #define RASTER_ENGINE
    #ifdef RASTER_ENGINE
        RayStruct curr;
        curr.voxelPos = voxelPos + flatNormal * exp2(-11);
        curr.voxelPos = texture(colortex12, texcoord).rgb;
        
        curr.worldDir   = worldDir;
        curr.absorb     = pow(diffuse.rgb, vec3(2.2));
        curr.absorb     = HSVtoRGB(pow(RGBtoHSV(curr.absorb), vec3(1.0, 1.0, 1.0)));
        curr.info       = 1;
        curr.screenCoord = ivec2(gl_FragCoord.xy);
        
        RayStruct specRay = curr;
        RayStruct  ambRay = curr;
        RayStruct  sunRay = curr;
        
        specRay.info |= SPECULAR_RAY_TYPE;
        ambRay.info  |= AMBIENT_RAY_TYPE;
        sunRay.info  |= SUNLIGHT_RAY_TYPE;
        
        DoPBR(diffuse, surfaceNormal, flatNormal, tex_s, curr.worldDir, specRay, ambRay, sunRay);
        
        uint i;
        WriteBufferedRay(i, specRay);
        WriteBufferedRay(i, ambRay);
        WriteBufferedRay(i, sunRay);
    #else
        RayStruct curr;
        curr.voxelPos = WorldToVoxelSpace(vec3(0.0));
        curr.worldDir = worldDir;
        curr.absorb    = vec3(1.0);
        curr.info      = 0 | PRIMARY_RAY_TYPE;
        curr.screenCoord = ivec2(gl_FragCoord.xy);
        
        uint i;
        WriteBufferedRay(i, curr);
    #endif
    
    gl_FragData[0].rgb = color;
    
    exit();
}
