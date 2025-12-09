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
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            float3 viewParams;
            float4x4 CamLocalToWorldMatrix;

            struct Ray {
                float3 origin;
                float3 dir;
            };

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

            float RaySphereDist(Ray ray, float3 sphereCenter, float sphereRadius)
            {
                float3 oc = ray.origin - sphereCenter;

                float a = dot(ray.dir, ray.dir);
                float b = 2.0 * dot(oc, ray.dir);
                float c = dot(oc, oc) - sphereRadius * sphereRadius;

                float discriminant = b * b - 4.0 * a * c;

                if (discriminant < 0.0)
                    return -1.0;

                float sqrtD = sqrt(discriminant);

                float t0 = (-b - sqrtD) / (2.0 * a);
                float t1 = (-b + sqrtD) / (2.0 * a);

                // pick the smallest positive t
                float t = t0;
                if (t < 0.0) t = t1;
                if (t < 0.0) return -1.0;

                return t;
            }

            HitInfo RaySphere(Ray ray, float3 sphereCenter, float sphereRadius)
            {
                HitInfo hitInfo = (HitInfo)0;

                float3 offsetRayOrigin = ray.origin - sphereCenter;

                float a = dot(ray.dir, ray.dir);
                float b = 2.0 * dot(offsetRayOrigin, ray.dir);
                float c = dot(offsetRayOrigin, offsetRayOrigin) - sphereRadius * sphereRadius;

                float discriminant = b * b - 4.0 * a * c;

                if (discriminant < 0.0)
                    return hitInfo; // didHit stays false

                float sqrtD = sqrt(discriminant);

                // closer root
                float t = (-b - sqrtD) / (2.0 * a);

                // if behind camera, try the other root
                if (t < 0.0)
                    t = (-b + sqrtD) / (2.0 * a);

                if (t < 0.0)
                    return hitInfo;

                hitInfo.didHit   = true;
                hitInfo.dst      = t;
                hitInfo.hitPoint = ray.origin + ray.dir * t;
                hitInfo.normal   = normalize(hitInfo.hitPoint - sphereCenter);

                return hitInfo;
            }

            float3 SphereCols[64];
            float3 SphereEmissions[64];
            float  SphereEmissionStrengths[64];
            float3 SpherePositions[64];
            float  SphereRadiuses[64];
            int    NumSpheres;
            int    MaxBounces; // set this from C# with SetInt
            int    raysPerPixel; // set this from C# with SetInt

            HitInfo CalculateRayCollision(Ray ray)
            {
                HitInfo closestHit = (HitInfo)0;
                closestHit.didHit = false;
                closestHit.dst = 1e20;

                for (int i = 0; i < NumSpheres; i++)
                {
                    float3 pos    = SpherePositions[i];
                    float  radius = SphereRadiuses[i];

                    HitInfo hitInfo = RaySphere(ray, pos, radius);

                    if (hitInfo.didHit && hitInfo.dst < closestHit.dst)
                    {
                        closestHit = hitInfo;

                        // Fill material from the arrays you upload from C#
                        RayTracingMaterial mat;
                        mat.colour            = SphereCols[i];
                        mat.emission          = SphereEmissions[i];
                        mat.emissionStrength  = SphereEmissionStrengths[i];

                        closestHit.material = mat;
                    }
                }

                return closestHit;
            }

            float RandomValue(inout uint state)
            {
                state = state * 747796405 + 2891336453;
                uint result = ((state >> ((state >> 28) + 4)) ^ state) * 277803737;
                result = (result >> 22) ^ result;
                return result / 4294967295.0;
            }
            
            float RandomValueNormal(inout uint state)
            {
                float theta = 2 * 3.14159265 * RandomValue(state);
                float rho = sqrt(-2 * log(RandomValue(state)));
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
                float3 dir = RandomDirection(state);
                return dir * sign(dot(normal, dir));
            }

            float3 GetEnvironmentColour(Ray ray)
            {
                float skyGradientT = pow(smoothstep(0, 0.4, ray.dir.y), 0.35);
                float3 skyGradient = lerp(float3(0.6, 0.8, 1.0), float3(0.1, 0.2, 0.4), skyGradientT);
                float sun = pow(max(0, dot(ray.dir, -normalize(float3(1, 1, 0)))), 200) * 3;

                float groundToSkyT = smoothstep(-0.1, 0, ray.dir.y);
                float sunMask = groundToSkyT >= 1;
                return lerp(float3(0.2, 0.1, 0.8), skyGradient, groundToSkyT) + sun * sunMask;
            }

            float3 Trace(Ray ray, inout uint state)
            {
                float3 incomingLight = 0;
                float3 rayColour = 1;

                for (int i = 0; i < MaxBounces + 1; i++)
                {
                    HitInfo hitInfo = CalculateRayCollision(ray);
                    if (!hitInfo.didHit)
                    {
                        incomingLight += rayColour * GetEnvironmentColour(ray);
                        break;
                    }

                    RayTracingMaterial mat = hitInfo.material;

                    float3 emission = mat.emission * mat.emissionStrength;
                    incomingLight += rayColour * emission;

                    float3 newDir = RandomHemisphereDirection(hitInfo.normal, state);
                    float  cosTheta = max(0, dot(newDir, hitInfo.normal));

                    rayColour *= mat.colour * cosTheta;

                    ray.origin = hitInfo.hitPoint + hitInfo.normal * 0.001;
                    ray.dir    = newDir;
                }

                return incomingLight;
            }

            float4 frag (v2f i) : SV_Target
            {
                // Camera position & basis from matrix
                float3 camPos     = mul(CamLocalToWorldMatrix, float4(0, 0, 0, 1)).xyz;
                float3 camForward = normalize(mul(CamLocalToWorldMatrix, float4(0, 0, 1, 0)).xyz);
                float3 camRight   = normalize(mul(CamLocalToWorldMatrix, float4(1, 0, 0, 0)).xyz);
                float3 camUp      = normalize(mul(CamLocalToWorldMatrix, float4(0, 1, 0, 0)).xyz);

                // NDC coordinates in [-1, 1]
                float2 ndc = i.uv * 2.0 - 1.0;

                // viewParams.x = tan(fov/2)*aspect
                // viewParams.y = tan(fov/2)
                float3 dirCamera = normalize(float3(ndc.x * viewParams.x, ndc.y * viewParams.y, 1.0));

                // Transform camera-space ray direction into world space
                float3 dirWorld =
                    dirCamera.x * camRight +
                    dirCamera.y * camUp +
                    dirCamera.z * camForward;
                dirWorld = normalize(dirWorld);

                // Seed for RNG (slightly less cursed)
                uint state = asuint(i.uv.x * 1234.567) ^ asuint(i.uv.y * 3456.789);

                float3 col = 0;
                for (int i = 0; i < raysPerPixel; i++)
                {
                    Ray ray;
                    ray.origin = camPos;
                    ray.dir    = dirWorld;
                    col += Trace(ray, state);
                }
                col /= raysPerPixel;
                return float4(col, 0.0);
            }
            ENDCG
        }
    }
}