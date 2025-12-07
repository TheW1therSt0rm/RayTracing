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

    void UpdateCameraParams(Camera cam)
    {
        float planeHeight = cam.nearClipPlane * Mathf.Tan(cam.fieldOfView * 0.5f * Mathf.Deg2Rad) * 2f;
        float planeWidth = planeHeight * cam.aspect;

        rayTracingMaterial.SetVector("viewParams", new Vector3(planeWidth, planeHeight, cam.nearClipPlane));
        rayTracingMaterial.SetMatrix("CamLocalToWorldMatrix", cam.transform.localToWorldMatrix);
    }
}