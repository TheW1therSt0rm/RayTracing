using UnityEngine;

[RequireComponent(typeof(MeshFilter))]
public class MeshObject : MonoBehaviour
{
    // Reuse your RayTracingMaterial from SphereObject.cs
    public RayTracingMaterial material;

    [Header("Material Settings")]
    public Color colour = Color.white;
    public Color emission = Color.black;
    public float emissionStrength = 0.0f;

    void Awake()
    {
        SyncMaterial();
    }

    void OnValidate()
    {
        SyncMaterial();
    }

    void Update()
    {
        SyncMaterial();
    }

    void SyncMaterial()
    {
        material.colour = colour;
        material.emission = emission;
        material.emissionStrength = emissionStrength;
    }
}