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
    public float radius = 1.0f;

    void Start()
    {
        sphere.position = transform.position;
        sphere.material.colour = colour;
        sphere.radius = 1.0f;
    }

    void OnValidate()
    {
        sphere.position = transform.position;
        sphere.material.colour = colour;
        sphere.radius = radius;
    }

    void Update()
    {
        sphere.position = transform.position;
        sphere.material.colour = colour;
        sphere.radius = radius;
    }
}