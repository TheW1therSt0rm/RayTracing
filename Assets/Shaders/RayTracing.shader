// Assets/Shaders/RayTracing.shader
Shader "RayTracing"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata { float4 vertex: POSITION; float2 uv: TEXCOORD0; };
            struct v2f { float2 uv: TEXCOORD0; float4 vertex: SV_POSITION; };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            float3 viewParams;                // x = tan(fov/2)*aspect, y = tan(fov/2)
            float4x4 CamLocalToWorldMatrix;

            struct Ray { float3 origin; float3 dir; };

            struct RayTracingMaterial
            {
                float3 colour;
                float3 emission;
                float emissionStrength;
            };

            struct HitInfo
            {
                bool didHit;
                float dst;
                float3 hitPoint;
                float3 normal;
                RayTracingMaterial material;
            };

            struct Sphere
            {
                float3 position;
                float radius;
                RayTracingMaterial material;
            };

            struct Tri
            {
                float3 posA;
                float3 posB;
                float3 posC;
                float3 colour;
                float3 normalA;
                float3 normalB;
                float3 normalC;
            };

            float RaySphereDist(Ray ray, float3 sphereCenter, float sphereRadius)
            {
                float3 oc = ray.origin - sphereCenter;
                float a = dot(ray.dir, ray.dir);
                float b = 2.0 * dot(oc, ray.dir);
                float c = dot(oc, oc) - sphereRadius * sphereRadius;
                float d = b*b - 4.0*a*c;
                if (d < 0.0) return -1.0;
                float s = sqrt(d);
                float t0 = (-b - s) / (2.0 * a);
                float t1 = (-b + s) / (2.0 * a);
                float t = t0;
                if (t < 0.0) t = t1;
                if (t < 0.0) return -1.0;
                return t;
            }

            HitInfo RaySphere(Ray ray, float3 sphereCenter, float sphereRadius)
            {
                HitInfo h = (HitInfo)0;
                float3 oc = ray.origin - sphereCenter;
                float a = dot(ray.dir, ray.dir);
                float b = 2.0 * dot(oc, ray.dir);
                float c = dot(oc, oc) - sphereRadius * sphereRadius;
                float d = b*b - 4.0*a*c;
                if (d < 0.0) return h;
                float s = sqrt(d);
                float t = (-b - s) / (2.0 * a);
                if (t < 0.0) t = (-b + s) / (2.0 * a);
                if (t < 0.0) return h;
                h.didHit = true;
                h.dst = t;
                h.hitPoint = ray.origin + ray.dir * t;
                h.normal = normalize(h.hitPoint - sphereCenter);
                return h;
            }

            // --- FIXED: robust, double-sided Möller–Trumbore ---
            HitInfo RayTriangle(Ray ray, Tri tri)
            {
                const float EPS = 1e-6;

                float3 edge1 = tri.posB - tri.posA;
                float3 edge2 = tri.posC - tri.posA;

                float3 pvec = cross(ray.dir, edge2);
                float det = dot(edge1, pvec);

                // Double-sided: reject only near-parallel
                if (abs(det) < EPS)
                {
                    HitInfo none = (HitInfo)0;
                    return none;
                }

                float invDet = 1.0 / det;

                float3 tvec = ray.origin - tri.posA;
                float u = dot(tvec, pvec) * invDet;
                if (u < 0.0 || u > 1.0)
                {
                    HitInfo none = (HitInfo)0;
                    return none;
                }

                float3 qvec = cross(tvec, edge1);
                float v = dot(ray.dir, qvec) * invDet;
                if (v < 0.0 || u + v > 1.0)
                {
                    HitInfo none = (HitInfo)0;
                    return none;
                }

                float t = dot(edge2, qvec) * invDet;
                if (t <= 0.0)
                {
                    HitInfo none = (HitInfo)0;
                    return none;
                }

                float w = 1.0 - u - v;

                HitInfo hit = (HitInfo)0;
                hit.didHit = true;
                hit.dst = t;
                hit.hitPoint = ray.origin + ray.dir * t;

                // Interpolate supplied per-vertex normals
                float3 n = normalize(tri.normalA * w + tri.normalB * u + tri.normalC * v);
                // Ensure geometric consistency: flip if needed so normal opposes incoming ray
                n = dot(n, ray.dir) > 0 ? -n : n;
                hit.normal = n;

                // Simple material: visualize normal
                hit.material.colour = float3(1, 1, 1);
                hit.material.emission = 0;
                hit.material.emissionStrength = 0;
                return hit;
            }

            float3 SphereCols[64];
            float3 SphereEmissions[64];
            float  SphereEmissionStrengths[64];
            float3 SpherePositions[64];
            float  SphereRadiuses[64];
            int    NumSpheres;
            int    MaxBounces;
            int    raysPerPixel;
            float2 numPixels;

            HitInfo CalculateRayCollision(Ray ray)
            {
                // A small triangle in front of the camera (z=0), high enough to be visible with typical FOV.
                Tri meshP = (Tri)0;
                meshP.posA = float3(-3, 7, 0);
                meshP.posB = float3( 3, 7, 0);
                meshP.posC = float3( 3, 13, 0);
                meshP.normalA = normalize(float3(0, -1.0, 0));
                meshP.normalB = normalize(float3(0, -1.0, 0));
                meshP.normalC = normalize(float3(0, -1.0, 0));

                HitInfo closest = (HitInfo)0;
                closest.dst = 1e20;

                // Spheres
                [loop]
                for (int i = 0; i < NumSpheres; i++)
                {
                    HitInfo h = RaySphere(ray, SpherePositions[i], SphereRadiuses[i]);
                    if (h.didHit && h.dst < closest.dst)
                    {
                        RayTracingMaterial m;
                        m.colour = SphereCols[i];
                        m.emission = SphereEmissions[i];
                        m.emissionStrength = SphereEmissionStrengths[i];
                        h.material = m;
                        closest = h;
                    }
                }

                // Triangle
                HitInfo triHit = RayTriangle(ray, meshP);
                if (triHit.didHit && triHit.dst < closest.dst)
                {
                    closest = triHit;
                }

                return closest;
            }

            float RandomValue(inout uint state)
            {
                state = state * 747796405u + 2891336453u;
                uint result = ((state >> ((state >> 28) + 4)) ^ state) * 277803737u;
                result = (result >> 22) ^ result;
                return result / 4294967295.0;
            }

            float RandomValueNormal(inout uint state)
            {
                float theta = 6.2831853 * RandomValue(state);
                float rho = sqrt(-2 * log(max(1e-7, RandomValue(state)))); // guard zero
                return rho * cos(theta);
            }

            float3 RandomDirection(inout uint state)
            {
                float x = RandomValueNormal(state);
                float y = RandomValueNormal(state);
                float z = RandomValueNormal(state);
                return normalize(float3(x, y, z));
            }

            float3 RandomHemisphereDirection(float3 normal, inout uint state)
            {
                float3 d = RandomDirection(state);
                return d * sign(dot(normal, d));
            }
            
            static const float PI = 3.1415;

            float2 RandomPointInCircle(inout uint state)
            {
                float angle = RandomValue(state) * 2 * PI;
                float2 pointOnCircle = float2(cos(angle), sin(angle));
                return pointOnCircle * sqrt(RandomValue(state));
            }

            float3 GetEnvironmentColour(Ray ray)
            {
                float t = pow(smoothstep(0, 0.4, ray.dir.y), 0.35);
                float3 sky = lerp(float3(0.6,0.8,1.0), float3(0.1,0.2,0.4), t);
                float sun = pow(max(0, dot(ray.dir, -normalize(float3(1,1,0)))), 200) * 3;
                float a = smoothstep(-0.1, 0, ray.dir.y);
                float sunMask = a >= 1;
                return lerp(float3(0.2,0.1,0.8), sky, a) + sun * sunMask;
            }

            float3 Trace(Ray ray, inout uint state)
            {
                float3 incoming = 0;
                float3 throughput = 1;

                [loop]
                for (int i = 0; i < MaxBounces + 1; i++)
                {
                    HitInfo h = CalculateRayCollision(ray);
                    if (h.didHit)
                    {
                        ray.origin = h.hitPoint;
                        // Cosine-ish diffuse bounce
                        ray.dir = normalize(h.normal + RandomDirection(state));

                        float3 emitted = h.material.emission * h.material.emissionStrength;
                        incoming += emitted * throughput;
                        throughput *= h.material.colour;
                    }
                    else
                    {
                        incoming += GetEnvironmentColour(ray) * throughput;
                        break;
                    }
                }
                return incoming;
            }

            float4 frag (v2f i) : SV_Target
            {
                // Camera basis in world space
                float3 camPos     = mul(CamLocalToWorldMatrix, float4(0,0,0,1)).xyz;
                float3 camForward = normalize(mul(CamLocalToWorldMatrix, float4(0,0,1,0)).xyz);
                float3 camRight   = normalize(mul(CamLocalToWorldMatrix, float4(1,0,0,0)).xyz);
                float3 camUp      = normalize(mul(CamLocalToWorldMatrix, float4(0,1,0,0)).xyz);

                // Stable per-pixel RNG seed
                uint state = asuint(i.uv.x * 1234.567) ^ asuint(i.uv.y * 3456.789);

                float3 col = 0;
                int spp = max(1, raysPerPixel);

                [loop]
                for (int s = 0; s < spp; s++)
                {
                    // Subpixel jitter in *UV space*
                    // RandomPointInCircle gives roughly [-1,1] radius; scale by pixel size
                    float2 jitter = RandomPointInCircle(state) / numPixels;

                    float2 uv = i.uv + jitter;
                    uv = clamp(uv, 0.0, 1.0); // just in case

                    // NDC [-1,1]
                    float2 ndc = uv * 2.0 - 1.0;

                    // Build a ray direction in camera space
                    // viewParams.x = tan(fov/2)*aspect, viewParams.y = tan(fov/2)
                    float3 dirLocal = normalize(float3(
                        ndc.x * viewParams.x,
                        ndc.y * viewParams.y,
                        1.0
                    ));

                    // Convert to world space using camera basis
                    float3 dirWorld = normalize(
                        dirLocal.x * camRight +
                        dirLocal.y * camUp +
                        dirLocal.z * camForward
                    );

                    Ray ray;
                    ray.origin = camPos;
                    ray.dir    = dirWorld;

                    col += Trace(ray, state);
                }

                col /= spp;

                // Simple clamp / tonemap so it doesn’t blow up visually
                col = col / (1.0 + col);   // Reinhard-ish
                col = saturate(col);

                return float4(col, 1.0);   // solid alpha
            }
            ENDCG
        }
    }
}