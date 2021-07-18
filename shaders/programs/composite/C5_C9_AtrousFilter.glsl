// #define ANY_ATROUS_FILTER

// #define ATROUS_FILTER_PASSES_1
// #define ATROUS_FILTER_PASSES_2
// #define ATROUS_FILTER_PASSES_3
// #define ATROUS_FILTER_PASSES_4
// #define ATROUS_FILTER_PASSES_5

#ifdef ANY_ATROUS_FILTER
#endif
#ifdef ATROUS_FILTER_PASSES_1
#endif
#ifdef ATROUS_FILTER_PASSES_2
#endif
#ifdef ATROUS_FILTER_PASSES_3
#endif
#ifdef ATROUS_FILTER_PASSES_4
#endif
#ifdef ATROUS_FILTER_PASSES_5
#endif

uniform sampler2D colortex6;
uniform sampler2D colortex9;
uniform sampler2D depthtex0;

uniform mat4 gbufferProjectionInverse;

/* DRAWBUFFERS:9 */

vec3 DecodeNormal(float enc) {
    const float bits = 11.0;
    
	vec4 normal;
	
	normal.y    = exp2(bits + 2.0) * floor(enc / exp2(bits + 2.0));
	normal.x    = enc - normal.y;
	normal.xy  /= exp2(vec2(bits, bits * 2.0 + 2.0));
	normal.x   -= 1.0;
	normal.xy  *= 3.14159;
	normal.xwzy = vec4(sin(normal.xy), cos(normal.xy));
	normal.xz  *= normal.w;
	
	return normal.xyz;
}

float LinearizeDepth(float depth) {
	return -1.0 / ((depth * 2.0 - 1.0) * gbufferProjectionInverse[2].w + gbufferProjectionInverse[3].w);
}

void main() {
    if (texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x >= 1.0) {
		gl_FragData[0] = texelFetch(colortex9, ivec2(gl_FragCoord.xy), 0);
		return;
	}
    
    vec4 col = vec4(0.0);
    
    float weights = 0.0;
    
    vec3 gbufferEncode = texelFetch(colortex6, ivec2(gl_FragCoord.xy), 0).rgb;
    vec3 normal = DecodeNormal(gbufferEncode.g);
    float depth = LinearizeDepth(texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x);
    
    int kernel = 1 << ATROUS_INDEX;
    
    for (int i = -kernel; i <= kernel; i += 1 << ATROUS_INDEX) {
		for (int j = -kernel; j <= kernel; j += 1 << ATROUS_INDEX) {
            ivec2 icoord = ivec2(gl_FragCoord.xy) + ivec2(i,j);
            
            vec3 samplenormal = DecodeNormal(texelFetch(colortex6, icoord, 0).g);
            float sampledepth = LinearizeDepth(texelFetch(depthtex0, icoord, 0).x);
            vec4 color = texelFetch(colortex9, icoord, 0);
            
            float weight = 1.0;
            weight *= max(dot(normal, samplenormal)*16-15, 0.0);
			weight *= max(1.0-distance(depth, sampledepth), 0.0);
			weight = weight + 0.000001;
            
            col += color * weight;
			weights += weight;
            
        }
    }
    
    col /= weights;
    
    gl_FragData[0] = col;
}