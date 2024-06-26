uniform sampler2D colortex13;
uniform vec2 viewSize;

#include "../../includes/debug.glsl"

vec2 texcoord = gl_FragCoord.xy / viewSize;

const bool colortex13MipmapEnabled = true;

#define cubesmooth(x) ((x) * (x) * (3.0 - 2.0 * (x)))

#define ACCUM_GAMMA 2.4

vec3 ComputeBloomTile(const float scale, vec2 offset) { // Computes a single bloom tile, the tile's blur level is inversely proportional to its size
	// Each bloom tile uses (1.0 / scale + pixelSize * 2.0) texcoord-units of the screen
	
	vec2 coord  = texcoord;
	     coord -= offset + 1 / viewSize; // A pixel is added to the offset to give the bloom tile a padding
	     coord *= scale;
	
	vec2 padding = scale / viewSize;
	
	if (any(greaterThanEqual(abs(coord - 0.5), padding + 0.5)))
		return vec3(0.0);
	
	
	float Lod = log2(scale);
	
	const float range     = 2.0 * scale; // Sample radius has to be adjusted based on the scale of the bloom tile
	const float interval  = 1.0 * scale;
	float  maxLength = length(vec2(range));
	
	vec3  bloom       = vec3(0.0);
	float totalWeight = 0.0;
	
	for (float i = -range; i <= range; i += interval) {
		for (float j = -range; j <= range; j += interval) {
			float weight  = 1.0 - length(vec2(i, j)) / maxLength;
			      weight *= weight;
			      weight  = cubesmooth(weight); // Apply a faux-gaussian falloff
			
			vec2 offset = vec2(i, j) / viewSize;
			
			vec4 lookup = pow(textureLod(colortex13, coord + offset, Lod), vec4(vec3(ACCUM_GAMMA), 1.0));
			
			bloom       += lookup.rgb * weight;
			totalWeight += weight;
		}
	}
    
	return bloom / totalWeight;
}

vec3 ComputeBloom() {
	vec3 bloom  = ComputeBloomTile(  4, vec2(0.0                         ,                          0.0));
	     bloom += ComputeBloomTile(  8, vec2(0.0                         , 0.25      + 1/viewSize.y * 2.0));
	     bloom += ComputeBloomTile( 16, vec2(0.125    + 1/viewSize.x * 2.0, 0.25     + 1/viewSize.y * 2.0));
	     bloom += ComputeBloomTile( 32, vec2(0.1875   + 1/viewSize.x * 4.0, 0.25     + 1/viewSize.y * 2.0));
	     bloom += ComputeBloomTile( 64, vec2(0.125    + 1/viewSize.x * 2.0, 0.3125   + 1/viewSize.y * 4.0));
	     bloom += ComputeBloomTile(128, vec2(0.140625 + 1/viewSize.x * 4.0, 0.3125   + 1/viewSize.y * 4.0));
	     bloom += ComputeBloomTile(256, vec2(0.125    + 1/viewSize.x * 2.0, 0.328125 + 1/viewSize.y * 6.0));
	
	return max(bloom, vec3(0.0));
}


/* RENDERTARGETS:14 */

void main() {
	if (texcoord.x > 0.25 || texcoord.y > 0.375) discard;
	
	gl_FragData[0] = vec4(ComputeBloom(), 0.0);
	
	exit();
}