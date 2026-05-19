using UnityEngine;
using System.Collections.Generic;

public class RoomMeshGenerator
{
    private readonly List<ARSpatialCorner> _corners;
    private readonly float _wallHeight;
    private readonly Material _wallMaterial;
    private readonly Material _floorMaterial;

    public RoomMeshGenerator(
        List<ARSpatialCorner> corners,
        float wallHeight,
        Material wallMaterial,
        Material floorMaterial)
    {
        _corners = corners;
        _wallHeight = wallHeight;
        _wallMaterial = wallMaterial;
        _floorMaterial = floorMaterial;
    }

    public void Generate(GameObject parent)
    {
        GenerateFloor(parent);
        GenerateWalls(parent);
        GenerateCeiling(parent);
    }

    private void GenerateFloor(GameObject parent)
    {
        int n = _corners.Count;
        var vertices = new Vector3[n];
        for (int i = 0; i < n; i++)
            vertices[i] = new Vector3(_corners[i].worldX, _corners[i].worldY, _corners[i].worldZ);

        var triangles = Triangulate(n);
        CreateMeshObject(parent, "Floor", vertices, triangles, _floorMaterial);
    }

    private void GenerateWalls(GameObject parent)
    {
        int n = _corners.Count;
        for (int i = 0; i < n; i++)
        {
            int j = (i + 1) % n;
            var c1 = _corners[i];
            var c2 = _corners[j];

            var vertices = new Vector3[]
            {
                new(c1.worldX, c1.worldY, c1.worldZ),
                new(c2.worldX, c2.worldY, c2.worldZ),
                new(c2.worldX, c2.worldY + _wallHeight, c2.worldZ),
                new(c1.worldX, c1.worldY + _wallHeight, c1.worldZ),
            };

            var triangles = new int[] { 0, 1, 2, 0, 2, 3 };
            CreateMeshObject(parent, $"Wall_{i + 1}", vertices, triangles, _wallMaterial);
        }
    }

    private void GenerateCeiling(GameObject parent)
    {
        int n = _corners.Count;
        var vertices = new Vector3[n];
        for (int i = 0; i < n; i++)
            vertices[i] = new Vector3(
                _corners[i].worldX,
                _corners[i].worldY + _wallHeight,
                _corners[i].worldZ);

        var triangles = Triangulate(n);
        // Reverse winding for ceiling (faces down)
        for (int i = 0; i < triangles.Length; i += 3)
            (triangles[i], triangles[i + 2]) = (triangles[i + 2], triangles[i]);

        var ceilMat = new Material(_wallMaterial) { color = new Color(0.9f, 0.9f, 0.9f, 0.3f) };
        CreateMeshObject(parent, "Ceiling", vertices, triangles, ceilMat);
    }

    private static int[] Triangulate(int n)
    {
        // Simple fan triangulation from vertex 0
        var triangles = new int[(n - 2) * 3];
        for (int i = 0; i < n - 2; i++)
        {
            triangles[i * 3 + 0] = 0;
            triangles[i * 3 + 1] = i + 1;
            triangles[i * 3 + 2] = i + 2;
        }
        return triangles;
    }

    private static void CreateMeshObject(
        GameObject parent, string name,
        Vector3[] vertices, int[] triangles, Material material)
    {
        var go = new GameObject(name);
        go.transform.SetParent(parent.transform, true);

        var mesh = new Mesh { name = name };
        mesh.SetVertices(vertices);
        mesh.SetTriangles(triangles, 0);
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();

        go.AddComponent<MeshFilter>().sharedMesh = mesh;
        go.AddComponent<MeshRenderer>().sharedMaterial = material;
    }
}
