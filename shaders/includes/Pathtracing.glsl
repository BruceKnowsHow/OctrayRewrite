#define AMBIENT_RAYS
#define SUNLIGHT_RAYS
// #define SPECULAR_RAYS

#define BLUE_NOISE_AMBIENT

void DoPBR(vec4 diffuse, vec3 surfaceNormal, vec3 flatNormal, vec4 tex_s, vec3 worldDir,
                  inout RayStruct specRay, inout RayStruct ambRay, inout RayStruct sunRay, mat3 tanMat)
{
    bool isMetal = tex_s.g > 229.5/255.0;
    
    #ifndef SPECULAR_RAYS
    isMetal = false;
    #endif
    
    float roughness = pow(1.0 - tex_s.r, 2.0);
    vec3 F0 = (isMetal) ? diffuse.rgb : vec3(tex_s.g);
    
    vec2 uv = RandNext2F();
    
    vec3 V = reflect(worldDir, surfaceNormal);
    mat3 atbn = ArbitraryTBN(V);
    specRay.worldDir = normalize(atbn * GGXVNDFSample(V * atbn, roughness*roughness, uv));
    
    float cosTheta = dot(specRay.worldDir, surfaceNormal);
    float G = GeometrySmith(surfaceNormal, -worldDir, specRay.worldDir, roughness);
    
    vec3 F = fresnelSchlick(cosTheta, vec3(F0));
    vec3 numerator = G * F;
    
    float denominator = (4.0*0+1) * max(dot(surfaceNormal, -worldDir), 0.0) * max(dot(surfaceNormal, specRay.worldDir), 0.0);
    
    vec3 spec = numerator / max(denominator, 0.001);
    
    vec3 kS = F;
    vec3 kD = (1.0 - kS) * float(!isMetal);
    
    float NdotL = max(dot(surfaceNormal, specRay.worldDir), 0.0);
    
    vec3 Li = (kD * diffuse.rgb*0 * 4.0 + spec) * NdotL;
    
    specRay.absorb *= Li * 1;
    specRay.absorb *= float(dot(specRay.worldDir, flatNormal) > 0.0);
    
#ifdef BLUE_NOISE_AMBIENT
    ivec3 ns = ivec3(128, 128, 32);
    
    vec3 dir;
    #if defined composite0
        dir.xy =                (texelFetch(colortex14, ivec2(ivec2(ambRay.screenCoord) + uvec2(Rand2(frameCounter/ns.z) % ns.xy) + uvec2(Rand2(GetRayDepth(ambRay)*12345) % ns.xy)) % ns.xy + ivec2((frameCounter%ns.z)*ns.x, 0), 0).xy)*2-1;
    #else
        dir.xy = uintBitsToFloat(texelFetch(colortex14, ivec2(ivec2(ambRay.screenCoord) + uvec2(Rand2(frameCounter/ns.z) % ns.xy) + uvec2(Rand2(GetRayDepth(ambRay)*12345) % ns.xy)) % ns.xy + ivec2((frameCounter%ns.z)*ns.x, 0), 0).xy)*2-1;
    #endif
    dir.z = sqrt(1.0 - dot(dir.xy, dir.xy));
    dir = normalize(dir);
#else
    vec3 dir = CalculateConeVector(RandNextF(), radians(90.0), 32);
#endif
    
    ambRay.worldDir = ArbitraryTBN(surfaceNormal) * dir;
    ambRay.absorb *= float(!isMetal);
    ambRay.absorb *= float(dot(ambRay.worldDir, flatNormal) > 0.0);
    
    sunRay.worldDir = normalize(ArbitraryTBN(sunDirection)*CalculateConeVector(RandNextF(), radians(1.0), 32)) * tanMat;
    sunRay.absorb *= max(0.0, dot(sunRay.worldDir, surfaceNormal)) * mix(vec3(1.0), kD, float(isMetal));
    sunRay.absorb *= float(dot(sunRay.worldDir, flatNormal) > 0.0);
    
    #ifndef AMBIENT_RAYS
        ambRay.absorb *= 0.0;
    #endif
    
    #ifndef SPECULAR_RAYS
        specRay.absorb *= 0.0;
    #endif
    
    #ifndef SUNLIGHT_RAYS
        sunRay.absorb *= 0.0;
    #endif
    
    #if (!defined world0)
        sunRay.absorb *= 0.0;
    #endif
}