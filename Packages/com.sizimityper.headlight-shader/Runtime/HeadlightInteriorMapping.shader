Shader "Custom/HeadlightInteriorMapping"
{
    Properties
    {
        [Header(Lens Surface)]
        _MainTex ("Base Color (RGB)", 2D) = "white" {}
        _BaseColorStrength ("Base Color Strength", Range(0, 1)) = 1.0
        _SpecularPower ("Specular Power", Range(1, 256)) = 64
        _SpecularIntensity ("Specular Intensity", Range(0, 2)) = 0.8
        _FresnelPower ("Fresnel Power", Range(1, 10)) = 3.0
        _FresnelIntensity ("Fresnel Intensity", Range(0, 1)) = 0.5
        _LensRoughness ("Lens Roughness", Range(0, 1)) = 0.0

        [Header(Lens Flute Refraction)]
        _LensNormal ("Lens Flute Normal", 2D) = "bump" {}
        _RefractionStrength ("Refraction Strength", Range(0, 1)) = 0.05

        [Header(Interior Mapping)]
        _BoxCenter ("Box Center (Object Space)", Vector) = (0, 0, 0, 0)
        _BoxRotation ("Box Rotation XYZ (degrees)", Vector) = (0, 0, 0, 0)
        _Scale ("Box Scale (XYZ)", Vector) = (1, 0.5, 0.8, 0)
        _InteriorBlur ("Interior Blur", Range(0, 0.2)) = 0.05
        _InteriorBlurScale ("Interior Blur Scale (large=fine)", Range(5, 300)) = 80

        [Header(Reflector)]
        _FacetCount ("Facet Count (XY)", Vector) = (8, 4, 0, 0)
        _FacetStrength ("Facet Strength", Range(0, 0.5)) = 0.1
        _ReflectorRoughness ("Reflector Roughness", Range(0, 1)) = 0.0
        _ReflectorBrightness ("Reflector Brightness", Range(0, 2)) = 1.0

        [Header(Bulb Emission)]
        _BulbPosition ("Bulb Position (XYZ, Object Space)", Vector) = (0, 0, -0.5, 0)
        _EmissionColor ("Emission Color", Color) = (1, 0.95, 0.8, 1)
        _EmissionIntensity ("Emission Intensity", Range(0, 10)) = 0.0
        _EmissionSharpness ("Emission Sharpness", Range(1, 128)) = 16

        [Header(Housing)]
        _HousingColor ("Housing Color", Color) = (0.02, 0.02, 0.02, 1)
        _HousingRoughness ("Housing Roughness", Range(0, 1)) = 0.6
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma target 3.0

            #include "UnityCG.cginc"
            #ifndef UNITY_SPECCUBE_LOD_STEPS
                #define UNITY_SPECCUBE_LOD_STEPS 6
            #endif

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float2 uvMain : TEXCOORD9;
                float3 worldPos : TEXCOORD1;
                float3 worldNormal : TEXCOORD2;
                float3 objTangent : TEXCOORD3;
                float3 objBitangent : TEXCOORD4;
                float3 objNormal : TEXCOORD5;
                float3 objectPos : TEXCOORD6;
                float3 objectViewDir : TEXCOORD7;
                UNITY_FOG_COORDS(8)
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float _BaseColorStrength;

            sampler2D _LensNormal;
            float4 _LensNormal_ST;

            float _SpecularPower;
            float _SpecularIntensity;
            float _FresnelPower;
            float _FresnelIntensity;
            float _LensRoughness;
            float _RefractionStrength;

            float4 _BoxCenter;
            float4 _BoxRotation;
            float4 _Scale;
            float _InteriorBlur;
            float _InteriorBlurScale;
            float4 _FacetCount;
            float _FacetStrength;
            float _ReflectorRoughness;
            float _ReflectorBrightness;

            float4 _BulbPosition;
            float4 _EmissionColor;
            float _EmissionIntensity;
            float _EmissionSharpness;

            float4 _HousingColor;
            float _HousingRoughness;

            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _LensNormal);
                o.uvMain = TRANSFORM_TEX(v.uv, _MainTex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.worldNormal = UnityObjectToWorldNormal(v.normal);
                o.objNormal = normalize(v.normal);
                o.objTangent = normalize(v.tangent.xyz);
                o.objBitangent = cross(o.objNormal, o.objTangent) * v.tangent.w;
                o.objectPos = v.vertex.xyz;

                // View direction in object space for interior mapping
                float3 worldViewDir = _WorldSpaceCameraPos - o.worldPos;
                o.objectViewDir = mul((float3x3)unity_WorldToObject, worldViewDir);

                UNITY_TRANSFER_FOG(o, o.pos);
                return o;
            }

            // Box interior mapping: ray-box intersection
            // Returns hit position in box-local space and hit normal
            bool interiorMapping(float3 rayOrigin, float3 rayDir, float3 boxScale,
                                 out float3 hitPos, out float3 hitNormal, out float2 hitUV)
            {
                float3 invDir = 1.0 / rayDir;
                float3 tMin = (-boxScale - rayOrigin) * invDir;
                float3 tMax = ( boxScale - rayOrigin) * invDir;

                float3 tFar = max(tMin, tMax);

                // Track which axis hits first to avoid float equality comparison
                int axis = 0;
                float t = tFar.x;
                if (tFar.y < t) { t = tFar.y; axis = 1; }
                if (tFar.z < t) { t = tFar.z; axis = 2; }

                if (t < 0.0)
                {
                    hitPos = float3(0, 0, 0);
                    hitNormal = float3(0, 0, 1);
                    hitUV = float2(0.5, 0.5);
                    return false;
                }

                hitPos = rayOrigin + rayDir * t;

                // Determine which face was hit and compute UV
                if (axis == 2)
                {
                    // Back wall
                    hitNormal = float3(0, 0, sign(rayDir.z));
                    hitUV = hitPos.xy / boxScale.xy * 0.5 + 0.5;
                }
                else if (axis == 0)
                {
                    // Side wall
                    hitNormal = float3(sign(rayDir.x), 0, 0);
                    hitUV = hitPos.zy / boxScale.zy * 0.5 + 0.5;
                }
                else
                {
                    // Top/bottom wall
                    hitNormal = float3(0, sign(rayDir.y), 0);
                    hitUV = hitPos.xz / boxScale.xz * 0.5 + 0.5;
                }

                return true;
            }

            // Rotation matrix from XYZ Euler degrees (Rz*Ry*Rx order)
            float3x3 boxRotationMatrix(float3 eulerDeg)
            {
                float3 r = eulerDeg * (UNITY_PI / 180.0);
                float cx = cos(r.x), sx = sin(r.x);
                float cy = cos(r.y), sy = sin(r.y);
                float cz = cos(r.z), sz = sin(r.z);
                return float3x3(
                    cz*cy,  cz*sy*sx - sz*cx,  cz*sy*cx + sz*sx,
                    sz*cy,  sz*sy*sx + cz*cx,  sz*sy*cx - cz*sx,
                      -sy,           cy*sx,             cy*cx
                );
            }

            // Procedural kamaboko facet normal (tangent-space, z-forward)
            float3 computeFacetNormal(float2 uv, float2 facetCount, float facetStrength)
            {
                float2 cell = frac(uv * facetCount);
                float3 facetN;
                facetN.x = sin(cell.x * UNITY_PI) * facetStrength;
                facetN.y = sin(cell.y * UNITY_PI) * facetStrength;
                facetN.z = 1.0;
                return normalize(facetN);
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float3 worldViewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 worldNormal = normalize(i.worldNormal);

                // ==========================================
                // 1. Lens surface lighting (smooth)
                // ==========================================
                // Simple directional spec using view reflection against a fixed light
                float3 lightDir = normalize(float3(0.3, 0.5, 1.0)); // normalized at compile time
                float3 halfVec = normalize(worldViewDir + lightDir);
                float NdotH = saturate(dot(worldNormal, halfVec));
                float specular = pow(NdotH, _SpecularPower) * _SpecularIntensity;

                // Fresnel
                float NdotV = saturate(dot(worldNormal, worldViewDir));
                float fresnel = pow(1.0 - NdotV, _FresnelPower) * _FresnelIntensity;

                // Lens surface reflection probe
                float3 lensReflDir = reflect(-worldViewDir, worldNormal);
                float lensMip = _LensRoughness * UNITY_SPECCUBE_LOD_STEPS;
                float4 lensEnvSample = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, lensReflDir, lensMip);
                float3 lensEnvColor = DecodeHDR(lensEnvSample, unity_SpecCube0_HDR);

                // ==========================================
                // 2. Lens flute refraction for interior ray
                // ==========================================
                float3 lensNormalTS = UnpackNormal(tex2D(_LensNormal, i.uv));
                // TBN already in object space from vertex shader
                float3 objTangent = normalize(i.objTangent);
                float3 objBitangent = normalize(i.objBitangent);
                float3 objNormal = normalize(i.objNormal);

                // Refract view direction by flute normal (tangential components only)
                // Negate: objectViewDir points toward camera; interior ray must go into the surface
                float3 objViewDir = normalize(i.objectViewDir);
                float3 lensOffset = (objTangent * lensNormalTS.x + objBitangent * lensNormalTS.y) * _RefractionStrength;
                float3 interiorRay = normalize(-objViewDir + lensOffset);

                // グリッド量子化したハッシュノイズでレイを偏向させ箱のエッジをぼかす
                // _InteriorBlurScale でグリッドサイズ（＝粒の大きさ）を制御する
                float2 seed = floor(i.objectPos.xy * _InteriorBlurScale);
                float blurX = (frac(sin(dot(seed, float2(127.1, 311.7))) * 43758.5) - 0.5);
                float blurY = (frac(sin(dot(seed, float2(269.5, 183.3))) * 43758.5) - 0.5);
                interiorRay = normalize(interiorRay + float3(blurX, blurY, 0) * _InteriorBlur);

                // ==========================================
                // 3. Interior Mapping (box)
                // ==========================================
                float3 boxScale = _Scale.xyz;
                float3x3 rot = boxRotationMatrix(_BoxRotation.xyz);
                float3 localRayOrigin = mul(rot, i.objectPos - _BoxCenter.xyz);
                float3 localInteriorRay = mul(rot, interiorRay);
                float3 hitPos;
                float3 hitNormal;
                float2 hitUV;

                bool hit = interiorMapping(localRayOrigin, localInteriorRay, boxScale,
                                           hitPos, hitNormal, hitUV);

                // ==========================================
                // 4. Reflector shading
                // ==========================================
                float3 interiorColor;

                if (hit)
                {
                    // Procedural facet normal (in box-local space, perturbing the hit normal)
                    float3 facetN = computeFacetNormal(hitUV, _FacetCount.xy, _FacetStrength);

                    // Blend facet perturbation with the actual hit wall normal
                    float3 perturbedNormal;
                    perturbedNormal.x = hitNormal.x + facetN.x;
                    perturbedNormal.y = hitNormal.y + facetN.y;
                    perturbedNormal.z = hitNormal.z + facetN.z;
                    perturbedNormal = normalize(perturbedNormal);

                    float3 perturbedNormalOS = mul(transpose(rot), perturbedNormal);
                    float3 worldPerturbedN = normalize(mul((float3x3)unity_ObjectToWorld, perturbedNormalOS));

                    // Sample reflection probe with perturbed reflector normal
                    float3 reflDir = reflect(-worldViewDir, worldPerturbedN);
                    float mip = _ReflectorRoughness * UNITY_SPECCUBE_LOD_STEPS;
                    float4 envSample = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflDir, mip);
                    float3 envColor = DecodeHDR(envSample, unity_SpecCube0_HDR);
                    interiorColor = envColor * _ReflectorBrightness;

                    // ==========================================
                    // 5. Bulb emission (reflection only)
                    // ==========================================
                    float3 toBulb = normalize(mul(rot, _BulbPosition.xyz - _BoxCenter.xyz) - hitPos);
                    float3 reflectedBulb = reflect(-toBulb, perturbedNormal);
                    float bulbSpec = pow(saturate(dot(reflectedBulb, -interiorRay)), _EmissionSharpness);
                    interiorColor += bulbSpec * _EmissionColor.rgb * _EmissionIntensity;
                }
                else
                {
                    // ハウジング：メタル質感（反射プローブ × カラーテント）
                    float3 housingReflDir = reflect(-worldViewDir, worldNormal);
                    float housingMip = _HousingRoughness * UNITY_SPECCUBE_LOD_STEPS;
                    float4 housingEnvSample = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, housingReflDir, housingMip);
                    float3 housingEnvColor = DecodeHDR(housingEnvSample, unity_SpecCube0_HDR);
                    interiorColor = housingEnvColor * _HousingColor.rgb;
                }

                // ==========================================
                // 6. Composite
                // ==========================================
                float3 baseColor = tex2D(_MainTex, i.uvMain).rgb;
                float3 finalColor = interiorColor * lerp(1.0, baseColor, _BaseColorStrength);
                // Add lens specular and fresnel on top
                finalColor += specular;
                finalColor += fresnel * lensEnvColor;

                fixed4 col = fixed4(finalColor, 1.0);
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
    FallBack "Unlit/Color"
}
