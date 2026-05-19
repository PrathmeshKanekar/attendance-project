// CoordinateManager.cs
// ─────────────────────────────────────────────────────────────────────────────
// Production-grade AR Local Coordinate Transformation & Pose Tracking Engine
// ─────────────────────────────────────────────────────────────────────────────

using System;
using System.Collections.Generic;
using UnityEngine;

namespace SmartCampus.SpatialAR
{
    public class CoordinateManager : MonoBehaviour
    {
        private Vector3 originPosition = Vector3.zero;
        private Quaternion originRotation = Quaternion.identity;
        private bool isOriginSet = false;

        /// <summary>
        /// Registers the first captured corner as the local spatial coordinate system origin.
        /// </summary>
        public void EstablishOrigin(Vector3 worldPos, Quaternion worldRot)
        {
            originPosition = worldPos;
            originRotation = worldRot;
            isOriginSet = true;
            Debug.Log($"[CoordinateManager] Spatial Origin established at World: {worldPos}");
        }

        /// <summary>
        /// Reverts the tracking origin back to raw world values.
        /// </summary>
        public void ResetOrigin()
        {
            isOriginSet = false;
            originPosition = Vector3.zero;
            originRotation = Quaternion.identity;
        }

        /// <summary>
        /// Converts a raw Unity world coordinate to local origin-relative XYZ space.
        /// </summary>
        public Vector3 GetLocalCoordinates(Vector3 worldPos)
        {
            if (!isOriginSet) return worldPos;

            // Compute offset from origin position
            Vector3 offset = worldPos - originPosition;

            // Rotate relative to origin rotation to establish local coordinate alignment
            return Quaternion.Inverse(originRotation) * offset;
        }

        /// <summary>
        /// Computes the exact 2D Shoelace area of the closed local coordinate footprint.
        /// </summary>
        public float CalculateFloorArea(List<Vector3> localCorners)
        {
            if (localCorners == null || localCorners.Count < 3) return 0f;

            float area = 0f;
            int n = localCorners.Count;

            for (int i = 0; i < n; i++)
            {
                int j = (i + 1) % n;
                // Shoelace formula in horizontal plane (X and Z in Unity world coordinates)
                area += localCorners[i].x * localCorners[j].z;
                area -= localCorners[j].x * localCorners[i].z;
            }

            return Mathf.Abs(area) / 2f;
        }

        /// <summary>
        /// Computes the absolute perimeter distance of the room corners.
        /// </summary>
        public float CalculatePerimeter(List<Vector3> localCorners)
        {
            if (localCorners == null || localCorners.Count < 2) return 0f;

            float perimeter = 0f;
            int n = localCorners.Count;

            for (int i = 0; i < n; i++)
            {
                int j = (i + 1) % n;
                perimeter += Vector3.Distance(localCorners[i], localCorners[j]);
            }

            return perimeter;
        }
    }
}
