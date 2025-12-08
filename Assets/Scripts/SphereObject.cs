using UnityEngine;

public struct RayTracingMaterial
{
    public Color colour;
}

public struct Sphere
{
    public Vector3 position;
    public float radius;
    public RayTracingMaterial material;
}

public class SphereObject : MonoBehaviour
{
    public Sphere sphere;
    public Color colour = Color.white;

    void OnValidate()
    {
        sphere.position = transform.position;
        sphere.material.colour = colour;
    }

    void Update()
    {
        sphere.position = transform.position;
        sphere.material.colour = colour;
    }
}