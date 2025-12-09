using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;

[ExecuteAlways, ImageEffectAllowedInSceneView]
[RequireComponent(typeof(Camera))]
public class RayTracingManager : MonoBehaviour
{
    const int MAX_SPHERES = 64;

    [SerializeField] bool useShaderInSceneView = true;
    [SerializeField] Shader rayTracingShader;
    [SerializeField] int maxBounces = 30;
    [SerializeField] int raysPerPixel = 100;
    [SerializeField] Vector2 numPixels = new(1280f, 1080f);
    public Material rayTracingMaterial;

    static readonly int ViewParamsID      = Shader.PropertyToID("viewParams");
    static readonly int CamLocalToWorldID = Shader.PropertyToID("CamLocalToWorldMatrix");
    static readonly int NumSpheresID      = Shader.PropertyToID("NumSpheres");
    static readonly int MaxBouncesID      = Shader.PropertyToID("MaxBounces");
    static readonly int RaysPerPixelID    = Shader.PropertyToID("raysPerPixel");
    static readonly int NumPixelsID       = Shader.PropertyToID("numPixels");
    static readonly int SphereBufferID    = Shader.PropertyToID("_Spheres");

    ComputeBuffer sphereBuffer;

    [StructLayout(LayoutKind.Sequential)]
    struct SphereData
    {
        public Vector3 position;
        public float radius;

        public Vector3 colour;
        public float pad0; // keep 16-byte alignment (matches HLSL)

        public Vector3 emission;
        public float emissionStrength;
    }

    void OnDisable()
    {
        ReleaseBuffers();
    }

    void OnDestroy()
    {
        ReleaseBuffers();
    }

    void ReleaseBuffers()
    {
        if (sphereBuffer != null)
        {
            sphereBuffer.Release();
            sphereBuffer = null;
        }
    }

    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        var cam = GetComponent<Camera>();
        if (cam == null)
        {
            Graphics.Blit(source, destination);
            return;
        }

        // Only run in game view unless toggled
        if (Camera.current.name != "SceneCamera" || useShaderInSceneView)
        {
            if (rayTracingMaterial == null)
            {
                rayTracingMaterial = new Material(rayTracingShader)
                {
                    hideFlags = HideFlags.HideAndDontSave
                };
            }

            UpdateCameraParams(cam);
            Graphics.Blit(null, destination, rayTracingMaterial);
        }
        else
        {
            Graphics.Blit(source, destination);
        }
    }

    void UpdateCameraParams(Camera cam)
    {
        // Ray generation params based on FOV
        float halfHeight = Mathf.Tan(cam.fieldOfView * 0.5f * Mathf.Deg2Rad);
        float halfWidth  = halfHeight * cam.aspect;

        rayTracingMaterial.SetVector(ViewParamsID, new Vector3(halfWidth, halfHeight, 0.0f));
        rayTracingMaterial.SetMatrix(CamLocalToWorldID, cam.transform.localToWorldMatrix);

        // Gather spheres from the scene
        SphereObject[] sphereObjects = FindObjectsOfType<SphereObject>();
        int count = Mathf.Min(sphereObjects.Length, MAX_SPHERES);

        Debug.Log($"[RayTracing] Found {count} spheres");

        // Build CPU-side struct array for GPU upload
        SphereData[] sphereData = count > 0 ? new SphereData[count] : null;

        for (int i = 0; i < count; i++)
        {
            SphereObject sp = sphereObjects[i];
            var s = sp.sphere;

            SphereData data = new SphereData();

            data.position = s.position;
            data.radius   = s.radius;

            Color col = s.material.colour;
            data.colour = new Vector3(col.r, col.g, col.b);
            data.pad0   = 0f;

            Color emission = s.material.emission;
            data.emission = new Vector3(emission.r, emission.g, emission.b);
            data.emissionStrength = s.material.emissionStrength;

            sphereData[i] = data;
        }

        // Upload to GPU via ComputeBuffer
        if (count > 0)
        {
            int stride = Marshal.SizeOf(typeof(SphereData));

            if (sphereBuffer == null || sphereBuffer.count != count || sphereBuffer.stride != stride)
            {
                ReleaseBuffers();
                sphereBuffer = new ComputeBuffer(count, stride);
            }

            sphereBuffer.SetData(sphereData);
            rayTracingMaterial.SetBuffer(SphereBufferID, sphereBuffer);
        }
        else
        {
            // No spheres – free buffer
            ReleaseBuffers();
        }

        rayTracingMaterial.SetInt(NumSpheresID, count);
        rayTracingMaterial.SetInt(MaxBouncesID, maxBounces);
        rayTracingMaterial.SetInt(RaysPerPixelID, raysPerPixel);
        rayTracingMaterial.SetVector(NumPixelsID, new Vector4(numPixels.x, numPixels.y, 0f, 0f));
    }
}