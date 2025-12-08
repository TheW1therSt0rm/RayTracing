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

[System.Serializable]
public class SphereObject : MonoBehaviour
{
    public Sphere sphere;
}