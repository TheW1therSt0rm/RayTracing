using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteAlways] // so it also runs in Edit mode
[RequireComponent(typeof(Camera))]
public class CamTest : MonoBehaviour
{
    public Camera cam;      // Assign your camera here (or it will auto-grab)
    public int cols = 10;   // How many points across
    public int rows = 6;    // How many points down
    public float depth = 5f;      // Distance in front of the camera
    public float pointSize = 0.05f;
    public Color colour = Color.white;

    // This gets filled in Update and read in OnDrawGizmos
    private List<Vector3> gridPoints = new List<Vector3>();

    void OnValidate()
    {
        cols = Mathf.Max(2, cols);
        rows = Mathf.Max(2, rows);
    }

    void Reset()
    {
        cam = GetComponent<Camera>();
    }

    void Update()
    {
        if (cam == null) cam = GetComponent<Camera>();
        if (cam == null) return;

        gridPoints.Clear();

        // Loop over a grid in *screen space* (0..Screen.width, 0..Screen.height)
        for (int y = 0; y < rows; y++)
        {
            float v = (float)y / (rows - 1); // 0..1
            float screenY = v * cam.pixelHeight;

            for (int x = 0; x < cols; x++)
            {
                float u = (float)x / (cols - 1); // 0..1
                float screenX = u * cam.pixelWidth;

                // Build screen position (x, y, depth from camera)
                Vector3 screenPos = new Vector3(screenX, screenY, depth);

                // Convert to world position
                Vector3 worldPos = cam.ScreenToWorldPoint(screenPos);

                gridPoints.Add(worldPos);
            }
        }
    }

    void OnDrawGizmos()
    {
        if (gridPoints == null || gridPoints.Count == 0)
            return;

        Gizmos.color = colour;

        foreach (var p in gridPoints)
        {
            Gizmos.DrawSphere(p, pointSize);
        }
    }
}