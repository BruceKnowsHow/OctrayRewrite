#if !defined RAYBUFFER_GLSL
#define RAYBUFFER_GLSL

struct BufferedRay {
    vec4 _0;
    vec4 _1;
    vec4 _2;
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
    uint info;
};

void PackBufferedRay(inout BufferedRay buf, RayStruct elem) {
    buf._0.zw = (elem.voxelPos.xy);
    buf._1.x  = (elem.voxelPos.z);
    buf._1.yzw = (elem.worldDir);
    buf._2.xyz = (elem.absorb);
    buf._2.w = uintBitsToFloat(elem.info);
}

RayStruct UnpackBufferedRay(BufferedRay buf) {
    RayStruct elem;
    elem.voxelPos = vec3(buf._0.zw, buf._1.x);
    elem.worldDir = buf._1.yzw;
    elem.absorb = buf._2.xyz;
    elem.info = floatBitsToUint(buf._2.w);
    
    return elem;
}

const uint  PRIMARY_RAY_TYPE = (1 <<  8);
const uint SUNLIGHT_RAY_TYPE = (1 <<  9);
const uint  AMBIENT_RAY_TYPE = (1 << 10);
const uint SPECULAR_RAY_TYPE = (1 << 11);
const uint TERMINAL_RAY_TYPE = (1 << 12);

const uint RAY_DEPTH_MASK = (1 << 8) - 1;
const uint RAY_TYPE_MASK  = ((1 << 16) - 1) & (~RAY_DEPTH_MASK);
const uint RAY_ATTR_MASK  = ((1 << 24) - 1) & (~RAY_DEPTH_MASK) & (~RAY_TYPE_MASK);

bool IsAmbientRay (RayStruct ray) { return ((ray.info & AMBIENT_RAY_TYPE)  != 0); }
bool IsSunlightRay(RayStruct ray) { return ((ray.info & SUNLIGHT_RAY_TYPE) != 0); }
bool IsPrimaryRay (RayStruct ray) { return ((ray.info & PRIMARY_RAY_TYPE)  != 0); }
bool IsSpecularRay(RayStruct ray) { return ((ray.info & SPECULAR_RAY_TYPE) != 0); }
bool IsTerminalRay(RayStruct ray) { return ((ray.info & TERMINAL_RAY_TYPE) != 0); }

uint GetRayDepth(RayStruct ray) { return ray.info & RAY_DEPTH_MASK; }

#define buffer_count_img colorimg3

const ivec2 raybufferFront = ivec2(0, 0);
const ivec2 raybufferBack  = ivec2(1, 0);

int RaybufferReadWarp(ivec2 index) {
    int first_thread = findLSB(activeThreadsNV());
    
    int addr = 0;
    
    if (gl_ThreadInWarpNV == first_thread) {
        addr = imageLoad(buffer_count_img, index).x;
    }
    
    return shuffleNV(addr, first_thread, 32);
}

int RaybufferIncrement(const ivec2 index) {
    return imageAtomicAdd(buffer_count_img, index, 1);
}

int RaybufferDecrement(const ivec2 index) {
    return imageAtomicAdd(buffer_count_img, index, -1);
}

int RaybufferIncrementWarp(const ivec2 index) {
    uint liveMask  = activeThreadsNV();
    int liveCount = bitCount(liveMask);
    
    int prefixSum = bitCount(liveMask & ((1 << gl_ThreadInWarpNV) - 1)) - 1;
    
    int first_thread = findLSB(liveMask);
    
    int rayAlloc = liveCount;
    
    int addr = 0;
    
    if (gl_ThreadInWarpNV == first_thread) {
        addr = imageAtomicAdd(buffer_count_img, index, rayAlloc);
    }
    
    addr = shuffleNV(addr, first_thread, 32) + prefixSum;
    
    return addr;
}

#define RaybufferPushWarp() RaybufferIncrementWarp(raybufferBack)
#define RaybufferPopWarp()  RaybufferIncrementWarp(raybufferFront)

ivec2 ray_buffer_dims = ivec2(4096, 16384);

const int ray_queue_cap = int(ray_buffer_dims.x * ray_buffer_dims.y);

BufferedRay ReadBufferedRay(int index) {
    BufferedRay buf;
    
    index = (index * 4) % ray_queue_cap;
    
    buf._0 = imageLoad(colorimg2, ivec2( index      % ray_buffer_dims.x, index / ray_buffer_dims.x));
    buf._1 = imageLoad(colorimg2, ivec2((index + 1) % ray_buffer_dims.x, index / ray_buffer_dims.x));
    buf._2 = imageLoad(colorimg2, ivec2((index + 2) % ray_buffer_dims.x, index / ray_buffer_dims.x));
    
    return buf;
}

void WriteBufferedRay(int index, BufferedRay buf) {
    index = (index * 4) % ray_queue_cap;
    
    imageStore(colorimg2, ivec2( index      % ray_buffer_dims.x, index / ray_buffer_dims.x), buf._0);
    imageStore(colorimg2, ivec2((index + 1) % ray_buffer_dims.x, index / ray_buffer_dims.x), buf._1);
    imageStore(colorimg2, ivec2((index + 2) % ray_buffer_dims.x, index / ray_buffer_dims.x), buf._2);
}

bool RayIsVisible(RayStruct ray) {
    return ray.absorb.x + ray.absorb.y + ray.absorb.z > 1.0 / 255.0;
}

void WriteBufferedRay(inout int index, BufferedRay buf, RayStruct ray) {
    if (!RayIsVisible(ray)) return;
    
    PackBufferedRay(buf, ray);
    index = RaybufferPushWarp();
    WriteBufferedRay(index, buf);
}

#endif
