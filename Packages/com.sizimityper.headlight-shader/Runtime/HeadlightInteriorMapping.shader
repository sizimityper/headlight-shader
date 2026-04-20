Shader "Custom/HeadlightInteriorMapping"
{
    Properties
    {
        [Header(Lighting)]
        _ShadowStrength ("影の強さ", Range(0, 1)) = 0.5
        _MinBrightness ("最小明るさ", Range(0, 1)) = 0.1

        [Header(Lens Surface)]
        _MainTex ("ベースカラー (RGB)", 2D) = "white" {}
        _BaseColorStrength ("ベースカラー強度", Range(0, 1)) = 1.0
        _EdgeMask ("エッジマスク (R=トリム)", 2D) = "white" {}
        _SpecularPower ("鏡面ハイライトの鋭さ", Range(1, 256)) = 64
        _SpecularIntensity ("鏡面ハイライト強度", Range(0, 2)) = 0.8
        _FresnelPower ("フレネルパワー", Range(1, 10)) = 3.0
        _FresnelIntensity ("フレネル強度", Range(0, 1)) = 0.5
        _LensRoughness ("レンズ粗さ", Range(0, 1)) = 0.0

        [Header(Lens Flute Refraction)]
        _LensNormal ("レンズフルート法線", 2D) = "bump" {}
        _RefractionStrength ("屈折強度", Range(0, 1)) = 0.05

        [Header(Interior Mapping)]
        _BoxCenter ("ボックス中心 (オブジェクト空間)", Vector) = (0, 0, 0, 0)
        _BoxRotation ("ボックス回転 XYZ (度)", Vector) = (0, 0, 0, 0)
        _ScaleX ("ボックススケール X", Range(0.001, 0.5)) = 0.1
        _ScaleY ("ボックススケール Y", Range(0.001, 0.5)) = 0.1
        _ScaleZ ("ボックススケール Z", Range(0.001, 0.5)) = 0.1
        [KeywordEnum(Box, Ellipsoid, RoundedBox)] _InteriorShape ("内部形状", Float) = 0
        _FilletRadius ("フィレット半径", Range(0, 0.5)) = 0.1
        [Toggle(_SYMMETRIC_INTERIOR)] _SymmetricInterior ("内部を左右対称にする (Xミラー)", Float) = 0
        _InteriorBlur ("内部ぼかし", Range(0, 0.2)) = 0.05
        _InteriorBlurScale ("内部ぼかしスケール (大=細かい)", Range(5, 300)) = 80

        [Header(Interior)]
        _MatCap ("内部マットキャップ", 2D) = "white" {}
        _LensColor ("レンズカラー (全体乗算)", Color) = (1, 1, 1, 1)
        _BulbColor ("バルブカラー", Color) = (1, 0.5, 0, 1)
        _InteriorRoughness ("内部粗さ", Range(0, 1)) = 0.0
        _InteriorSaturation ("内部彩度", Range(0, 2)) = 1.0
        _FacetCount ("ファセット数 (XY)", Vector) = (8, 4, 0, 0)
        _FacetStrength ("ファセット強度", Range(0, 0.5)) = 0.1

        [Header(Bulb)]
        _BulbPosition ("バルブ位置 (XYZ, オブジェクト空間)", Vector) = (0, 0, -0.5, 0)
        _BulbRotation ("バルブ回転 XYZ (度)", Vector) = (0, 0, 0, 0)
        _BulbBodySize ("バルブ本体サイズ (半径)", Range(0.001, 0.1)) = 0.02
        _BulbBodyLength ("バルブ本体長さ (半分)", Range(0.001, 0.2)) = 0.05
        [Toggle(_BULBSHAPE_GLASS)] _BulbShapeGlass ("バルブ形状: スムースガラスカプセル", Float) = 0
        [IntRange] _BulbFacetN ("バルブのファセット数 (メタリックのみ)", Range(3, 16)) = 8
        _BulbRimPower ("バルブリムパワー (ガラスのみ)", Range(0.1, 16)) = 2
        _BulbReflectStrength ("バルブ色のリフレクター反映強度", Range(0, 5)) = 0.5
        _BulbReflectRadius ("バルブ色の反映半径", Range(0.001, 1)) = 0.2
        _BulbReflectFalloff ("バルブ色の反映減衰", Range(0.1, 10)) = 1
        _EmissionIntensity ("発光強度", Range(0, 50)) = 0.0
        _EmissionSharpness ("発光の鋭さ", Range(1, 128)) = 16

    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100

        Pass
        {
            Tags { "LightMode" = "ForwardBase" }
            ZWrite On
            ZTest LEqual
            Cull Back

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase
            #pragma multi_compile_instancing
            #pragma target 3.0
            #pragma shader_feature _INTERIORSHAPE_BOX _INTERIORSHAPE_ELLIPSOID _INTERIORSHAPE_ROUNDEDBOX
            #pragma shader_feature _SYMMETRIC_INTERIOR
            #pragma shader_feature _BULBSHAPE_GLASS

            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"
            #ifndef UNITY_SPECCUBE_LOD_STEPS
                #define UNITY_SPECCUBE_LOD_STEPS 6
            #endif

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 uvs : TEXCOORD0;     // xy=lensNormal, zw=mainTex
                float3 worldPos : TEXCOORD1;
                float3 worldNormal : TEXCOORD2;
                float3 objTangent : TEXCOORD3;
                float3 objBitangent : TEXCOORD4;
                float3 objNormal : TEXCOORD5;
                float3 objectPos : TEXCOORD6;
                float3 objectViewDir : TEXCOORD7;
                UNITY_FOG_COORDS(8)
                SHADOW_COORDS(9)
                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float _BaseColorStrength;

            sampler2D _LensNormal;
            float4 _LensNormal_ST;

            float _SpecularPower;
            float _SpecularIntensity;
            float _ShadowStrength;
            float _MinBrightness;
            float _FresnelPower;
            float _FresnelIntensity;
            sampler2D _EdgeMask;
            float4 _EdgeMask_ST;
            float _LensRoughness;
            float _RefractionStrength;

            float _FilletRadius;
            float4 _BoxCenter;
            float4 _BoxRotation;
            float _ScaleX;
            float _ScaleY;
            float _ScaleZ;
            float _InteriorBlur;
            float _InteriorBlurScale;
            sampler2D _MatCap;
            float4 _LensColor;
            float4 _BulbColor;
            float _InteriorRoughness;
            float _InteriorSaturation;
            float4 _FacetCount;
            float _FacetStrength;

            float4 _BulbPosition;
            float4 _BulbRotation;
            float _BulbBodySize;
            float _BulbBodyLength;
            float _BulbFacetN;
            float _BulbRimPower;
            float _BulbReflectStrength;
            float _BulbReflectRadius;
            float _BulbReflectFalloff;
            float _EmissionIntensity;
            float _EmissionSharpness;

            v2f vert(appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uvs.xy = TRANSFORM_TEX(v.uv, _LensNormal);
                o.uvs.zw = TRANSFORM_TEX(v.uv, _MainTex);
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
                TRANSFER_SHADOW(o);
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

            // 2D SDF for regular N-gon (circumradius r)
            float sdNGon2D(float2 p, float r, int n)
            {
                float an = UNITY_PI / float(n);
                float sector = UNITY_TWO_PI / float(n);
                float bn = fmod(atan2(p.y, p.x) + UNITY_TWO_PI * 5.0, sector) - an;
                float2 q = length(p) * float2(cos(bn), abs(sin(bn)));
                q.x -= r * cos(an);
                q.y += clamp(-q.y, 0.0, r * sin(an));
                return length(q) * sign(q.x);
            }

            // 3D SDF for N-gon capsule (Z-aligned, half-length h, circumradius r)
            float sdNGonCapsule(float3 p, float r, float h, int n)
            {
                float dXY = sdNGon2D(p.xy, r, n);
                float dZ = max(abs(p.z) - h, 0.0);
                return length(float2(max(dXY, 0.0), dZ)) + min(dXY, 0.0);
            }

            float sdCapsule(float3 p, float r, float h)
            {
                float3 q = p;
                q.z -= clamp(q.z, -h, h);
                return length(q) - r;
            }

            float3 sdCapsuleNormal(float3 p, float h)
            {
                float3 q = p;
                q.z -= clamp(q.z, -h, h);
                return normalize(q);
            }

            float sdRoundBox(float3 p, float3 b, float r)
            {
                float3 q = abs(p) - b + r;
                return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
            }

            bool interiorMappingRoundedBox(float3 rayOrigin, float3 rayDir, float3 halfExtents, float filletR,
                                           out float3 hitPos, out float3 hitNormal, out float2 hitUV)
            {
                if (sdRoundBox(rayOrigin, halfExtents, filletR) >= 0.0)
                {
                    hitPos = float3(0, 0, 0); hitNormal = float3(0, 0, 1); hitUV = float2(0.5, 0.5);
                    return false;
                }

                float t = 0.0;
                float3 p = rayOrigin;
                [loop]
                for (int i = 0; i < 24; i++)
                {
                    float d = sdRoundBox(p, halfExtents, filletR);
                    if (d >= -0.001) break;
                    t += -d;
                    p = rayOrigin + rayDir * t;
                }

                hitPos = p;

                // Analytical gradient of rounded box SDF
                float3 q = abs(p) - halfExtents + filletR;
                float3 m = max(q, 0.0);
                float3 grad;
                if (dot(m, m) > 1e-6)
                    grad = m / length(m);
                else
                    grad = float3(q.x >= q.y && q.x >= q.z ? 1.0 : 0.0,
                                  q.y >  q.x && q.y >= q.z ? 1.0 : 0.0,
                                  q.z >  q.x && q.z >  q.y ? 1.0 : 0.0);
                hitNormal = normalize(sign(p) * grad);

                float3 absN = abs(hitNormal);
                if (absN.z >= absN.x && absN.z >= absN.y)
                    hitUV = p.xy / halfExtents.xy * 0.5 + 0.5;
                else if (absN.x >= absN.y)
                    hitUV = p.zy / halfExtents.zy * 0.5 + 0.5;
                else
                    hitUV = p.xz / halfExtents.xz * 0.5 + 0.5;

                return true;
            }

            // Ellipsoid interior mapping: ray-ellipsoid intersection (ray origin assumed inside)
            bool interiorMappingEllipsoid(float3 rayOrigin, float3 rayDir, float3 semiAxes,
                                          out float3 hitPos, out float3 hitNormal, out float2 hitUV)
            {
                float3 u = rayOrigin / semiAxes;
                float3 v = rayDir / semiAxes;
                float A = dot(v, v);
                float B = dot(u, v);
                float C = dot(u, u) - 1.0;
                float disc = B * B - A * C;
                if (disc < 0.0)
                {
                    hitPos = float3(0, 0, 0);
                    hitNormal = float3(0, 0, 1);
                    hitUV = float2(0.5, 0.5);
                    return false;
                }
                float t = (-B + sqrt(disc)) / A;
                if (t < 0.0)
                {
                    hitPos = float3(0, 0, 0);
                    hitNormal = float3(0, 0, 1);
                    hitUV = float2(0.5, 0.5);
                    return false;
                }
                hitPos = rayOrigin + rayDir * t;
                hitNormal = normalize(hitPos / (semiAxes * semiAxes));
                float3 unitHit = normalize(hitPos / semiAxes);
                hitUV = float2(atan2(unitHit.x, unitHit.z) / (2.0 * UNITY_PI) + 0.5,
                               unitHit.y * 0.5 + 0.5);
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

            float2 getMatcapUV(float3 worldNorm)
            {
                float3 viewN = normalize(mul((float3x3)UNITY_MATRIX_V, worldNorm));
                return viewN.xy * 0.5 + 0.5;
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

            float4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                float3 worldViewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 worldNormal = normalize(i.worldNormal);

                // ==========================================
                // 1. Lens surface lighting (smooth)
                // ==========================================
                // Directional specular using scene main light
                float3 lightDir = normalize(_WorldSpaceLightPos0.xyz + float3(0, 1e-6, 0));
                float3 lightColor = _LightColor0.rgb;
                float lightLuma = dot(lightColor, float3(0.2126, 0.7152, 0.0722));
                float lightOn = step(0.001, lightLuma);
                #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
                    float shadowAtten = lightOn;
                #else
                    float shadowAtten = saturate(SHADOW_ATTENUATION(i)) * lightOn;
                #endif
                float shadowFactor = max(lerp(1.0, shadowAtten, _ShadowStrength), _MinBrightness);
                float3 hvec = worldViewDir + lightDir;
                float3 halfVec = dot(hvec, hvec) > 0.0001 ? normalize(hvec) : worldNormal;
                float NdotH = saturate(dot(worldNormal, halfVec));
                float specular = pow(NdotH, _SpecularPower) * _SpecularIntensity * lightLuma;

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
                float3 lensNormalTS = UnpackNormal(tex2D(_LensNormal, i.uvs.xy));
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
                float3 boxScale = float3(_ScaleX, _ScaleY, _ScaleZ);
                float3x3 rot = boxRotationMatrix(_BoxRotation.xyz);

                // オブジェクト空間でX=0を鏡面として折り返す：ボックスが+X側に設定されていれば
                // -X側にも対称複製される（左右のライトを同じマテリアルで共用できる）
                #if _SYMMETRIC_INTERIOR
                float xSign = i.objectPos.x >= 0 ? 1.0 : -1.0;
                float3 symObjectPos = float3(abs(i.objectPos.x), i.objectPos.y, i.objectPos.z);
                float3 symInteriorRay = float3(interiorRay.x * xSign, interiorRay.y, interiorRay.z);
                float3 localRayOrigin = mul(rot, symObjectPos - _BoxCenter.xyz);
                float3 localInteriorRay = mul(rot, symInteriorRay);
                #else
                float3 localRayOrigin = mul(rot, i.objectPos - _BoxCenter.xyz);
                float3 localInteriorRay = mul(rot, interiorRay);
                #endif

                float3 hitPos;
                float3 hitNormal;
                float2 hitUV;

                #if _INTERIORSHAPE_ELLIPSOID
                bool hit = interiorMappingEllipsoid(localRayOrigin, localInteriorRay, boxScale,
                                                    hitPos, hitNormal, hitUV);
                #elif _INTERIORSHAPE_ROUNDEDBOX
                bool hit = interiorMappingRoundedBox(localRayOrigin, localInteriorRay, boxScale, _FilletRadius,
                                                     hitPos, hitNormal, hitUV);
                #else
                bool hit = interiorMapping(localRayOrigin, localInteriorRay, boxScale,
                                           hitPos, hitNormal, hitUV);
                #endif

                // Bulb body: N-gon capsule via SDF sphere tracing
                #if _SYMMETRIC_INTERIOR
                float3 symBulbPos = float3(abs(_BulbPosition.x), _BulbPosition.y, _BulbPosition.z);
                float3 bulbBoxLocal = mul(rot, symBulbPos - _BoxCenter.xyz);
                #else
                float3 bulbBoxLocal = mul(rot, _BulbPosition.xyz - _BoxCenter.xyz);
                #endif
                float3x3 bulbRot = boxRotationMatrix(_BulbRotation.xyz);
                float bulbT = 0.0;
                bool bulbHit = false;
                float3 bulbHitNormal = float3(0, 0, 1);
                float maxBulbDist = length(boxScale) * 3.0;
                [loop]
                for (int bi = 0; bi < 24; bi++)
                {
                    float3 bp = mul(bulbRot, localRayOrigin + localInteriorRay * bulbT - bulbBoxLocal);
                    #if _BULBSHAPE_GLASS
                    float bd = sdCapsule(bp, _BulbBodySize, _BulbBodyLength);
                    #else
                    float bd = sdNGonCapsule(bp, _BulbBodySize, _BulbBodyLength, int(round(_BulbFacetN)));
                    #endif
                    if (bd < 0.001) { bulbHit = true; break; }
                    if (bulbT > maxBulbDist) break;
                    bulbT += bd;
                }
                if (bulbHit)
                {
                    float3 hp = mul(bulbRot, localRayOrigin + localInteriorRay * bulbT - bulbBoxLocal);
                    #if _BULBSHAPE_GLASS
                    bulbHitNormal = normalize(mul(transpose(bulbRot), sdCapsuleNormal(hp, _BulbBodyLength)));
                    #else
                    float e = 0.001;
                    int bulbN = int(round(_BulbFacetN));
                    float3 bulbGrad = float3(
                        sdNGonCapsule(hp + float3(e,0,0), _BulbBodySize, _BulbBodyLength, bulbN) -
                        sdNGonCapsule(hp - float3(e,0,0), _BulbBodySize, _BulbBodyLength, bulbN),
                        sdNGonCapsule(hp + float3(0,e,0), _BulbBodySize, _BulbBodyLength, bulbN) -
                        sdNGonCapsule(hp - float3(0,e,0), _BulbBodySize, _BulbBodyLength, bulbN),
                        sdNGonCapsule(hp + float3(0,0,e), _BulbBodySize, _BulbBodyLength, bulbN) -
                        sdNGonCapsule(hp - float3(0,0,e), _BulbBodySize, _BulbBodyLength, bulbN)
                    );
                    bulbHitNormal = normalize(mul(transpose(bulbRot), bulbGrad));
                    #endif
                }
                float wallT = hit ? dot(hitPos - localRayOrigin, localInteriorRay) : 1e9;

                // ==========================================
                // 4. リフレクター / ハウジング シェーディング
                // ==========================================
                float3 interiorColor = float3(0, 0, 0);
                float3 emissionAdd = float3(0, 0, 0);

                if (hit)
                {
                    float3 facetN = computeFacetNormal(hitUV, _FacetCount.xy, _FacetStrength);
                    float3 perturbedNormal = normalize(hitNormal + facetN);
                    float3 perturbedNormalOS = mul(transpose(rot), perturbedNormal);
                    float3 worldPerturbedN = normalize(mul((float3x3)unity_ObjectToWorld, perturbedNormalOS));

                    float3 envColor = tex2D(_MatCap, getMatcapUV(worldPerturbedN)).rgb;
                    float envLuma = dot(envColor, float3(0.2126, 0.7152, 0.0722));
                    interiorColor = lerp(envColor, envLuma.xxx, 1.0 - _InteriorSaturation);

                    // ==========================================
                    // 5. バルブ発光のリフレクター反射
                    // ==========================================
                    float3 toBulb = normalize(bulbBoxLocal - hitPos);
                    float3 reflectedBulb = reflect(-toBulb, perturbedNormal);
                    float bulbSpec = pow(saturate(dot(reflectedBulb, -localInteriorRay)), _EmissionSharpness);
                    emissionAdd += bulbSpec * _BulbColor.rgb * _EmissionIntensity;

                    // バルブ色のリフレクター近接染め
                    float bulbDist = saturate(length(hitPos - bulbBoxLocal) / _BulbReflectRadius);
                    float bulbProximity = pow(smoothstep(1.0, 0.0, bulbDist), _BulbReflectFalloff);
                    interiorColor += interiorColor * _BulbColor.rgb * bulbProximity * _BulbReflectStrength;
                }
                else
                {
                    float3 housingEnvColor = tex2D(_MatCap, getMatcapUV(worldNormal)).rgb;
                    float housingLuma = dot(housingEnvColor, float3(0.2126, 0.7152, 0.0722));
                    interiorColor = lerp(housingEnvColor, housingLuma.xxx, 1.0 - _InteriorSaturation);
                }

                // ==========================================
                // 6. バルブ シェーディング
                // ==========================================
                if (bulbHit && bulbT < wallT)
                {
                    float3 bulbNormalOS = mul(transpose(rot), bulbHitNormal);
                    float3 bulbWorldN = normalize(mul((float3x3)unity_ObjectToWorld, bulbNormalOS));
                    if (dot(bulbWorldN, worldViewDir) < 0.0) bulbWorldN = -bulbWorldN;

                    #if _BULBSHAPE_GLASS
                    float bulbNdotV = saturate(dot(bulbWorldN, worldViewDir));
                    interiorColor = interiorColor * _BulbColor.rgb * pow(bulbNdotV, _BulbRimPower);
                    #else
                    float3 bulbEnvColor = tex2D(_MatCap, getMatcapUV(bulbWorldN)).rgb;
                    float bulbEnvLuma = dot(bulbEnvColor, float3(0.2126, 0.7152, 0.0722));
                    interiorColor = lerp(bulbEnvColor, bulbEnvLuma.xxx, 1.0 - _InteriorSaturation) * _BulbColor.rgb;
                    #endif

                    emissionAdd += _BulbColor.rgb * _EmissionIntensity;
                }

                // ==========================================
                // 7. コンポジット
                // ==========================================
                float3 shAmbient = max(ShadeSH9(float4(worldNormal, 1.0)), 0.0);
                float ambientLuma = dot(shAmbient, float3(0.2126, 0.7152, 0.0722));

                float3 baseColor = tex2D(_MainTex, i.uvs.zw).rgb;
                float edgeMask = tex2D(_EdgeMask, i.uvs.zw).r;
                float3 finalColor = interiorColor * lerp(1.0, baseColor, _BaseColorStrength) * shadowFactor * edgeMask;
                finalColor += specular;
                finalColor += fresnel * lensEnvColor * shadowFactor;
                finalColor += emissionAdd * edgeMask;
                finalColor *= _LensColor.rgb;

                // NaN guard: max(NaN, 0) = 0 on DirectX 11+ hardware
                finalColor = max(finalColor, float3(0, 0, 0));
                float4 col = float4(finalColor, 1.0);
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
        Pass
        {
            Tags { "LightMode" = "ForwardAdd" }
            Blend One One
            ZWrite Off

            CGPROGRAM
            #pragma vertex vertAdd
            #pragma fragment fragAdd
            #pragma multi_compile_fwdadd_fullshadows
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #pragma target 3.0

            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            struct appdataAdd
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2fAdd
            {
                float4 pos : SV_POSITION;
                float3 worldPos : TEXCOORD0;
                float3 worldNormal : TEXCOORD1;
                UNITY_FOG_COORDS(2)
                LIGHTING_COORDS(3, 4)
                UNITY_VERTEX_OUTPUT_STEREO
            };

            float _SpecularPower;
            float _SpecularIntensity;
            float _FresnelPower;
            float _FresnelIntensity;
            float4 _LensColor;

            v2fAdd vertAdd(appdataAdd v)
            {
                v2fAdd o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.pos = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.worldNormal = UnityObjectToWorldNormal(v.normal);
                UNITY_TRANSFER_FOG(o, o.pos);
                TRANSFER_VERTEX_TO_FRAGMENT(o);
                return o;
            }

            float4 fragAdd(v2fAdd i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                float3 worldViewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 worldNormal = normalize(i.worldNormal);

                #ifdef USING_DIRECTIONAL_LIGHT
                    float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
                #else
                    float3 lightDir = normalize(_WorldSpaceLightPos0.xyz - i.worldPos);
                #endif

                UNITY_LIGHT_ATTENUATION(atten, i, i.worldPos);
                float3 lightColor = _LightColor0.rgb;

                // Specular highlight on lens surface
                float3 halfVec = normalize(worldViewDir + lightDir);
                float NdotH = saturate(dot(worldNormal, halfVec));
                float spec = pow(NdotH, _SpecularPower) * _SpecularIntensity;

                // Fresnel with additional light
                float NdotV = saturate(dot(worldNormal, worldViewDir));
                float fresnel = pow(1.0 - NdotV, _FresnelPower) * _FresnelIntensity;

                // Subtle interior brightening (light passing through lens)
                float NdotL = saturate(dot(worldNormal, lightDir));
                float3 interiorAdd = _LensColor.rgb * NdotL * 0.3;

                float3 finalColor = (spec + fresnel + interiorAdd) * lightColor * atten;

                float4 col = float4(finalColor, 1.0);
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
        Pass
        {
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ZTest LEqual
            Cull Back

            CGPROGRAM
            #pragma vertex vertShadow
            #pragma fragment fragShadow
            #pragma multi_compile_shadowcaster
            #pragma multi_compile_instancing
            #include "UnityCG.cginc"

            struct appdataShadow
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2fShadow
            {
                V2F_SHADOW_CASTER;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            v2fShadow vertShadow(appdataShadow v)
            {
                v2fShadow o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                TRANSFER_SHADOW_CASTER_NORMALOFFSET(o);
                return o;
            }

            float4 fragShadow(v2fShadow i) : SV_Target
            {
                SHADOW_CASTER_FRAGMENT(i);
            }
            ENDCG
        }
    }
    FallBack Off
}
