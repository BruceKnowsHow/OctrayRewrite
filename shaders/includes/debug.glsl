#if !defined DEBUG_GLSL
#define DEBUG_GLSL

layout (rgba8) uniform image2D colorimg5;

//#define DEBUG
// #define DEBUG_BRIGHTNESS 1.0 // [1/65536.0 1/32768.0 1/16384.0 1/8192.0 1/4096.0 1/2048.0 1/1024.0 1/512.0 1/256.0 1/128.0 1/64.0 1/32.0 1/16.0 1/8.0 1/4.0 1/2.0 1.0 2.0 4.0 8.0 16.0 32.0 64.0 128.0 256.0 512.0 1024.0 2048.0 4096.0 8192.0 16384.0 32768.0 65536.0]
// #define DRAW_DEBUG_VALUE

bool deb = false;
vec3 Debug = vec3(0.0);

// Write the direct variable onto the screen
void show( bool x) { deb = true; Debug = vec3(float(x)); }
void show(float x) { deb = true; Debug = vec3(x); }
void show( vec2 x) { deb = true; Debug = vec3(x, 0.0); }
void show( vec3 x) { deb = true; Debug = x; }
void show( vec4 x) { deb = true; Debug = x.rgb; }

void inc( bool x) { deb = true; Debug += vec3(float(x)); }
void inc(float x) { deb = true; Debug += vec3(x); }
void inc( vec2 x) { deb = true; Debug += vec3(x, 0.0); }
void inc( vec3 x) { deb = true; Debug += x; }
void inc( vec4 x) { deb = true; Debug += x.rgb; }

#if defined fsh
	void exit() { if (deb) imageStore(colorimg5, ivec2(gl_FragCoord.xy), vec4(Debug, 0.0)); }
#endif
#if defined csh
	void exitCoord(ivec2 screenCoord) { if (deb) imageStore(colorimg5, screenCoord, vec4(Debug, 0.0)); Debug = vec3(0.0); }
#endif


#endif
