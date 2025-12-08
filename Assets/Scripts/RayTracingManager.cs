using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteAlways, ImageEffectAllowedInSceneView]
public class RayTracingManager : MonoBehaviour
{
    [SerializeField] bool useShaderInSceneView;
    [SerializeField] Shader rayTracingShader;
    public Material rayTracingMaterial;

    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (Camera.current.name != "SceneCamera" || useShaderInSceneView) {
            if (rayTracingMaterial == null)
            {
                rayTracingMaterial = new Material(rayTracingShader)
                {
                    hideFlags = HideFlags.HideAndDontSave
                };
            }

            UpdateCameraParams(Camera.current);

            Graphics.Blit(null, destination, rayTracingMaterial);
        }
        else {
            Graphics.Blit(source, destination);
        }
    }

    struct RayTracingMaterial
    {
        public Vector3 colour;
    }

    struct Sphere
    {
        public Vector3 position;
        public float radius;
        public RayTracingMaterial material;
    }

    void UpdateCameraParams(Camera cam)
    {
        float planeHeight = cam.nearClipPlane * Mathf.Tan(cam.fieldOfView * 0.5f * Mathf.Deg2Rad) * 2f;
        float planeWidth  = planeHeight * cam.aspect;

        rayTracingMaterial.SetVector("viewParams", new Vector3(planeWidth, planeHeight, cam.nearClipPlane));
        rayTracingMaterial.SetMatrix("CamLocalToWorldMatrix", cam.transform.localToWorldMatrix);

        SphereObject[] sphereObjects = FindObjectsOfType<SphereObject>();
        int count = Mathf.Min(sphereObjects.Length, 64); // match MAX_SPHERES

        rayTracingMaterial.SetInt("NumSpheres", count);

        for (int i = 0; i < count; i++)
        {
            SphereObject sp = sphereObjects[i];
            Sphere s = new()
            {
                position = sp.sphere.position,
                radius = sp.sphere.radius,
                material = new RayTracingMaterial()
                {
                    colour = new Vector3(sp.sphere.material.colour.r,
                                         sp.sphere.material.colour.g,
                                         sp.sphere.material.colour.b)
                }
            };

            // position (pad to Vector4 is fine)
            rayTracingMaterial.SetVector($"SpherePositions[{i}]",
                new Vector4(s.position.x, s.position.y, s.position.z, 1));

            // radius
            rayTracingMaterial.SetFloat($"SphereRadiuses[{i}]", s.radius);
            // colour
            rayTracingMaterial.SetColor($"SphereCols[{i}]", new Color(s.material.colour.x, s.material.colour.y, s.material.colour.z));
        }
    }
}