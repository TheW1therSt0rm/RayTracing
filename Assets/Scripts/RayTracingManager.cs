using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteAlways, ImageEffectAllowedInSceneView]
[RequireComponent(typeof(Camera))]
public class RayTracingManager : MonoBehaviour
{
    const int MAX_SPHERES = 64;

    [SerializeField] bool useShaderInSceneView = true;
    [SerializeField] Shader rayTracingShader;
    public Material rayTracingMaterial;

    static readonly int ViewParamsID      = Shader.PropertyToID("viewParams");
    static readonly int CamLocalToWorldID = Shader.PropertyToID("CamLocalToWorldMatrix");
    static readonly int NumSpheresID      = Shader.PropertyToID("NumSpheres");
    static readonly int SpherePositionsID = Shader.PropertyToID("SpherePositions");
    static readonly int SphereColsID      = Shader.PropertyToID("SphereCols");
    static readonly int SphereRadiusesID  = Shader.PropertyToID("SphereRadiuses");

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

        // Allocate arrays for GPU upload
        var positions = new Vector4[count];
        var colours   = new Vector4[count];
        var radiuses  = new float[count];

        for (int i = 0; i < count; i++)
        {
            SphereObject sp = sphereObjects[i];

            // make sure SphereObject has updated its sphere
            var s = sp.sphere;

            Vector3 pos = s.position;
            float radius = s.radius;
            Color col = s.material.colour;

            positions[i] = new Vector4(pos.x, pos.y, pos.z, 1.0f);
            colours[i]   = new Vector4(col.r, col.g, col.b, 1.0f);
            radiuses[i]  = radius;
        }

        rayTracingMaterial.SetInt(NumSpheresID, count);
        rayTracingMaterial.SetVectorArray(SpherePositionsID, positions);
        rayTracingMaterial.SetVectorArray(SphereColsID,      colours);
        rayTracingMaterial.SetFloatArray(SphereRadiusesID,   radiuses);
    }
}