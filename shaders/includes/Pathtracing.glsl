void DoPBR(vec4 diffuse, vec3 surfaceNormal, vec3 flatNormal, vec4 tex_s, vec3 worldDir,
                  inout RayStruct specRay, inout RayStruct ambRay, inout RayStruct sunRay)
{
    bool isMetal = tex_s.g > 229.5/255.0;
    
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
    
    
    ambRay.worldDir = ArbitraryTBN(surfaceNormal) * CalculateConeVector(RandNextF(), radians(90.0), 32);
    ambRay.absorb *= float(!isMetal);
    // ambRay.absorb *= float(dot(ambRay.worldDir, flatNormal) > 0.0) * float(GetRayDepth(ambRay) < 2);
    ambRay.absorb *= float(dot(ambRay.worldDir, flatNormal) > 0.0);
    
    sunRay.worldDir = normalize(ArbitraryTBN(sunDirection)*CalculateConeVector(RandNextF(), radians(1.0), 32));
    sunRay.absorb *= max(0.0, dot(sunRay.worldDir, surfaceNormal)) * mix(vec3(1.0), kD, isMetal);
    sunRay.absorb *= float(dot(sunRay.worldDir, flatNormal) > 0.0);
    
    #define AMBIENT_RAYS
    #define SUNLIGHT_RAYS
    // #define SPECULAR_RAYS
    
    #ifndef AMBIENT_RAYS
        ambRay.absorb *= 0.0;
    #endif
    
    #ifndef SPECULAR_RAYS
        specRay.absorb *= 0.0;
    #endif
    
    #ifndef SUNLIGHT_RAYS
        sunRay.absorb *= 0.0;
    #endif
}