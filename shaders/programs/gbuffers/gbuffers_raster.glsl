uniform float far;
uniform vec3 cameraPosition;
uniform vec2 viewSize;

#include "../../BlockMappings.glsl"
#include "../../includes/Voxelization.glsl"

layout (r32ui) uniform uimage2D voxel_data_img;
layout (r32ui) uniform uimage2D colorimg3;

/**********************************************************************/
#if defined vsh

attribute vec4 at_tangent;
attribute vec3 mc_Entity;
attribute vec2 mc_midTexCoord;

uniform sampler2D tex;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;

uniform vec3 previousCameraPosition;
ivec2 atlasSize = ivec2(textureSize(tex, 0).xy);

uniform float frameTimeCounter;
uniform int frameCounter;
uniform bool accum;

#include "../../includes/Random.glsl"


#define tanMat _tanMat
#define vertexColor _vertexColor
#define worldPos _worldPos
#define viewPos _viewPos
#define voxelPos _voxelPos
#define midTexcoord _midTexcoord
#define cornerTexcoord _cornerTexcoord
#define texcoord _texcoord
#define spriteSize _spriteSize
#define blockID _blockID

out mat3 tanMat;
out vec4 vertexColor;
out vec3 worldPos;
out vec3 viewPos;
out vec3 voxelPos;
flat out vec2 midTexcoord;
flat out vec2 cornerTexcoord;
out vec2 texcoord;
flat out ivec2 spriteSize;
flat out int blockID;
flat out ivec3 ivoxelPos;
flat out uint packed_tex_coord;
flat out uint packedVoxelData;

// Returns the tangent to world space matrix
mat3 GetTangentMat() {
    // World-space normal matrix
    mat3 normal_mat = mat3(gbufferModelViewInverse) * gl_NormalMatrix;
    
    vec3 tangent  = normalize(normal_mat * at_tangent.xyz);
    vec3 normal   = normalize(normal_mat *  gl_Normal.xyz);
    vec3 binormal = normalize(cross(tangent, normal));
    
    return mat3(tangent, binormal, normal);
}

void main() {
    vertexColor    = gl_Color;
    texcoord       = gl_MultiTexCoord0.xy;
    tanMat         = GetTangentMat();
    blockID        = backport_id(int(mc_Entity.x)) % 256;
    midTexcoord    = mc_midTexCoord;
    cornerTexcoord = mc_midTexCoord.xy - abs(mc_midTexCoord.xy - texcoord);
    vec2 texDirection = sign(texcoord - mc_midTexCoord)*vec2(1,sign(at_tangent.w));
    worldPos    = (gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 triCentroid = worldPos.xyz - (tanMat * vec3(texDirection,0.0)) - tanMat[2] / 32.0;
    triCentroid = mix(worldPos, triCentroid, 0.5);
    voxelPos    = WorldToVoxelSpace(mix(worldPos, triCentroid, exp2(-11))) + tanMat[2] * exp2(-11);
    // worldPos = mix(worldPos, triCentroid, -0.2);
    viewPos     = (gbufferModelView * vec4(worldPos, 1.0)).xyz;
    
    gl_Position = gbufferProjection * vec4(viewPos, 1.0);
    gl_Position.xy += TAAHash() * gl_Position.w;
    
    if (!is_voxelized(blockID))
        return;
    
    if (((blockID == 3
      || blockID == 4
      || (blockID >=  6 && blockID <= 12)) && abs(tanMat[2].y) < 0.9) // Snow layers
      || ((blockID >= 14 && blockID <= 21) && abs(tanMat[2].y) < 0.9)
    )
        return;
    
    if (blockID == 5 && (abs(tanMat[2]).y < 0.9 || abs(fract(WorldToVoxelSpace(triCentroid).y) - 0.5) > 0.1 ))
        return;
    
    spriteSize = ivec2(exp2(round(log2(abs(midTexcoord - texcoord) * 2.0 * atlasSize))));
    
    ivoxelPos = ivec3(WorldToVoxelSpace(triCentroid));
    
    // Store into chunk bitmap so that this chunk will be allocated next frame.
    imageStore(colorimg3, old_get_sparse_chunk_coord(ivoxelPos), uvec4(1));
    
    // Allocate extra chunks along the movement vector.
    // This prevents flickering when stepping over chunk borders.
    vec2 chunkGrow = 16.0 * sign(previousCameraPosition.xz - cameraPosition.xz);
    imageStore(colorimg3, old_get_sparse_chunk_coord(ivoxelPos + ivec3(chunkGrow.x, 0, 0)), uvec4(1));
    imageStore(colorimg3, old_get_sparse_chunk_coord(ivoxelPos + ivec3(0, 0, chunkGrow.y)), uvec4(1));
    
    uint chunkAddr = imageLoad(colorimg3, old_get_sparse_chunk_coord(ivoxelPos) + SPARSE0).r;
    bool allocFlag = chunkAddr != 0;
    if (!allocFlag)
        return;
    
    // Store all of its data into the sparse texture
    packed_tex_coord = packUnorm2x16(cornerTexcoord);
    
    vec2 hueSat           = RGBtoHSV(vertexColor.rgb).rg;
    packedVoxelData = 0;
    packedVoxelData |= blockID;
    packedVoxelData |= int(clamp(hueSat.r, 0.0, 1.0) * 255.0) << VBM_hue_start;
    packedVoxelData |= int(clamp(hueSat.g, 0.0, 1.0) * 255.0) << VBM_sat_start;
    packedVoxelData |= int(round(log2(spriteSize.x))) << VBM_sprite_size_start;
    if (is_sub_voxel(blockID)) packedVoxelData |= VBM_AABB_bit;
    
    ivec2 chunkCoord = get_sparse_voxel_coord(chunkAddr, ivoxelPos, 0);
    
    imageAtomicMax(voxel_data_img, chunkCoord, packed_tex_coord);
    imageAtomicMax(voxel_data_img, chunkCoord + DATA0, packedVoxelData);
    
    for (int lod = 1; lod <= 4; ++lod) {
        chunkCoord = get_sparse_voxel_coord(chunkAddr, ivoxelPos, lod);
        imageStore(voxel_data_img, chunkCoord + DATA0, uvec4(1));
    }
}

#endif
/**********************************************************************/

/**********************************************************************/
#if defined fsh

uniform sampler2D tex;
uniform usampler2D normals;
uniform sampler2D specular;
uniform sampler2D noisetex;

#undef atlas_tex_n
#define atlas_tex_n normals

uniform int frameCounter;
uniform float frameTimeCounter;

uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;

ivec2 atlasSize = ivec2(textureSize(tex, 0).xy);

in mat3 _tanMat;
in vec4 _vertexColor;
in vec3 _worldPos;
in vec3 _viewPos;
in vec3 _voxelPos;
in vec2 _texcoord;
flat in vec2 _cornerTexcoord;
flat in ivec2 _spriteSize;
flat in int _blockID;
flat in ivec3 ivoxelPos;
flat in uint packed_tex_coord;
flat in uint packedVoxelData;

#include "../../includes/debug.glsl"

float EncodeNormal(vec3 normal) {
    const float bits = 11.0;
    
	normal    = clamp(normal, -1.0, 1.0);
	normal.xy = vec2(atan(normal.x, normal.z), acos(normal.y)) / 3.14159;
	normal.x += 1.0;
	normal.xy = round(normal.xy * exp2(bits));
	
	return normal.x + normal.y * exp2(bits + 2.0);
}

#include "../../includes/Parallax.glsl"

#ifdef PARALLAX
/* RENDERTARGETS:6,7,12 */
#else
/* RENDERTARGETS:6,7 */
#endif


uint GetVoxelData(ivec3 voxelPos) {
    uint chunkAddr = imageLoad(colorimg3, old_get_sparse_chunk_coord(voxelPos) + SPARSE0).r;
    
    if (chunkAddr == 0)
        return -1;
    
    ivec2 voxelCoord = get_sparse_voxel_coord(chunkAddr, voxelPos, 0);
    return imageLoad(voxel_data_img, voxelCoord).x;
}

ivec2 GetVoxelCoord(ivec3 voxelPos) {
    uint chunkAddr = imageLoad(colorimg3, old_get_sparse_chunk_coord(voxelPos) + SPARSE0).r;
    return get_sparse_voxel_coord(chunkAddr, voxelPos, 0);
}


#define TIME 0.0
#define WAVE_SPEED 1.0
#define WAVE_MULT 1.0

const int noiseTextureResolution = 64; // [16 32 64 128 256 512 1024]
const float noiseRes = float(noiseTextureResolution);
const float noiseResInverse = 1.0 / noiseRes;
const float noiseScale = 64.0 / noiseRes;


#define cubesmooth(x) ((x) * (x) * (3.0 - (x)*2.0))

float GetWaveCoord(float coord) {
    const float madd = 0.5 * noiseResInverse;
    float whole = floor(coord);
    coord = whole + cubesmooth(coord - whole);
    
    return coord * noiseResInverse + madd;
}

vec2 GetWaveCoord(vec2 coord) {
    const vec2 madd = vec2(0.5 * noiseResInverse);
    vec2 whole = floor(coord);
    coord = whole + cubesmooth(coord - whole);
    
    return coord * noiseResInverse + madd;
}

float SharpenWave(float wave) {
    wave = 1.0 - abs(wave * 2.0 - 1.0);
    
    return wave < 0.78 ? wave : (wave * -2.5 + 5.0) * wave - 1.6;
}

const vec4 heights = vec4(29.0, 15.0, 17.0, 4.0);
const vec4 height = heights * WAVE_MULT / (heights.x + heights.y + heights.z + heights.w);

const vec2[4] scale = vec2[4](
    vec2(0.0065, 0.0052  ) * noiseRes * noiseScale,
    vec2(0.013 , 0.00975 ) * noiseRes * noiseScale,
    vec2(0.0195, 0.014625) * noiseRes * noiseScale,
    vec2(0.0585, 0.04095 ) * noiseRes * noiseScale);

const vec4 stretch = vec4(
    scale[0].x * -1.7 ,
    scale[1].x * -1.7 ,
    scale[2].x *  1.1 ,
    scale[3].x * -1.05);

mat4x2 waveTime = mat4x2(0.0);

void SetupWaveFBM() {
    const vec2 disp1 = vec2(0.04155, -0.0165   ) * noiseRes * noiseScale;
    const vec2 disp2 = vec2(0.017  , -0.0469   ) * noiseRes * noiseScale;
    const vec2 disp3 = vec2(0.0555 ,  0.03405  ) * noiseRes * noiseScale;
    const vec2 disp4 = vec2(0.00825, -0.0491625) * noiseRes * noiseScale;
    
    float w = TIME * WAVE_SPEED * 0.6;
    
    waveTime[0] = w * disp1;
    waveTime[1] = w * disp2;
    waveTime[2] = w * disp3;
    waveTime[3] = w * disp4;
}

float GetWaves(vec2 coord, inout mat4x2 c) {
	float waves = 0.0;
	vec2 ebin;
	
	c[0].xy = coord * scale[0] + waveTime[0];
	c[0].y = coord.x * stretch[0] + c[0].y;
	ebin = GetWaveCoord(c[0].xy);
	c[0].x = ebin.x;
	
	waves += SharpenWave(texture2D(noisetex, ebin).x) * height.x;
	
	c[1].xy = coord * scale[1] + waveTime[1];
	c[1].y = coord.x * stretch[1] + c[1].y;
	ebin = GetWaveCoord(c[1].xy);
	c[1].x = ebin.x;
	
	waves += texture2D(noisetex, ebin).x * height.y;
	
	c[2].xy = coord * scale[2] + waveTime[2];
	c[2].y = coord.x * stretch[2] + c[2].y;
	ebin = GetWaveCoord(c[2].xy);
	c[2].x = ebin.x;
	
	waves += texture2D(noisetex, ebin).x * height.z;
	
	c[3].xy = coord * scale[3] + waveTime[3];
	c[3].y = coord.x * stretch[3] + c[3].y;
	ebin = GetWaveCoord(c[3].xy);
	c[3].x = ebin.x;
	
	waves += texture2D(noisetex, ebin).x * height.w;
	
	return waves;
}

float GetWaves(vec2 coord) {
	mat4x2 c;
	
	return GetWaves(coord, c);
}

float GetWaves(mat4x2 c, float offset) {
	float waves = 0.0;
	
	c[0].y = GetWaveCoord(offset * scale[0].y + c[0].y);
	
	waves += SharpenWave(texture2D(noisetex, c[0].xy).x) * height.x;
	
	c[1].y = GetWaveCoord(offset * scale[1].y + c[1].y);
	
	waves += texture2D(noisetex, c[1].xy).x * height.y;
	
	c[2].y = GetWaveCoord(offset * scale[2].y + c[2].y);
	
	waves += texture2D(noisetex, c[2].xy).x * height.z;
	
	c[3].y = GetWaveCoord(offset * scale[3].y + c[3].y);
	
	waves += texture2D(noisetex, c[3].xy).x * height.w;
	
	return waves;
}

vec2 GetWaveDifferentials(vec2 coord, float scale) { // Get finite wave differentials for the world-space X and Z coordinates
	mat4x2 c;
	
	float a  = GetWaves(coord, c);
	float aX = GetWaves(coord + vec2(scale,   0.0));
	float aY = GetWaves(c, scale);
	
	return a - vec2(aX, aY);
}

vec3 ComputeWaveNormals(vec3 worldSpacePosition, vec3 flatWorldNormal) {
	if (WAVE_MULT == 0.0) return vec3(0.0, 0.0, 1.0);
	
	SetupWaveFBM();
	
	float angleCoeff  = dot(normalize(-_worldPos.xyz), normalize(flatWorldNormal));
	      angleCoeff /= clamp(length(_worldPos) * 0.05, 1.0, 10.0);
	      angleCoeff  = clamp(angleCoeff * 2.5, 0.0, 1.0);
	      angleCoeff  = sqrt(angleCoeff);
	
	vec3 worldPos    = _worldPos + cameraPosition;
	     worldPos.xz = worldPos.xz + worldPos.y;
	
	vec2 diff = GetWaveDifferentials(worldPos.xz, 0.1) * angleCoeff;
	
	return vec3(diff, sqrt(1.0 - dot(diff,diff)));
}

void main() {
    vec3 plane = vec3(0,0,1);
    ivec2 corner = ivec2(_cornerTexcoord*atlasSize);
    float LOD = max(0.0, textureQueryLod(tex, _texcoord).y)*0;
    vec3 tangent_pos = vec3((_texcoord - _cornerTexcoord)*atlasSize, 1.0);
    
    vec3 tangent_ray = normalize(_worldPos * _tanMat);
    tangent_pos.xy += 0.5 / _spriteSize;
    
    vec2 tCoord = _texcoord;
    
    if (textureLod(tex, tCoord, LOD).a < 0.1) {
        discard;
    }
    
    vec4 tex_n = uintBitsToFloat(texture(normals, tCoord));
    
    vec3 normal;
    
    vec2 edge = sign(tangent_ray.xy) * 0.5 + 0.5;
    vec3 cornerPlane = vec3(MinComponent2((edge - tangent_pos.xy / _spriteSize) / tangent_ray.xy), 0.0);
    ivec3 edgePlane = ivec3(round(abs(_tanMat * cornerPlane) * sign(_worldPos)));
    ivec3 edgeBackPlane = ivec3(round(abs(_tanMat * vec3(1-cornerPlane.xy,0)) * sign(_worldPos)));
    
    // -1 = air, 0 = tiled, 1 = (different block) or (any corner block)
    
    ivec3 ebinPos = ivoxelPos + ivec3(round(_tanMat[2])) + edgePlane;
    int adjStatus = 0; // 0 = occupied by different block. 1 = occupied by same block. -1 = occupied by air
    
    if (GetVoxelData(ebinPos) == 0) {
        ivec3 ebinPos = ivoxelPos + edgePlane;
        uint chunkAddr = imageLoad(colorimg3, old_get_sparse_chunk_coord(ebinPos) + SPARSE0).r;
        ivec2 chunkCoord = get_sparse_voxel_coord(chunkAddr, ebinPos, 0);
        uint data = GetVoxelData(ebinPos);
        if (data == 0) {
            adjStatus = -1;
        }
        else if (data == packed_tex_coord) {
            adjStatus = 1;
            if (GetVoxelData(ivoxelPos + edgePlane + edgeBackPlane + ivec3(round(_tanMat[2]))) == 0
             && GetVoxelData(ivoxelPos + edgePlane + edgeBackPlane) == 0) adjStatus = -2;
        }
    }
    
    
    if (bool_parallax && tex_n.a < 1.0 && is_voxelized(_blockID) && length(_worldPos) < 1600.0) {
        ivec2 pCoord = Parallax(tangent_pos, tangent_ray, normal, corner, _spriteSize, int(0), adjStatus == -10);
        
        tCoord = vec2(pCoord) / atlasSize;
        
        #ifdef POM_SILHOUETTE
        if (adjStatus == -1 &&
            any(greaterThanEqual(abs((tangent_pos.xy/_spriteSize - normal.xy * exp2(-8)) - vec2(0.5)), vec2(0.5)))) discard;
        
        if (adjStatus == -2 &&
            abs(dot(1.0 - cornerPlane.xy, tangent_pos.xy/_spriteSize - normal.xy * exp2(-8)) - 0.5) >= 0.5
            ) discard;
        #endif
        
        if (normal.z > 0.5) {
            tex_n = uintBitsToFloat(texture(normals, tCoord));
            normal.xy = tex_n.xy * 2.0 - 1.0;
            normal.z = sqrt(max(1.0 - dot(normal.xy, normal.xy), 0.0));
            normal = normalize(normal);
        }
    } else {
        normal.xy = tex_n.xy * 2.0 - 1.0;
        normal.z = sqrt(max(1.0 - dot(normal.xy, normal.xy), 0.0));
        normal = normalize(normal);
    }
    
    vec4 spec = texture(specular, tCoord) * 255.0 / 256.0;
    
    vec4 diffuse = textureLod(tex, tCoord, LOD);
    
    diffuse.rgb *= pow(_vertexColor.rgb, vec3(1.0 / 2.2));
    
    vec3 surfaceNormal = _tanMat * normal;
    
    if (is_iron_block(_blockID)) {
        diffuse.rgb *= pow(0.65 / 5.0, 1.0/2.2);
    }
    
    if (is_water(_blockID)) {
        spec.r = 1.0;
        spec.g = 230.0 / 255.0;
        
        surfaceNormal = _tanMat * ComputeWaveNormals(_worldPos, _tanMat[2]);
        diffuse.rgb = vec3(pow(0.65 / 5.0, 1.0/2.2));
    }
    
    #if (defined gbuffers_entities) || (defined gbuffers_hand)
        diffuse.a = 1.0;
    #else
        diffuse.a = 0.0;
    #endif
    
    gl_FragData[0] = vec4(uintBitsToFloat(packUnorm4x8(vec4(diffuse.rgb * 255.0 / 256.0, diffuse.a))), EncodeNormal(surfaceNormal), uintBitsToFloat(packUnorm4x8(spec)), _blockID);
    gl_FragData[1].rgb = _voxelPos + _tanMat[2] * exp2(-11);
    
    #ifdef PARALLAX
    gl_FragData[2] = vec4(EncodeTangentPos(tangent_pos.xy, _spriteSize), uintBitsToFloat(packUnorm2x16(_cornerTexcoord)), tangent_pos.z, uintBitsToFloat(EncodePlane(_tanMat[2]) + 8*uint(tex_n.a < 1.0)));
    #endif
    
    exit();
}

#endif
/**********************************************************************/