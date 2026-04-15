Shader "Custom/HeadlightInteriorMapping"
{
    Properties
    {
        [Header(Lens Surface)]
        _SpecularPower ("Specular Power", Range(1, 256)) = 64
        _SpecularIntensity ("Specular Intensity", Range(0, 2)) = 0.8
        _FresnelPower ("Fresnel Power", Range(1, 10)) = 3.0
        _FresnelIntensity ("Fresnel Intensity", Range(0, 1)) = 0.5

        [Header(Lens Flute Refraction)]
        _LensNormal ("Lens Flute Normal", 2D) = "bump" {}
        _RefractionStrength ("Refraction Strength", Range(0, 0.3)) = 0.05

        [Header(Interior Mapping)]
        _Scale ("Box Scale (XYZ)", Vector) = (1, 0.5, 0.8, 0)

        [Header(Reflector)]
        _MatCap ("MatCap", 2D) = "white" {}
        _FacetCount ("Facet Count (XY)", Vector) = (8, 4, 0, 0)
        _FacetStrength ("Facet Strength", Range(0, 0.5)) = 0.1
        _ReflectorBrightness ("Reflector Brightness", Range(0, 2)) = 1.0

        [Header(Bulb Emission)]
        _BulbPosition ("Bulb Position (XYZ, Object Space)", Vector) = (0, 0, -0.5, 0)
        _EmissionColor ("Emission Color", Color) = (1, 0.95, 0.8, 1)
        _EmissionIntensity ("Emission Intensity", Range(0, 10)) = 0.0
        _EmissionSharpness ("Emission Sharpness", Range(1, 128)) = 16

        [Header(Housing)]
        _HousingColor ("Housing Color", Color) = (0.02, 0.02, 0.02, 1)
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

            #include "UnityCG.cginc"

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
                float3 worldPos : TEXCOORD1;
                float3 worldNormal : TEXCOORD2;
                float3 worldTangent : TEXCOORD3;
                float3 worldBitangent : TEXCOORD4;
                float3 objectPos : TEXCOORD5;
                float3 objectViewDir : TEXCOORD6;
                UNITY_FOG_COORDS(7)
            };

            sampler2D _LensNormal;
            float4 _LensNormal_ST;
            sampler2D _MatCap;

            float _SpecularPower;
            float _SpecularIntensity;
            float _FresnelPower;
            float _FresnelIntensity;
            float _RefractionStrength;

            float4 _Scale;
            float4 _FacetCount;
            float _FacetStrength;
            float _ReflectorBrightness;

            float4 _BulbPosition;
            float4 _EmissionColor;
            float _EmissionIntensity;
            float _EmissionSharpness;

            float4 _HousingColor;

            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _LensNormal);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.worldNormal = UnityObjectToWorldNormal(v.normal);
                o.worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
                o.worldBitangent = cross(o.worldNormal, o.worldTangent) * v.tangent.w;
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
                // Box bounds: -boxScale to +boxScale (but we only care about inner walls)
                // Ray starts from front face, goes inward
                float3 invDir = 1.0 / rayDir;
                float3 tMin = (-boxScale - rayOrigin) * invDir;
                float3 tMax = ( boxScale - rayOrigin) * invDir;

                float3 tFar  = max(tMin, tMax);

                // We want the nearest far-plane hit (first interior wall)
                float t = min(tFar.x, min(tFar.y, tFar.z));

                if (t < 0.0)
                {
                    hitPos = float3(0, 0, 0);
                    hitNormal = float3(0, 0, 1);
                    hitUV = float2(0.5, 0.5);
                    return false;
                }

                hitPos = rayOrigin + rayDir * t;

                // Determine which face was hit and compute UV
                if (t == tFar.z)
                {
                    // Back wall
                    hitNormal = float3(0, 0, sign(rayDir.z));
                    hitUV = hitPos.xy / boxScale.xy * 0.5 + 0.5;
                }
                else if (t == tFar.x)
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

            // Procedural kamaboko facet normal
            float3 computeFacetNormal(float2 uv, float2 facetCount, float facetStrength, float3 baseNormal)
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
                float3 lightDir = normalize(float3(0.3, 0.5, 1.0));
                float3 halfVec = normalize(worldViewDir + lightDir);
                float NdotH = saturate(dot(worldNormal, halfVec));
                float specular = pow(NdotH, _SpecularPower) * _SpecularIntensity;

                // Fresnel
                float NdotV = saturate(dot(worldNormal, worldViewDir));
                float fresnel = pow(1.0 - NdotV, _FresnelPower) * _FresnelIntensity;

                // ==========================================
                // 2. Lens flute refraction for interior ray
                // ==========================================
                float3 lensNormalTS = UnpackNormal(tex2D(_LensNormal, i.uv));
                // Build TBN in object space for refraction
                float3 objNormal = normalize(mul((float3x3)unity_WorldToObject, worldNormal));
                float3 objTangent = normalize(mul((float3x3)unity_WorldToObject, normalize(i.worldTangent)));
                float3 objBitangent = normalize(mul((float3x3)unity_WorldToObject, normalize(i.worldBitangent)));

                float3 lensNormalOS = normalize(
                    objTangent * lensNormalTS.x +
                    objBitangent * lensNormalTS.y +
                    objNormal * lensNormalTS.z
                );

                // Refract view direction by flute normal
                float3 objViewDir = normalize(i.objectViewDir);
                float3 interiorRay = normalize(objViewDir + lensNormalOS * _RefractionStrength);

                // ==========================================
                // 3. Interior Mapping (box)
                // ==========================================
                float3 boxScale = _Scale.xyz;
                float3 hitPos;
                float3 hitNormal;
                float2 hitUV;

                bool hit = interiorMapping(i.objectPos, interiorRay, boxScale,
                                           hitPos, hitNormal, hitUV);

                // ==========================================
                // 4. Reflector shading
                // ==========================================
                float3 interiorColor;

                if (hit)
                {
                    // Procedural facet normal (in box-local space, perturbing the hit normal)
                    float3 facetN = computeFacetNormal(hitUV, _FacetCount.xy, _FacetStrength, hitNormal);

                    // Transform facet normal to world space for matcap lookup
                    // Blend facet perturbation with the actual hit wall normal
                    float3 perturbedNormal;
                    perturbedNormal.x = hitNormal.x + facetN.x;
                    perturbedNormal.y = hitNormal.y + facetN.y;
                    perturbedNormal.z = hitNormal.z + facetN.z;
                    perturbedNormal = normalize(perturbedNormal);

                    float3 worldPerturbedN = normalize(mul((float3x3)unity_ObjectToWorld, perturbedNormal));

                    // MatCap UV from world-space normal
                    float3 viewCross = cross(worldViewDir, float3(0, 1, 0));
                    float3 viewUp = cross(viewCross, worldViewDir);
                    float2 matCapUV;
                    matCapUV.x = dot(normalize(viewCross), worldPerturbedN) * 0.5 + 0.5;
                    matCapUV.y = dot(normalize(viewUp), worldPerturbedN) * 0.5 + 0.5;

                    float3 matCapColor = tex2D(_MatCap, matCapUV).rgb;
                    interiorColor = matCapColor * _ReflectorBrightness;

                    // ==========================================
                    // 5. Bulb emission (reflection only)
                    // ==========================================
                    float3 toBulb = normalize(_BulbPosition.xyz - hitPos);
                    float3 reflectedBulb = reflect(-toBulb, perturbedNormal);
                    float bulbSpec = pow(saturate(dot(reflectedBulb, -interiorRay)), _EmissionSharpness);
                    interiorColor += bulbSpec * _EmissionColor.rgb * _EmissionIntensity;
                }
                else
                {
                    interiorColor = _HousingColor.rgb;
                }

                // ==========================================
                // 6. Composite
                // ==========================================
                float3 finalColor = interiorColor;
                // Add lens specular and fresnel on top
                finalColor += specular;
                finalColor += fresnel * 0.5; // subtle fresnel reflection

                fixed4 col = fixed4(finalColor, 1.0);
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
    FallBack "Unlit/Color"
}
