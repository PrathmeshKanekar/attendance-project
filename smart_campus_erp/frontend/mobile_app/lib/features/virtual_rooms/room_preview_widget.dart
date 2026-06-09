import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../../core/config/map_config.dart';

class RoomPreviewWidget extends StatefulWidget {
  final double centerLat;
  final double centerLng;
  final double widthMeters;
  final double lengthMeters;
  final double rotationDegrees;
  final double confidenceScore;
  final double height;
  final bool interactive;
  final List<LatLng>? roomPolygonPoints;
  
  // Callback when user interactively edits geometry via HUD controls
  final Function(double newLat, double newLng, double newWidth, double newLength, double newRotation)? onGeometryChanged;

  const RoomPreviewWidget({
    Key? key,
    required this.centerLat,
    required this.centerLng,
    required this.widthMeters,
    required this.lengthMeters,
    required this.rotationDegrees,
    this.confidenceScore = 100.0,
    this.height = 340.0,
    this.interactive = true,
    this.roomPolygonPoints,
    this.onGeometryChanged,
  }) : super(key: key);

  @override
  State<RoomPreviewWidget> createState() => _RoomPreviewWidgetState();
}

class _RoomPreviewWidgetState extends State<RoomPreviewWidget> {
  StreamSubscription<Position>? _positionSubscription;
  LatLng? _liveUserLocation;
  late MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _subscribeToLiveLocation();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  // ── Subscribes to live user location for comparative geofencing overlay ─────
  void _subscribeToLiveLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        _positionSubscription = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 1,
          ),
        ).listen((Position pos) {
          if (mounted) {
            setState(() {
              _liveUserLocation = LatLng(pos.latitude, pos.longitude);
            });
          }
        });
      }
    } catch (_) {}
  }

  // ── Rotated Rectangle Geodetic Generator ──────────────────────────────────
  List<LatLng> _generateRotatedRectangle() {
    if (widget.centerLat == 0.0 && widget.centerLng == 0.0) return [];

    final double latRad = widget.centerLat * math.pi / 180.0;
    
    // Exact WGS84 length of one degree of latitude & longitude in meters
    const double metersPerDegreeLat = 110574.0;
    final double metersPerDegreeLng = 111320.0 * math.cos(latRad);
    
    final double rotationRad = widget.rotationDegrees * math.pi / 180.0;
    final cosRot = math.cos(rotationRad);
    final sinRot = math.sin(rotationRad);
    
    final hw = widget.widthMeters / 2.0;
    final hl = widget.lengthMeters / 2.0;
    
    // Unrotated Cartesian corner offsets: (East, North)
    final List<math.Point<double>> unrotatedOffsets = [
      math.Point(hw, hl),    // Corner 1: Top-Right
      math.Point(hw, -hl),   // Corner 2: Bottom-Right
      math.Point(-hw, -hl),  // Corner 3: Bottom-Left
      math.Point(-hw, hl),   // Corner 4: Top-Left
    ];
    
    return unrotatedOffsets.map((p) {
      // Apply clockwise rotation from North
      final dx = p.x * cosRot + p.y * sinRot;
      final dy = -p.x * sinRot + p.y * cosRot;
      
      final latOffset = dy / metersPerDegreeLat;
      final lngOffset = dx / metersPerDegreeLng;
      
      return LatLng(widget.centerLat + latOffset, widget.centerLng + lngOffset);
    }).toList();
  }

  // ── GIS Shift and Tweak Math ──────────────────────────────────────────────
  void _tweakGeometry({
    double dLat = 0.0,
    double dLng = 0.0,
    double dWidth = 0.0,
    double dLength = 0.0,
    double dRotation = 0.0,
  }) {
    if (widget.onGeometryChanged == null) return;
    
    final newLat = widget.centerLat + dLat;
    final newLng = widget.centerLng + dLng;
    final newWidth = (widget.widthMeters + dWidth).clamp(2.0, 100.0);
    final newLength = (widget.lengthMeters + dLength).clamp(2.0, 100.0);
    final newRotation = (widget.rotationDegrees + dRotation + 360.0) % 360.0;

    widget.onGeometryChanged!(newLat, newLng, newWidth, newLength, newRotation);
  }

  // Shifts center in local tangent space (meters)
  void _shiftCenterMeters(double eastMeters, double northMeters) {
    final double latRad = widget.centerLat * math.pi / 180.0;
    const double metersPerDegreeLat = 110574.0;
    final double metersPerDegreeLng = 111320.0 * math.cos(latRad);

    final dLat = northMeters / metersPerDegreeLat;
    final dLng = eastMeters / metersPerDegreeLng;

    _tweakGeometry(dLat: dLat, dLng: dLng);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasCenter = widget.centerLat != 0.0 && widget.centerLng != 0.0;
    if (!hasCenter) {
      return _buildEmptyState(theme, isDark);
    }

    final polyPoints = widget.roomPolygonPoints ?? _generateRotatedRectangle();
    final center = LatLng(widget.centerLat, widget.centerLng);

    return Container(
      height: widget.interactive ? widget.height + 120.0 : widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.primaryColor.withOpacity(0.25),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Column(
          children: [
            // ── Interactive Map Canvas ──────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 19.5,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: MapConfig.urlTemplate,
                        subdomains: MapConfig.subdomains,
                        additionalOptions: MapConfig.headers,
                        userAgentPackageName: MapConfig.userAgentPackageName,
                        maxZoom: 22,
                      ),

                      // Room rotated rectangle polygon layer
                      if (polyPoints.isNotEmpty)
                        PolygonLayer(
                          polygons: [
                            Polygon(
                              points: polyPoints,
                              color: theme.primaryColor.withOpacity(0.18),
                              borderColor: theme.primaryColor,
                              borderStrokeWidth: 3.5,
                            ),
                          ],
                        ),

                      // Center point coordinate pin
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: center,
                            width: 24,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.tealAccent.shade700,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.teal.withOpacity(0.4),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.location_on_rounded, size: 14, color: Colors.white),
                            ),
                          ),
                          
                          // Corner index numerical indicators
                          for (int i = 0; i < polyPoints.length; i++)
                            Marker(
                              point: polyPoints[i],
                              width: 20,
                              height: 20,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Color(0xFF0F172A),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    color: theme.primaryColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),

                          // Live Student Location Indicator
                          if (_liveUserLocation != null)
                            Marker(
                              point: _liveUserLocation!,
                              width: 32,
                              height: 32,
                              child: _LiveLocationMarker(),
                            ),
                        ],
                      ),
                    ],
                  ),

                  // Map Info overlay card
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF1E293B) : Colors.white).withOpacity(0.92),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_tethering_rounded, color: Colors.tealAccent.shade700, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Confidence: ${widget.confidenceScore.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Direction north pointer
                  Positioned(
                    right: 10,
                    top: 10,
                    child: FloatingActionButton.small(
                      onPressed: () => _mapController.move(center, 19.5),
                      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      child: Icon(Icons.my_location_rounded, color: theme.primaryColor),
                    ),
                  ),
                ],
              ),
            ),

            // ── GIS Interactive Calibration Dashboard (HUD) ───────────────────
            if (widget.interactive && widget.onGeometryChanged != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
                child: Column(
                  children: [
                    // Horizontal parameter sliders / increments
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Adjust Length
                        _buildMetricAdjuster(
                          title: 'Width (W)',
                          value: '${widget.widthMeters.toStringAsFixed(1)}m',
                          onSub: () => _tweakGeometry(dWidth: -0.5),
                          onAdd: () => _tweakGeometry(dWidth: 0.5),
                        ),
                        // Adjust Width
                        _buildMetricAdjuster(
                          title: 'Length (L)',
                          value: '${widget.lengthMeters.toStringAsFixed(1)}m',
                          onSub: () => _tweakGeometry(dLength: -0.5),
                          onAdd: () => _tweakGeometry(dLength: 0.5),
                        ),
                        // Adjust Rotation
                        _buildMetricAdjuster(
                          title: 'Yaw/Heading',
                          value: '${widget.rotationDegrees.toStringAsFixed(0)}°',
                          onSub: () => _tweakGeometry(dRotation: -5.0),
                          onAdd: () => _tweakGeometry(dRotation: 5.0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    
                    // Fine-tune displacement coordinates arrow keys
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'MOVE ROOM CENTER:',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey),
                        ),
                        const SizedBox(width: 8),
                        _buildDisplaceButton(Icons.arrow_back_rounded, () => _shiftCenterMeters(-0.3, 0.0)),
                        _buildDisplaceButton(Icons.arrow_upward_rounded, () => _shiftCenterMeters(0.0, 0.3)),
                        _buildDisplaceButton(Icons.arrow_downward_rounded, () => _shiftCenterMeters(0.0, -0.3)),
                        _buildDisplaceButton(Icons.arrow_forward_rounded, () => _shiftCenterMeters(0.3, 0.0)),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isDark) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map_rounded,
              color: theme.disabledColor.withOpacity(0.4),
              size: 56,
            ),
            const SizedBox(height: 12),
            Text(
              'Awaiting GPS Center Lock',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.disabledColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Stand in the middle of the room and calibrate.\nThe generated geofence boundary will appear.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.disabledColor.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricAdjuster({
    required String title,
    required String value,
    required VoidCallback onSub,
    required VoidCallback onAdd,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildSmallCircleButton(Icons.remove_rounded, onSub),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    value,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                _buildSmallCircleButton(Icons.add_rounded, onAdd),
              ],
            )
          ],
        ),
      ],
    );
  }

  Widget _buildSmallCircleButton(IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: 24,
      height: 24,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(icon, size: 14),
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildDisplaceButton(IconData icon, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(icon, size: 14),
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.tealAccent,
        ),
      ),
    );
  }
}

// ─── Live Location Marker Widget ──────────────────────────────────────────
class _LiveLocationMarker extends StatefulWidget {
  @override
  State<_LiveLocationMarker> createState() => _LiveLocationMarkerState();
}

class _LiveLocationMarkerState extends State<_LiveLocationMarker> with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 12 + (_anim.value * 20),
              height: 12 + (_anim.value * 20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(1.0 - _anim.value),
              ),
            ),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ],
        );
      },
    );
  }
}