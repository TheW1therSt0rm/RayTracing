using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;

[ExecuteAlways, ImageEffectAllowedInSceneView]
[RequireComponent(typeof(Camera))]
public class RayTracingManager : MonoBehaviour
{
    const int MAX_SPHERES    = 64;
    const int MAX_TRIANGLES  = 8192; // tweak as needed

    [SerializeField] bool   useShaderInSceneView = true;
    [SerializeField] Shader rayTracingShader;
    [SerializeField] int    maxBounces   = 3;
    [SerializeField] int    raysPerPixel = 10;
    [SerializeField] Vector2 numPixels  = new(1280f, 1080f);
    public Material rayTracingMaterial;

    // Shader property IDs
    static readonly int ViewParamsID       = Shader.PropertyToID("viewParams");
    static readonly int CamLocalToWorldID  = Shader.PropertyToID("CamLocalToWorldMatrix");
    static readonly int NumSpheresID       = Shader.PropertyToID("NumSpheres");
    static readonly int MaxBouncesID       = Shader.PropertyToID("MaxBounces");
    static readonly int RaysPerPixelID     = Shader.PropertyToID("raysPerPixel");
    static readonly int NumPixelsID        = Shader.PropertyToID("numPixels");
    static readonly int SphereBufferID     = Shader.PropertyToID("_Spheres");

    static readonly int TriangleBufferID   = Shader.PropertyToID("_Triangles");
    static readonly int NumTrianglesID     = Shader.PropertyToID("NumTriangles");

    ComputeBuffer sphereBuffer;
    ComputeBuffer triangleBuffer;

    // Must match HLSL layout for spheres
    [StructLayout(LayoutKind.Sequential)]
    struct SphereData
    {
        public Vector3 position;
        public float radius;

        public Vector3 colour;
        public float pad0; // keep 16-byte alignment

        public Vector3 emission;
        public float emissionStrength;
    }

    // Must match HLSL layout for triangles
    [StructLayout(LayoutKind.Sequential)]
    struct TriangleData
    {
        public Vector3 v0;
        public float pad0;

        public Vector3 v1;
        public float pad1;

        public Vector3 v2;
        public float pad2;

        public Vector3 normal;
        public float pad3;

        public Vector3 colour;
        public float pad4;

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
        sphereBuffer?.Release();
        sphereBuffer = null;
        triangleBuffer?.Release();
        triangleBuffer = null;
    }

    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (!TryGetComponent<Camera>(out var cam))
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

        // ------------------------------------------------------
        // 1) Gather spheres
        // ------------------------------------------------------
        SphereObject[] sphereObjects = FindObjectsOfType<SphereObject>();
        int sphereCount = Mathf.Min(sphereObjects.Length, MAX_SPHERES);

        // Debug.Log($"[RayTracing] Found {sphereCount} spheres");

        SphereData[] sphereData = sphereCount > 0 ? new SphereData[sphereCount] : null;

        for (int i = 0; i < sphereCount; i++)
        {
            SphereObject sp = sphereObjects[i];
            var s = sp.sphere;

            SphereData data = new()
            {
                position = s.position,
                radius = s.radius
            };

            Color col = s.material.colour;
            data.colour = new Vector3(col.r, col.g, col.b);
            data.pad0   = 0f;

            Color emission = s.material.emission;
            data.emission = new Vector3(emission.r, emission.g, emission.b);
            data.emissionStrength = s.material.emissionStrength;

            sphereData[i] = data;
        }

        // Upload spheres
        if (sphereCount > 0)
        {
            int stride = Marshal.SizeOf(typeof(SphereData));

            if (sphereBuffer == null || sphereBuffer.count != sphereCount || sphereBuffer.stride != stride)
            {
                sphereBuffer?.Release();
                sphereBuffer = null;

                sphereBuffer = new ComputeBuffer(sphereCount, stride);
            }

            sphereBuffer.SetData(sphereData);
            rayTracingMaterial.SetBuffer(SphereBufferID, sphereBuffer);
        }
        else
        {
            sphereBuffer?.Release();
            sphereBuffer = null;
        }

        rayTracingMaterial.SetInt(NumSpheresID, sphereCount);

        // ------------------------------------------------------
        // 2) Gather mesh triangles
        // ------------------------------------------------------
        MeshObject[] meshObjects = FindObjectsOfType<MeshObject>();
        List<TriangleData> triList = new();

        foreach (var mObj in meshObjects)
        {
            if (!mObj.TryGetComponent<MeshFilter>(out var mf)) continue;

            Mesh mesh = mf.sharedMesh;
            if (mesh == null) continue;

            Vector3[] verts   = mesh.vertices;
            Vector3[] normals = mesh.normals;
            int[] tris        = mesh.triangles;

            // If no normals, we can still compute per-triangle normals
            bool hasNormals = normals != null && normals.Length == verts.Length;

            Color col = mObj.material.colour;
            Color em  = mObj.material.emission;
            float emissionStrength = mObj.material.emissionStrength;

            Transform t = mObj.transform;

            for (int i = 0; i < tris.Length && triList.Count < MAX_TRIANGLES; i += 3)
            {
                int i0 = tris[i + 0];
                int i1 = tris[i + 1];
                int i2 = tris[i + 2];

                Vector3 v0 = t.TransformPoint(verts[i0]);
                Vector3 v1 = t.TransformPoint(verts[i1]);
                Vector3 v2 = t.TransformPoint(verts[i2]);

                Vector3 n;
                if (hasNormals)
                {
                    Vector3 n0 = t.TransformDirection(normals[i0]);
                    Vector3 n1 = t.TransformDirection(normals[i1]);
                    Vector3 n2 = t.TransformDirection(normals[i2]);
                    n = (n0 + n1 + n2) / 3f;
                }
                else
                {
                    n = Vector3.Normalize(Vector3.Cross(v1 - v0, v2 - v0));
                }

                TriangleData td = new()
                {
                    v0 = v0,
                    pad0 = 0f,
                    v1 = v1,
                    pad1 = 0f,
                    v2 = v2,
                    pad2 = 0f,
                    normal = n,
                    pad3 = 0f,
                    colour = new Vector3(col.r, col.g, col.b),
                    pad4 = 0f,
                    emission = new Vector3(em.r, em.g, em.b),
                    emissionStrength = emissionStrength
                };

                triList.Add(td);
            }

            if (triList.Count >= MAX_TRIANGLES)
                break;
        }

        int triCount = triList.Count;

        if (triCount > 0)
        {
            TriangleData[] triArray = triList.ToArray();
            int stride = Marshal.SizeOf(typeof(TriangleData));

            if (triangleBuffer == null || triangleBuffer.count != triCount || triangleBuffer.stride != stride)
            {
                triangleBuffer?.Release();
                triangleBuffer = null;

                triangleBuffer = new ComputeBuffer(triCount, stride);
            }

            triangleBuffer.SetData(triArray);
            rayTracingMaterial.SetBuffer(TriangleBufferID, triangleBuffer);
        }
        else
        {
            triangleBuffer?.Release();
            triangleBuffer = null;
        }

        rayTracingMaterial.SetInt(NumTrianglesID, triCount);

        // ------------------------------------------------------
        // 3) Shared params
        // ------------------------------------------------------
        rayTracingMaterial.SetInt(MaxBouncesID, maxBounces);
        rayTracingMaterial.SetInt(RaysPerPixelID, raysPerPixel);
        rayTracingMaterial.SetVector(NumPixelsID, new Vector4(numPixels.x, numPixels.y, 0f, 0f));
    }
}