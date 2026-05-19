// SpatialAnchorManager.cs
// ─────────────────────────────────────────────────────────────────────────────
// AR Foundation & SLAM Spatial Anchor Management Layer
// ─────────────────────────────────────────────────────────────────────────────

using System.Collections.Generic;
using UnityEngine;
using UnityEngine.XR.ARFoundation;

namespace SmartCampus.SpatialAR
{
    [RequireComponent(typeof(ARAnchorManager))]
    public class SpatialAnchorManager : MonoBehaviour
    {
        private ARAnchorManager anchorManager;
        private List<ARAnchor> activeAnchors = new List<ARAnchor>();

        void Awake()
        {
            anchorManager = GetComponent<ARAnchorManager>();
        }

        /// <summary>
        /// Pins a stable SLAM spatial anchor in physical space at the specified Pose.
        /// </summary>
        public ARAnchor LockSpatialAnchor(Pose worldPose)
        {
            // Instantiates a native spatial tracking anchor pinned to local physics
            GameObject anchorObj = new GameObject("SLAM_Corner_Anchor");
            anchorObj.transform.position = worldPose.position;
            anchorObj.transform.rotation = worldPose.rotation;

            ARAnchor anchor = anchorObj.AddComponent<ARAnchor>();
            if (anchor != null)
            {
                activeAnchors.Add(anchor);
                Debug.Log($"[SpatialAnchorManager] Locked stable SLAM anchor at: {worldPose.position}");
                return anchor;
            }

            Destroy(anchorObj);
            return null;
        }

        /// <summary>
        /// Flushes all spatial anchors to reset tracking boundaries.
        /// </summary>
        public void ClearAllAnchors()
        {
            foreach (var anchor in activeAnchors)
            {
                if (anchor != null)
                {
                    Destroy(anchor.gameObject);
                }
            }
            activeAnchors.Clear();
            Debug.Log("[SpatialAnchorManager] All spatial anchors flushed.");
        }

        /// <summary>
        /// Retrieves the exact, drift-compensated world positions of all locked anchors.
        /// </summary>
        public List<Vector3> GetAnchorPositions()
        {
            List<Vector3> positions = new List<Vector3>();
            foreach (var anchor in activeAnchors)
            {
                if (anchor != null)
                {
                    positions.Add(anchor.transform.position);
                }
            }
            return positions;
        }
    }
}
