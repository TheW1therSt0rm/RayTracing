using UnityEngine;

public struct RayTracingMaterial
{
    public Color colour;
    public Color emission;
    public float emissionStrength;
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
    public Color emission = Color.black;
    public float emissionStrength = 0.0f;
    public float radius = 1.0f;

    void Start()
    {
        sphere.position = transform.position;
        sphere.material.colour = colour;
        sphere.radius = 1.0f;
    }

    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        sphere.position = transform.position;
        sphere.material.colour = colour;
        sphere.material.emission = emission;
        sphere.material.emissionStrength = emissionStrength;
        sphere.radius = transform.localScale.x * 0.5f;
    }

    void OnValidate()
    {
        sphere.position = transform.position;
        sphere.material.colour = colour;
        sphere.material.emission = emission;
        sphere.material.emissionStrength = emissionStrength;
        sphere.radius = transform.localScale.x * 0.5f;
    }

    void Update()
    {
        sphere.position = transform.position;
        sphere.material.colour = colour;
        sphere.material.emission = emission;
        sphere.material.emissionStrength = emissionStrength;
        sphere.radius = transform.localScale.x * 0.5f;
    }
}