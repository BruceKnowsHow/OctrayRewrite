#if !defined RAYBUFFER_GLSL
#define RAYBUFFER_GLSL

struct BufferedRay {
    vec4 _0;
    vec4 _1;
    vec4 _2;
    vec4 _3;
};

float PackCoord(ivec2 coord) {
    coord.y = coord.y >> 16;
    return intBitsToFloat(coord.x + coord.y);
}

ivec2 UnpackCoord(float enc) {
    ivec2 coord;
    coord.x = floatBitsToInt(enc) & ((1 << 16) - 1);
    coord.y = floatBitsToInt(enc) >> 16;
    
    return coord;
}

struct RayStruct {
    vec3 voxelPos;
    vec3 worldDir;
    vec3 absorb;
    vec4 extra;
    uint info;
    ivec2 screenCoord;
};

BufferedRay PackBufferedRay(inout RayStruct elem) {
    BufferedRay buf;
    buf._0.xy = intBitsToFloat(elem.screenCoord);
    buf._0.zw = (elem.voxelPos.xy);
    buf._1.x  = (elem.voxelPos.z);
    buf._1.yzw = (elem.worldDir);
    buf._2.xyz = (elem.absorb);
    buf._2.w = uintBitsToFloat(elem.info);
    buf._3 = elem.extra;
    
    elem.absorb *= 0.0;
    
    return buf;
}

RayStruct UnpackBufferedRay(BufferedRay buf) {
    RayStruct elem;
    elem.screenCoord = floatBitsToInt(buf._0.xy);
    elem.voxelPos = vec3(buf._0.zw, buf._1.x);
    elem.worldDir = buf._1.yzw;
    elem.absorb = buf._2.xyz;
    elem.info = floatBitsToUint(buf._2.w);
    elem.extra = buf._3;
    
    return elem;
}

#define MAX_LIGHT_BOUNCES 2 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 256]

const uint  PRIMARY_RAY_TYPE = (1 <<  8);
const uint SUNLIGHT_RAY_TYPE = (1 <<  9);
const uint  AMBIENT_RAY_TYPE = (1 << 10);
const uint SPECULAR_RAY_TYPE = (1 << 11);
const uint  STENCIL_RAY_TYPE = (1 << 12);
const uint PARALLAX_RAY_TYPE = (1 << 13);

const uint RAY_DEPTH_MASK = (1 << 8) - 1;
const uint RAY_TYPE_MASK  = ((1 << 16) - 1) & (~RAY_DEPTH_MASK);

bool IsAmbientRay (RayStruct ray) { return ((ray.info & AMBIENT_RAY_TYPE)  != 0); }
bool IsSunlightRay(RayStruct ray) { return ((ray.info & SUNLIGHT_RAY_TYPE) != 0); }
bool IsPrimaryRay (RayStruct ray) { return ((ray.info & PRIMARY_RAY_TYPE)  != 0); }
bool IsSpecularRay(RayStruct ray) { return ((ray.info & SPECULAR_RAY_TYPE) != 0); }
bool  IsStencilRay(RayStruct ray) { return ((ray.info & STENCIL_RAY_TYPE)  != 0); }
bool IsParallaxRay(RayStruct ray) { return ((ray.info & PARALLAX_RAY_TYPE) != 0); }

#define raybuffer_img colorimg1
layout (rgba32f) uniform image2D raybuffer_img;

const ivec2 raybuffer_back  = ivec2(0, 513);
const ivec2 raybuffer_front = ivec2(1, 513);

uint GetRayDepth(RayStruct ray) { return ray.info & RAY_DEPTH_MASK; }

uint RaybufferReadWarp(ivec2 index) {
    uint ret;
    
#   if (defined MC_GL_VENDOR_NVIDIA)
    uint first_thread = findLSB(uint(ballotARB(true)));
    
    uint addr = 0;
    
    if (gl_SubGroupInvocationARB == first_thread) {
        addr = imageLoad(colorimg3, index).x;
    }
    
    ret = readFirstInvocationARB(addr);
#   else
    ret = imageLoad(colorimg3, index).x;
#   endif
    
    return ret;
}

uint RaybufferIncrementWarp(const ivec2 index) {
    uint ret;
    
#   if (defined MC_GL_VENDOR_NVIDIA)
    uint liveMask  = uint(ballotARB(true));
    uint liveCount = bitCount(liveMask);
    
    uint prefixSum = bitCount(liveMask & ((1 << gl_SubGroupInvocationARB) - 1));
    
    uint first_thread = findLSB(liveMask);
    
    uint addr = 0;
    
    if (gl_SubGroupInvocationARB == first_thread) {
        addr = imageAtomicAdd(colorimg3, index, liveCount);
    }
    
    ret = readFirstInvocationARB(addr) + prefixSum;
#   else
    ret = imageAtomicAdd(colorimg3, index, 1);
#   endif
    
    return ret;
}

uint RaybufferPushWarp() {
    return RaybufferIncrementWarp(raybuffer_back);
}

uint RaybufferPopWarp() {
    return RaybufferIncrementWarp(raybuffer_front);
}

#define RAYBUFFER_MULT 2 // [1 2 4]

uniform vec2 raybuffer_dims;
ivec2 ray_buffer_dims = ivec2(raybuffer_dims);

int ray_queue_cap = int(ray_buffer_dims.x * ray_buffer_dims.y);

BufferedRay ReadBufferedRay(uint index) {
    BufferedRay buf;
    
    index = (index * 4) % ray_queue_cap;
    
    buf._0 = imageLoad(raybuffer_img, ivec2((index    ) % ray_buffer_dims.x, index / ray_buffer_dims.x));
    buf._1 = imageLoad(raybuffer_img, ivec2((index + 1) % ray_buffer_dims.x, index / ray_buffer_dims.x));
    buf._2 = imageLoad(raybuffer_img, ivec2((index + 2) % ray_buffer_dims.x, index / ray_buffer_dims.x));
    buf._3 = imageLoad(raybuffer_img, ivec2((index + 3) % ray_buffer_dims.x, index / ray_buffer_dims.x));
    
    return buf;
}

void WriteBufferedRay(uint index, BufferedRay buf) {
    buf._3.w = uintBitsToFloat(index);
    
    index = (index * 4) % ray_queue_cap;
    
    imageStore(raybuffer_img, ivec2((index   )  % ray_buffer_dims.x, index / ray_buffer_dims.x), buf._0);
    imageStore(raybuffer_img, ivec2((index + 1) % ray_buffer_dims.x, index / ray_buffer_dims.x), buf._1);
    imageStore(raybuffer_img, ivec2((index + 2) % ray_buffer_dims.x, index / ray_buffer_dims.x), buf._2);
    imageStore(raybuffer_img, ivec2((index + 3) % ray_buffer_dims.x, index / ray_buffer_dims.x), buf._3);
}

bool RayIsVisible(RayStruct ray) {
    return ray.absorb.x + ray.absorb.y + ray.absorb.z > 1.0 / 255.0;
}

void WriteRay(inout uint index, RayStruct ray) {
    if (!RayIsVisible(ray)) return;
    
    index = RaybufferPushWarp();
    WriteBufferedRay(index, PackBufferedRay(ray));
}

// Atomic color write
uvec2 EncodeColor(vec3 color) {
    color = color * 1024;
    color = clamp(color, vec3(0.0), vec3(1 << 15));
    
    uvec3 col = uvec3(color);
    return uvec2(col.r + (col.g << 16), col.b);
}

void WriteColor(vec3 color, ivec2 screenCoord) {
    ivec2 coord = ScreenToVoxelBuffer(screenCoord);
    
    uvec2 enc = EncodeColor(color);
    
    imageAtomicAdd(voxel_data_img, coord              , enc.x);
    imageAtomicAdd(voxel_data_img, coord + ivec2(1, 0), enc.y);
}

#endif
