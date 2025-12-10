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
            // Need 4.5+/5.0 for StructuredBuffer
            #pragma target 5.0
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

            // ----------- GPU sphere struct & buffer ------------

            // Must match SphereData layout in C#
            struct SphereGPU
            {
                float3 position;
                float  radius;

                float3 colour;
                float  pad0;

                float3 emission;
                float  emissionStrength;
            };

            StructuredBuffer<SphereGPU> _Spheres;
            int NumSpheres;

            // ---- Triangles ----
            struct TriangleData
            {
                float3 v0;
                float  pad0;

                float3 v1;
                float  pad1;

                float3 v2;
                float  pad2;

                float3 normal;
                float  pad3;

                float3 colour;
                float  pad4;

                float3 emission;
                float  emissionStrength;
            };

            StructuredBuffer<TriangleData> _Triangles;
            int NumTriangles;
            int    MaxBounces;
            int    raysPerPixel;
            float2 numPixels;

            // ---------------------------------------------------

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

            HitInfo RaySphere(Ray ray, SphereGPU sphere)
            {
                HitInfo h = (HitInfo)0;

                float3 oc = ray.origin - sphere.position;
                float a = dot(ray.dir, ray.dir);
                float b = 2.0 * dot(oc, ray.dir);
                float c = dot(oc, oc) - sphere.radius * sphere.radius;
                float d = b*b - 4.0*a*c;
                if (d < 0.0) return h;

                float s = sqrt(d);
                float t = (-b - s) / (2.0 * a);
                if (t < 0.0) t = (-b + s) / (2.0 * a);
                if (t < 0.0) return h;

                h.didHit = true;
                h.dst = t;
                h.hitPoint = ray.origin + ray.dir * t;
                h.normal = normalize(h.hitPoint - sphere.position);

                // Fill material from sphere data
                h.material.colour = sphere.colour;
                h.material.emission = sphere.emission;
                h.material.emissionStrength = sphere.emissionStrength;

                return h;
            }

            // -------- FIXED TRIANGLE INTERSECTION --------
            HitInfo RayTriangle(Ray ray, TriangleData tri)
            {
                HitInfo h = (HitInfo)0;

                float3 edgeAB = tri.v1 - tri.v0;
                float3 edgeAC = tri.v2 - tri.v0;
                float3 normalVector = cross(edgeAB, edgeAC);

                float determinant = -dot(ray.dir, normalVector);

                // Ray parallel or back-facing: no hit
                if (determinant < 1e-6)
                    return h;

                float invDet = 1.0 / determinant;

                float3 ao  = ray.origin - tri.v0;
                float3 dao = cross(ao, ray.dir);

                float dst = dot(ao, normalVector) * invDet;
                float u   = dot(edgeAC, dao) * invDet;
                float v   = -dot(edgeAB, dao) * invDet;
                float w   = 1.0 - u - v;

                // Outside triangle or behind ray origin
                if (dst < 0.0 || u < 0.0 || v < 0.0 || w < 0.0)
                    return h;

                h.didHit  = true;
                h.dst     = dst;
                h.hitPoint = ray.origin + ray.dir * dst;

                // Use provided triangle normal (already averaged in C#)
                h.normal = normalize(tri.normal);

                // Material from triangle data
                h.material.colour            = tri.colour;
                h.material.emission          = tri.emission;
                h.material.emissionStrength  = tri.emissionStrength;

                return h;
            }

            HitInfo CalculateRayCollision(Ray ray)
            {
                HitInfo closest = (HitInfo)0;
                closest.dst = 1e20;

                // Spheres
                [loop]
                for (int i = 0; i < NumSpheres; i++)
                {
                    SphereGPU s = _Spheres[i];
                    HitInfo h = RaySphere(ray, s);
                    if (h.didHit && h.dst < closest.dst)
                    {
                        closest = h;
                    }
                }

                // Triangles
                [loop]
                for (int i = 0; i < NumTriangles; i++)
                {
                    TriangleData tri = _Triangles[i];
                    HitInfo h = RayTriangle(ray, tri);
                    if (h.didHit && h.dst < closest.dst)
                    {
                        closest = h;
                    }
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
                float rho = sqrt(-2 * log(max(1e-7, RandomValue(state))));
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
                float3 incoming   = 0;
                float3 throughput = 1;

                // Safety clamp on the shader side too
                int maxB;
                if (MaxBounces < 1)
                {
                    maxB = 1;
                }
                else
                {
                    maxB = MaxBounces;
                }

                [loop]
                for (int bounce = 0; bounce < maxB; bounce++)
                {
                    HitInfo h = CalculateRayCollision(ray);

                    if (!h.didHit)
                    {
                        // Hit sky
                        incoming += GetEnvironmentColour(ray) * throughput;
                        break;
                    }

                    // Move origin slightly along the normal to avoid self-intersection
                    ray.origin = h.hitPoint + h.normal * 1e-3;
                    // Cosine-ish diffuse bounce
                    ray.dir    = normalize(h.normal + RandomDirection(state));

                    // Add emission
                    float3 emitted = h.material.emission * h.material.emissionStrength;
                    incoming += emitted * throughput;

                    // Multiply by surface albedo
                    throughput *= h.material.colour;

                    // Early out if contribution is tiny
                    float maxChannel = max(throughput.x, max(throughput.y, throughput.z));
                    if (maxChannel < 0.001)
                        break;

                    // -------------------------
                    // Russian roulette
                    // -------------------------
                    if (bounce >= 3)  // only after a few bounces
                    {
                        float p = saturate(maxChannel);  // survival probability
                        float r = RandomValue(state);
                        if (r > p)
                        {
                            // Path dies
                            break;
                        }

                        // If it survives, compensate
                        throughput /= p;
                    }
                }

                return incoming;
            }

            float4 frag (v2f i) : SV_Target
            {
                float3 camPos     = mul(CamLocalToWorldMatrix, float4(0,0,0,1)).xyz;
                float3 camForward = normalize(mul(CamLocalToWorldMatrix, float4(0,0,1,0)).xyz);
                float3 camRight   = normalize(mul(CamLocalToWorldMatrix, float4(1,0,0,0)).xyz);
                float3 camUp      = normalize(mul(CamLocalToWorldMatrix, float4(0,1,0,0)).xyz);

                uint state = asuint(i.uv.x * 1234.567) ^ asuint(i.uv.y * 3456.789);

                float3 col = 0;
                int spp = max(1, raysPerPixel);

                [loop]
                for (int s = 0; s < spp; s++)
                {
                    float2 jitter = RandomPointInCircle(state) / numPixels;
                    float2 uv = i.uv + jitter;
                    uv = clamp(uv, 0.0, 1.0);

                    float2 ndc = uv * 2.0 - 1.0;

                    float3 dirLocal = normalize(float3(
                        ndc.x * viewParams.x,
                        ndc.y * viewParams.y,
                        1.0
                    ));

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
                col = col / (1.0 + col);   // simple tonemap
                col = saturate(col);

                return float4(col, 1.0);
            }
            ENDCG
        }
    }
}