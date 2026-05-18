using UnityEngine;
using UnityEngine.XR.ARFoundation;
using UnityEngine.XR.ARSubsystems;
using System.Collections.Generic;
using System;
using Newtonsoft.Json;

public class ARRoomCapture : MonoBehaviour
{
    [Header("AR Components")]
    [SerializeField] private ARRaycastManager raycastManager;
    [SerializeField] private ARAnchorManager anchorManager;
    [SerializeField] private ARPlaneManager planeManager;
    [SerializeField] private Camera arCamera;

    [Header("Visual")]
    [SerializeField] private GameObject cornerMarkerPrefab;
    [SerializeField] private LineRenderer roomOutlineRenderer;
    [SerializeField] private Material wallMaterial;
    [SerializeField] private Material floorMaterial;

    private readonly List<ARSpatialCorner> _corners = new();
    private readonly List<GameObject> _markerObjects = new();
    private readonly List<ARAnchor> _anchors = new();
    private ARSpatialCorner _origin;
    private bool _floorDetected = false;
    private float _floorY = 0f;
    private const float WALL_HEIGHT = 3.0f;
    private GameObject _roomMeshParent;

    private static readonly List<ARRaycastHit> _hits = new();

    void Start()
    {
        planeManager.planesChanged += OnPlanesChanged;
        _roomMeshParent = new GameObject("RoomMesh");
    }

    void OnDestroy()
    {
        planeManager.planesChanged -= OnPlanesChanged;
    }

    // Called from Flutter via flutter_unity_widget message
    public void HandleFlutterMessage(string jsonMessage)
    {
        var msg = JsonConvert.DeserializeObject<Dictionary<string, string>>(jsonMessage);
        if (msg == null) return;
        switch (msg.GetValueOrDefault("action"))
        {
            case "capture_corner": CaptureCorner(); break;
            case "undo_corner": UndoLastCorner(); break;
            case "reset": ResetCapture(); break;
            case "finish_room": FinishRoom(); break;
        }
    }

    // ── Plane Detection ────────────────────────────────────────────────────
    private void OnPlanesChanged(ARPlanesChangedEventArgs args)
    {
        foreach (var plane in args.added)
        {
            if (plane.alignment == PlaneAlignment.HorizontalUp && !_floorDetected)
            {
                _floorDetected = true;
                _floorY = plane.transform.position.y;
                SendToFlutter("plane_detected", new { floor_y = _floorY });
            }
        }
    }

    // ── Corner Capture ─────────────────────────────────────────────────────
    public void CaptureCorner()
    {
        // Raycast from screen center to floor plane
        var screenCenter = new Vector2(Screen.width / 2f, Screen.height / 2f);
        if (!raycastManager.Raycast(screenCenter, _hits, TrackableType.PlaneWithinPolygon))
        {
            SendToFlutter("error", new { message = "Point device at the floor and move slowly." });
            return;
        }

        var hitPose = _hits[0].pose;

        // Create spatial anchor at this world point
        var anchorGO = new GameObject($"Anchor_{_corners.Count + 1}");
        anchorGO.transform.SetPositionAndRotation(hitPose.position, hitPose.rotation);
        var anchor = anchorGO.AddComponent<ARAnchor>();
        _anchors.Add(anchor);

        // Compute coordinates relative to origin
        Vector3 worldPos = hitPose.position;
        Vector3 localPos;

        if (_corners.Count == 0)
        {
            // First corner is origin
            _origin = new ARSpatialCorner
            {
                x = 0f, y = 0f, z = 0f,
                worldX = worldPos.x,
                worldY = worldPos.y,
                worldZ = worldPos.z,
                anchorId = anchor.trackableId.ToString(),
                trackingAccuracy = _hits[0].distance < 2f ? 0.02f : 0.05f,
                timestamp = DateTime.UtcNow.ToString("o"),
            };
            _corners.Add(_origin);
            localPos = Vector3.zero;
        }
        else
        {
            // All other corners relative to origin
            localPos = new Vector3(
                worldPos.x - _origin.worldX,
                worldPos.y - _origin.worldY,
                worldPos.z - _origin.worldZ
            );
            var corner = new ARSpatialCorner
            {
                x = localPos.x,
                y = 0f, // floor level
                z = localPos.z,
                worldX = worldPos.x,
                worldY = worldPos.y,
                worldZ = worldPos.z,
                anchorId = anchor.trackableId.ToString(),
                trackingAccuracy = _hits[0].distance < 2f ? 0.02f : 0.05f,
                timestamp = DateTime.UtcNow.ToString("o"),
            };
            _corners.Add(corner);
        }

        // Place visual marker
        var marker = Instantiate(cornerMarkerPrefab, worldPos, Quaternion.identity);
        _markerObjects.Add(marker);

        // Label the marker
        var label = marker.GetComponentInChildren<TMPro.TextMeshPro>();
        if (label != null)
            label.text = $"C{_corners.Count}\n({localPos.x:F2}, {localPos.z:F2})";

        // Update room outline
        UpdateRoomOutline();

        // If 4+ corners, generate mesh
        if (_corners.Count >= 4)
            GenerateRoomMesh();

        // Send data to Flutter
        SendToFlutter("corner_captured", new
        {
            corner_index = _corners.Count,
            x = localPos.x,
            y = 0f,
            z = localPos.z,
            anchor_id = anchor.trackableId.ToString(),
            tracking_accuracy = _corners[_corners.Count - 1].trackingAccuracy,
            timestamp = _corners[_corners.Count - 1].timestamp,
            total_corners = _corners.Count,
        });
    }

    // ── Undo ──────────────────────────────────────────────────────────────
    private void UndoLastCorner()
    {
        if (_corners.Count == 0) return;
        _corners.RemoveAt(_corners.Count - 1);

        if (_markerObjects.Count > 0)
        {
            Destroy(_markerObjects[_markerObjects.Count - 1]);
            _markerObjects.RemoveAt(_markerObjects.Count - 1);
        }
        if (_anchors.Count > 0)
        {
            Destroy(_anchors[_anchors.Count - 1].gameObject);
            _anchors.RemoveAt(_anchors.Count - 1);
        }

        UpdateRoomOutline();
        if (_corners.Count >= 4) GenerateRoomMesh();
        else ClearRoomMesh();

        SendToFlutter("corner_undone", new { remaining_corners = _corners.Count });
    }

    // ── Reset ─────────────────────────────────────────────────────────────
    private void ResetCapture()
    {
        _corners.Clear();
        foreach (var m in _markerObjects) Destroy(m);
        _markerObjects.Clear();
        foreach (var a in _anchors) Destroy(a.gameObject);
        _anchors.Clear();
        _origin = null;
        ClearRoomMesh();
        UpdateRoomOutline();
        SendToFlutter("reset_complete", new { });
    }

    // ── Room Outline ──────────────────────────────────────────────────────
    private void UpdateRoomOutline()
    {
        if (roomOutlineRenderer == null) return;
        if (_corners.Count < 2)
        {
            roomOutlineRenderer.positionCount = 0;
            return;
        }

        int count = _corners.Count;
        roomOutlineRenderer.positionCount = count + 1;
        for (int i = 0; i < count; i++)
            roomOutlineRenderer.SetPosition(i, new Vector3(
                _corners[i].worldX, _corners[i].worldY + 0.01f, _corners[i].worldZ));
        roomOutlineRenderer.SetPosition(count, new Vector3(
            _corners[0].worldX, _corners[0].worldY + 0.01f, _corners[0].worldZ));
    }

    // ── Room Mesh Generation ──────────────────────────────────────────────
    private void GenerateRoomMesh()
    {
        ClearRoomMesh();
        if (_corners.Count < 3) return;

        var generator = new RoomMeshGenerator(_corners, WALL_HEIGHT, wallMaterial, floorMaterial);
        generator.Generate(_roomMeshParent);

        // Compute and send dimensions to Flutter
        float area = CalculatePolygonArea();
        float perimeter = CalculatePerimeter();

        SendToFlutter("room_geometry_updated", new
        {
            corner_count = _corners.Count,
            area_sqm = area,
            perimeter_m = perimeter,
            wall_height_m = WALL_HEIGHT,
        });
    }

    private void ClearRoomMesh()
    {
        foreach (Transform child in _roomMeshParent.transform)
            Destroy(child.gameObject);
    }

    private float CalculatePolygonArea()
    {
        // Shoelace formula on XZ plane
        float area = 0f;
        int n = _corners.Count;
        for (int i = 0; i < n; i++)
        {
            int j = (i + 1) % n;
            area += _corners[i].x * _corners[j].z;
            area -= _corners[j].x * _corners[i].z;
        }
        return Mathf.Abs(area) / 2f;
    }

    private float CalculatePerimeter()
    {
        float total = 0f;
        int n = _corners.Count;
        for (int i = 0; i < n; i++)
        {
            int j = (i + 1) % n;
            float dx = _corners[j].x - _corners[i].x;
            float dz = _corners[j].z - _corners[i].z;
            total += Mathf.Sqrt(dx * dx + dz * dz);
        }
        return total;
    }

    // ── Finish Room ───────────────────────────────────────────────────────
    private void FinishRoom()
    {
        if (_corners.Count < 3)
        {
            SendToFlutter("error", new { message = "Capture at least 3 corners to finish a room." });
            return;
        }

        var export = new
        {
            corners = _corners.ConvertAll(c => new
            {
                x = c.x, y = c.y, z = c.z,
                anchor_id = c.anchorId,
                tracking_accuracy = c.trackingAccuracy,
                timestamp = c.timestamp,
            }),
            area_sqm = CalculatePolygonArea(),
            perimeter_m = CalculatePerimeter(),
            wall_height_m = WALL_HEIGHT,
            corner_count = _corners.Count,
        };

        SendToFlutter("room_finished", export);
    }

    // ── Flutter Bridge ────────────────────────────────────────────────────
    private void SendToFlutter(string eventType, object payload)
    {
        var message = JsonConvert.SerializeObject(new
        {
            @event = eventType,
            data = payload,
            timestamp = DateTime.UtcNow.ToString("o"),
        });
        // flutter_unity_widget communication channel
        Unity.SendMessageToFlutter(message);
    }
}

[Serializable]
public class ARSpatialCorner
{
    public float x, y, z;          // Local coords relative to origin
    public float worldX, worldY, worldZ; // Unity world space
    public string anchorId;
    public float trackingAccuracy;
    public string timestamp;
}
